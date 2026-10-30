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

/// Files bigger than this go up as several blobs, so no single request trips
/// a proxy's body limit (Cloudflare in front of Nextcloud stops at 100 MB).
const int kBlobPartBytes = 32 * 1024 * 1024;

/// The place-side path of a content-addressed blob.
String blobPath(String sha) => 'blobs/${sha.substring(0, 2)}/$sha';

/// The place-side path of a snapshot's manifest.
String manifestPath(String id) => 'snapshots/$id.json';

/// A content-addressed piece of a file on the sync place.
class BlobRef {
  const BlobRef(this.sha, this.size);

  factory BlobRef.fromJson(Map json) =>
      BlobRef(json['sha'] as String, (json['size'] as num).toInt());

  final String sha;
  final int size;

  Map<String, Object> toJson() => {'sha': sha, 'size': size};
}

/// One file in a snapshot. A file up to [kBlobPartBytes] is the single blob
/// named by its own sha; a bigger one lists its [parts].
class SnapshotFile {
  const SnapshotFile({
    required this.path,
    required this.sha,
    required this.size,
    this.parts = const [],
  });

  factory SnapshotFile.fromJson(Map json) => SnapshotFile(
    path: json['path'] as String,
    sha: json['sha'] as String,
    size: (json['size'] as num).toInt(),
    parts: [
      for (final part in (json['parts'] as List? ?? const []))
        BlobRef.fromJson(part as Map),
    ],
  );

  final String path;
  final String sha;
  final int size;
  final List<BlobRef> parts;

  /// The blobs that make up this file, in order.
  List<BlobRef> get blobs => parts.isEmpty ? [BlobRef(sha, size)] : parts;

  Map<String, Object> toJson() => {
    'path': path,
    'sha': sha,
    'size': size,
    if (parts.isNotEmpty) 'parts': [for (final b in parts) b.toJson()],
  };
}

/// `snapshots/<id>.json`: everything a Get needs to rebuild one library.
class SnapshotManifest {
  const SnapshotManifest({
    required this.id,
    required this.libraryId,
    required this.parent,
    required this.device,
    required this.deviceId,
    required this.sentAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.sourceRoot,
    required this.counts,
    required this.prefs,
    required this.database,
    required this.files,
  });

  factory SnapshotManifest.fromJson(Map json) {
    if (json['format'] != 1) {
      throw const FormatException('this snapshot was made by a newer app');
    }
    return SnapshotManifest(
      id: json['id'] as String,
      libraryId: json['libraryId'] as String,
      parent: json['parent'] as String?,
      device: json['device'] as String? ?? 'Another device',
      deviceId: json['deviceId'] as String,
      sentAt: DateTime.parse(json['sentAt'] as String),
      appVersion: json['appVersion'] as String? ?? '',
      schemaVersion: (json['schemaVersion'] as num).toInt(),
      sourceRoot: json['sourceRoot'] as String,
      counts: {
        for (final e in (json['counts'] as Map? ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      },
      prefs: Map<String, Object?>.from(json['prefs'] as Map? ?? const {}),
      database: SnapshotFile.fromJson(json['db'] as Map),
      files: [
        for (final f in (json['files'] as List? ?? const []))
          SnapshotFile.fromJson(f as Map),
      ],
    );
  }

  final String id;
  final String libraryId;
  final String? parent;
  final String device;
  final String deviceId;
  final DateTime sentAt;
  final String appVersion;
  final int schemaVersion;
  final String sourceRoot;

  /// Row counts by table, for the status line and the empty-library check.
  final Map<String, int> counts;
  final Map<String, Object?> prefs;

  /// The gzipped database.
  final SnapshotFile database;
  final List<SnapshotFile> files;

  int get totalBytes =>
      database.size + files.fold<int>(0, (sum, f) => sum + f.size);

  /// Every blob this snapshot needs.
  Iterable<BlobRef> get blobs sync* {
    yield* database.blobs;
    for (final f in files) {
      yield* f.blobs;
    }
  }

  Map<String, Object?> toJson() => {
    'format': 1,
    'id': id,
    'libraryId': libraryId,
    'parent': parent,
    'device': device,
    'deviceId': deviceId,
    'sentAt': sentAt.toUtc().toIso8601String(),
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'sourceRoot': sourceRoot,
    'counts': counts,
    'prefs': prefs,
    'db': database.toJson(),
    'files': [for (final f in files) f.toJson()],
  };
}

/// One kept snapshot as `latest.json` lists it.
class SnapshotEntry {
  const SnapshotEntry({
    required this.id,
    required this.device,
    required this.deviceId,
    required this.sentAt,
    this.pinned = false,
  });

  factory SnapshotEntry.fromJson(Map json) => SnapshotEntry(
    id: json['id'] as String,
    device: json['device'] as String? ?? 'Another device',
    deviceId: json['deviceId'] as String? ?? '',
    sentAt: DateTime.parse(json['sentAt'] as String),
    pinned: json['pinned'] == true,
  );

  factory SnapshotEntry.of(SnapshotManifest m) => SnapshotEntry(
    id: m.id,
    device: m.device,
    deviceId: m.deviceId,
    sentAt: m.sentAt,
  );

  final String id;
  final String device;
  final String deviceId;
  final DateTime sentAt;

  /// Kept past the usual five because a Send mine anyway replaced it.
  final bool pinned;

  SnapshotEntry withPinned(bool value) => SnapshotEntry(
    id: id,
    device: device,
    deviceId: deviceId,
    sentAt: sentAt,
    pinned: value,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'device': device,
    'deviceId': deviceId,
    'sentAt': sentAt.toUtc().toIso8601String(),
    if (pinned) 'pinned': true,
  };
}

/// A blob no kept snapshot uses any more, deleted a day after [since] so a
/// device mid-Get of the snapshot that dropped it still finds it.
class Tombstone {
  const Tombstone(this.sha, this.since);

  factory Tombstone.fromJson(Map json) =>
      Tombstone(json['sha'] as String, DateTime.parse(json['since'] as String));

  final String sha;
  final DateTime since;

  Map<String, Object> toJson() => {
    'sha': sha,
    'since': since.toUtc().toIso8601String(),
  };
}

/// `latest.json`: which library lives here, which snapshot is newest, and
/// what is kept. It is the only file on the place that is ever rewritten.
class RemoteHead {
  const RemoteHead({
    required this.libraryId,
    required this.head,
    required this.snapshots,
    this.tombstones = const [],
  });

  factory RemoteHead.fromJson(Map json) {
    if (json['format'] != 1) {
      throw const FormatException('this sync place was written by a newer app');
    }
    return RemoteHead(
      libraryId: json['libraryId'] as String,
      head: json['head'] as String,
      snapshots: [
        for (final s in (json['snapshots'] as List? ?? const []))
          SnapshotEntry.fromJson(s as Map),
      ],
      tombstones: [
        for (final t in (json['tombstones'] as List? ?? const []))
          Tombstone.fromJson(t as Map),
      ],
    );
  }

  final String libraryId;
  final String head;

  /// Newest first; the first is [head].
  final List<SnapshotEntry> snapshots;
  final List<Tombstone> tombstones;

  SnapshotEntry? get headEntry {
    for (final s in snapshots) {
      if (s.id == head) return s;
    }
    return null;
  }

  Map<String, Object> toJson() => {
    'format': 1,
    'libraryId': libraryId,
    'head': head,
    'snapshots': [for (final s in snapshots) s.toJson()],
    'tombstones': [for (final t in tombstones) t.toJson()],
  };
}
