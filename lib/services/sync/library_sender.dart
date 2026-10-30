// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'snapshot_builder.dart';
import 'sync_manifest.dart';
import 'sync_place.dart';
import 'sync_state_store.dart';

/// Why a Send stopped to ask first.
enum SendConflictKind {
  /// The place holds a library this device never synced with.
  otherLibrary,

  /// Another device sent a library this device hasn't got.
  newerHead,
}

class SendConflict implements Exception {
  const SendConflict(this.kind, this.theirs);

  final SendConflictKind kind;
  final SnapshotEntry? theirs;

  @override
  String toString() => switch (kind) {
    SendConflictKind.otherLibrary =>
      'This sync place holds a different library.',
    SendConflictKind.newerHead =>
      '${theirs?.device ?? 'Another device'} sent a library that this device '
          'hasn\'t got.',
  };
}

/// `latest.json` as parsed, with the tag a conditional write must quote.
typedef PlaceHead = ({RemoteHead head, String tag});

/// Reads and parses the head, or null when the place is empty.
Future<PlaceHead?> readPlaceHead(SyncPlace place) async {
  final read = await place.readHead();
  if (read == null) return null;
  try {
    final json = jsonDecode(utf8.decode(read.bytes)) as Map;
    return (head: RemoteHead.fromJson(json), tag: read.tag);
  } on FormatException catch (e) {
    throw SyncPlaceException('latest.json on the sync place is damaged: $e');
  } on TypeError catch (e) {
    throw SyncPlaceException('latest.json on the sync place is damaged: $e');
  }
}

/// A snapshot's manifest, or null when it isn't there.
Future<SnapshotManifest?> readManifest(SyncPlace place, String id) async {
  final bytes = await place.readFile(manifestPath(id));
  if (bytes == null) return null;
  try {
    return SnapshotManifest.fromJson(jsonDecode(utf8.decode(bytes)) as Map);
  } on FormatException catch (e) {
    throw SyncPlaceException('The snapshot $id is damaged: $e');
  } on TypeError catch (e) {
    throw SyncPlaceException('The snapshot $id is damaged: $e');
  }
}

/// Snapshots kept besides the newest: five more, plus up to three pinned.
const kKeptSnapshots = 5;
const kKeptPinned = 3;

/// How long a blob no snapshot uses waits before it is deleted.
const kTombstoneDelay = Duration(days: 1);

/// Sends one [OutgoingSnapshot] to a [SyncPlace].
///
/// Blobs go up first, then the manifest, and `latest.json` last with the tag
/// that was read, so the place never names a snapshot that isn't all there
/// and two devices can't overwrite each other unseen.
class LibrarySender {
  LibrarySender({
    required this.place,
    required this.state,
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    required this.schemaVersion,
    required this.root,
    DateTime Function()? clock,
    this.onBytes,
  }) : _now = clock ?? DateTime.now;

  final SyncPlace place;
  final SyncStateStore state;
  final String deviceId;
  final String deviceName;
  final String appVersion;
  final int schemaVersion;
  final String root;
  final DateTime Function() _now;

  /// Called with each chunk's size as it goes up.
  final void Function(int bytes, int total)? onBytes;

  /// Throws [SendConflict] when the place holds something this device
  /// hasn't synced, unless [overwriteTheirs].
  void checkConflict(PlaceHead? read, {required bool overwriteTheirs}) {
    if (read == null || overwriteTheirs) return;
    final head = read.head;
    final last = state.lastSync;
    if (last != null && last.libraryId != head.libraryId) {
      throw SendConflict(SendConflictKind.otherLibrary, head.headEntry);
    }
    final ours =
        head.head == last?.snapshotId ||
        head.head == state.pendingSend ||
        head.headEntry?.deviceId == deviceId;
    if (!ours) throw SendConflict(SendConflictKind.newerHead, head.headEntry);
  }

  /// Sends [snap] and returns its snapshot id. Throws [SendConflict],
  /// [HeadChangedException] (another device sent meanwhile) or
  /// [SyncPlaceException].
  Future<String> send(
    OutgoingSnapshot snap, {
    bool overwriteTheirs = false,
  }) async {
    final read = await readPlaceHead(place);
    checkConflict(read, overwriteTheirs: overwriteTheirs);
    final now = _now().toUtc();
    final head = read?.head;
    final libraryId =
        head?.libraryId ?? state.lastSync?.libraryId ?? const Uuid().v4();
    // Sortable by time; the device and a random tail keep two sends in the
    // same millisecond (or from two devices) apart.
    final id =
        '${now.toIso8601String().replaceAll(RegExp(r'[-:.]'), '')}'
        '-${deviceId.substring(0, 8)}-${const Uuid().v4().substring(0, 8)}';
    await state.setPendingSend(id);

    final kept = <SnapshotEntry, SnapshotManifest>{};
    for (final entry in head?.snapshots ?? const <SnapshotEntry>[]) {
      final manifest = await readManifest(place, entry.id);
      if (manifest != null) kept[entry] = manifest;
    }
    final tombstoned = {for (final t in head?.tombstones ?? const []) t.sha};
    final present = {
      for (final m in kept.values)
        for (final b in m.blobs) b.sha,
    }.difference(tombstoned);

    final total =
        snap.database.size + snap.files.fold<int>(0, (s, f) => s + f.size);
    var sent = 0;
    void progress(int n) {
      sent += n;
      onBytes?.call(sent, total);
    }

    final uploaded = <String>{};
    Future<void> upload(SnapshotFile entry, File local) async {
      var offset = 0;
      for (final blob in entry.blobs) {
        final start = offset;
        offset += blob.size;
        if (present.contains(blob.sha) || !uploaded.add(blob.sha)) {
          progress(blob.size);
          continue;
        }
        await _uploadBlob(
          local,
          start,
          start + blob.size,
          blob,
          entry.path,
          progress,
        );
      }
    }

    await upload(snap.database, snap.dbGz);
    for (final file in snap.files) {
      await upload(file, snap.locals[file.path]!);
    }

    final manifest = SnapshotManifest(
      id: id,
      libraryId: libraryId,
      parent: head?.head,
      device: deviceName,
      deviceId: deviceId,
      sentAt: now,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      sourceRoot: root,
      counts: snap.counts,
      prefs: snap.prefs,
      database: snap.database,
      files: snap.files,
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
    await place.upload(
      manifestPath(id),
      () => Stream.value(manifestBytes),
      manifestBytes.length,
    );

    final entries = [
      SnapshotEntry.of(manifest),
      for (final e in kept.keys)
        overwriteTheirs && e.id == head?.head && e.deviceId != deviceId
            ? e.withPinned(true)
            : e,
    ];
    final keep = _prune(entries);
    final dropped = entries.where((e) => !keep.contains(e)).toList();
    final manifests = {
      for (final e in kept.entries) e.key.id: e.value,
      id: manifest,
    };
    final referenced = {
      for (final e in keep)
        for (final b in manifests[e.id]?.blobs ?? const <BlobRef>[]) b.sha,
    };
    final expired = <String>[];
    final tombstones = <Tombstone>[];
    for (final t in head?.tombstones ?? const <Tombstone>[]) {
      if (referenced.contains(t.sha)) continue;
      if (now.difference(t.since) >= kTombstoneDelay) {
        expired.add(t.sha);
      } else {
        tombstones.add(t);
      }
    }
    final alreadyTombed = {for (final t in tombstones) t.sha, ...expired};
    for (final e in dropped) {
      for (final b in manifests[e.id]?.blobs ?? const <BlobRef>[]) {
        if (!referenced.contains(b.sha) && alreadyTombed.add(b.sha)) {
          tombstones.add(Tombstone(b.sha, now));
        }
      }
    }

    final newHead = RemoteHead(
      libraryId: libraryId,
      head: id,
      snapshots: keep,
      tombstones: tombstones,
    );
    await place.writeHead(
      utf8.encode(jsonEncode(newHead.toJson())),
      ifTag: read?.tag,
    );

    await state.setPendingSend(null);
    await state.setLastSync(
      LastSync(
        snapshotId: id,
        libraryId: libraryId,
        at: now,
        sent: true,
        device: deviceName,
      ),
    );

    // Cleanup after the head moved: a failure here only leaves litter.
    for (final e in dropped) {
      await _quietly(() => place.delete(manifestPath(e.id)));
    }
    for (final sha in expired) {
      await _quietly(() => place.delete(blobPath(sha)));
    }
    return id;
  }

  /// The newest entry, the next [kKeptSnapshots] unpinned ones, and the
  /// newest [kKeptPinned] pinned ones, newest first.
  static List<SnapshotEntry> _prune(List<SnapshotEntry> entries) {
    final keep = <SnapshotEntry>[entries.first];
    var unpinned = 0;
    var pinned = 0;
    for (final e in entries.skip(1)) {
      if (e.pinned && pinned < kKeptPinned) {
        pinned++;
        keep.add(e);
      } else if (!e.pinned && unpinned < kKeptSnapshots) {
        unpinned++;
        keep.add(e);
      }
    }
    return keep;
  }

  /// Uploads bytes [start]..[end] of [local] as [blob], hashing as it goes.
  /// A file that changed since it was hashed would store the wrong bytes
  /// under the blob's name, so a mismatch deletes the blob and stops.
  Future<void> _uploadBlob(
    File local,
    int start,
    int end,
    BlobRef blob,
    String path,
    void Function(int) progress,
  ) async {
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    await place.upload(
      blobPath(blob.sha),
      () => local.openRead(start, end).map((chunk) {
        hasher.add(chunk);
        return chunk;
      }),
      blob.size,
      onBytes: progress,
    );
    hasher.close();
    if (digest.value.toString() != blob.sha) {
      await _quietly(() => place.delete(blobPath(blob.sha)));
      throw SyncPlaceException(
        '$path changed while it was being sent. Send again.',
      );
    }
  }

  static Future<void> _quietly(Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      debugPrint('[Sync] Cleanup on the sync place failed (harmless): $e');
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
