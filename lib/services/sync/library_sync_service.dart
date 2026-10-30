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
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/database.dart';

import 'library_digest.dart';
import 'library_file_set.dart';
import 'library_prefs.dart';
import 'library_sender.dart';
import 'library_swap.dart';
import 'library_swap_runner.dart';
import 'local_changes.dart';
import 'snapshot_builder.dart';
import 'snapshot_stager.dart';
import 'swap_journal.dart';
import 'sync_host.dart';
import 'sync_place.dart';
import 'sync_settings.dart';
import 'sync_state_store.dart';
import 'sync_words.dart';

/// What the sync service is doing right now.
enum SyncPhase { idle, checking, packing, sending, fetching, replacing }

/// Send my library / Get the library / Undo, for one device.
///
/// A whole library moves at once, so nothing is merged: a Get replaces this
/// device's library, after asking Keep mine / Take theirs when this device
/// changed since its last sync, and keeps what it replaced for an Undo.
class LibrarySyncService extends ChangeNotifier {
  LibrarySyncService({
    required String Function() root,
    required this.prefs,
    required this.host,
    SyncPasswordStore? passwords,
    DateTime Function()? clock,
  }) : _root = root,
       settings = SyncSettings(prefs),
       state = SyncStateStore(prefs),
       passwords = passwords ?? SyncPasswordStore.open(),
       _now = clock ?? DateTime.now;

  /// Read each time: the root is set once storage loads, and moves with
  /// Change Data Directory.
  final String Function() _root;
  String get root => _root();
  final SharedPreferences prefs;
  final SyncHost host;
  final SyncSettings settings;
  final SyncStateStore state;
  final SyncPasswordStore passwords;
  final DateTime Function() _now;

  FileHashCache? _hashCache;
  FileHashCache get _hashes => _hashCache?.root == root
      ? _hashCache!
      : (_hashCache = FileHashCache(root));

  SyncPhase phase = SyncPhase.idle;
  int progressDone = 0;
  int progressTotal = 0;

  /// How the last job ended, for the phone web app's polling.
  SyncOutcome? lastOutcome;
  RemoteStatus? remote;
  String? remoteError;

  /// A fetched library waiting for the person's choice.
  GetReady? pendingGet;
  IncomingLibrary? _staged;
  SyncPlace? _place;
  bool _cancelled = false;

  /// A send on close is running; the window waits for it.
  bool closingSend = false;

  /// A swap failed part-way; the next start finishes it.
  String? needsRestart;

  bool get busy => phase != SyncPhase.idle;
  bool get replacing => phase == SyncPhase.replacing;

  /// A developer data-folder override splits files and the database across
  /// two roots, which a swap can't follow.
  bool get disabled =>
      isPreRelease && Platform.environment['FRONT_PORCH_AI_DATA_DIR'] != null;

  String get deviceName => settings.deviceName.isNotEmpty
      ? settings.deviceName
      : (Platform.isAndroid ? 'Android phone' : Platform.localHostname);

  UndoRecord? get undoRecord {
    final undo = state.undo;
    return undo == null || undo.expiredAt(_now()) ? null : undo;
  }

  void _setPhase(SyncPhase value) {
    phase = value;
    progressDone = progressTotal = 0;
    notifyListeners();
  }

  DateTime _lastTick = DateTime(0);
  void _progress(int done, int total) {
    progressDone = done;
    progressTotal = total;
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds < 150 && done < total) return;
    _lastTick = now;
    notifyListeners();
  }

  /// A place for a job, kept so [cancel] can close it.
  Future<SyncPlace> _open() async {
    _place?.close();
    return _place = await _openOwn();
  }

  /// A place of its own, so a status read never cuts off a job's.
  Future<SyncPlace> _openOwn() async =>
      await settings.openPlace(passwords) ??
      (throw const SyncPlaceException('Set up a sync place first.'));

  /// Runs one job, turning every failure into words.
  Future<SyncOutcome> _job(
    SyncPhase start,
    Future<SyncOutcome> Function() run,
  ) async {
    if (disabled) return const SyncFailed(kSyncDisabledReason);
    if (busy) return const SyncFailed('Sync is already busy.');
    _cancelled = false;
    _setPhase(start);
    try {
      return lastOutcome = await run();
    } catch (e) {
      final text = _cancelled ? 'Cancelled.' : syncErrorWords(e);
      debugPrint('[Sync] ${start.name} failed: $e');
      return lastOutcome = SyncFailed(text);
    } finally {
      _setPhase(SyncPhase.idle);
    }
  }

  /// Stops a Send or a download. A swap, once started, always finishes.
  void cancel() {
    if (replacing || !busy) return;
    _cancelled = true;
    _place?.close();
  }

  /// Reads the sync place's newest library for the status card.
  Future<void> refresh() async {
    if (disabled || !settings.isConfigured || busy) return;
    final SyncPlace place;
    try {
      place = await _openOwn();
    } catch (e) {
      remoteError = syncErrorWords(e);
      notifyListeners();
      return;
    }
    try {
      final read = await readPlaceHead(place);
      if (read == null) {
        remote = null;
      } else {
        final last = state.lastSync;
        final id = await state.deviceId();
        remote = RemoteStatus(
          head: read.head,
          manifest: await readManifest(place, read.head.head),
          newer:
              read.head.head != last?.snapshotId &&
              read.head.headEntry?.deviceId != id,
        );
      }
      remoteError = null;
    } catch (e) {
      remoteError = syncErrorWords(e);
    } finally {
      place.close();
    }
    notifyListeners();
  }

  /// What changed here since the last sync, for the status card.
  LocalChanges? here;

  Future<void> checkHere() async {
    if (disabled || busy) return;
    _setPhase(SyncPhase.checking);
    try {
      here = await _localChanges();
    } catch (e) {
      debugPrint('[Sync] Checking this device for changes failed: $e');
      here = null;
    } finally {
      _setPhase(SyncPhase.idle);
    }
  }

  /// At start: drops an Undo older than seven days, and any set-aside
  /// library nothing can undo to any more.
  Future<void> cleanUp() async {
    if (disabled || root.isEmpty) return;
    final undo = state.undo;
    if (undo != null && undo.expiredAt(_now())) await state.setUndo(null);
    try {
      await pruneAsideFolders(root, keep: undoRecord?.folder);
    } on FileSystemException catch (e) {
      debugPrint('[Sync] Could not clear old set-aside libraries: $e');
    }
  }

  Future<String?> testConnection() async {
    SyncPlace? place;
    try {
      place = await _openOwn();
      await place.probe();
      return null;
    } catch (e) {
      return syncErrorWords(e);
    } finally {
      place?.close();
    }
  }

  /// Packs and sends this device's library. [overwriteTheirs] is the
  /// person's "Send mine anyway": the newer library stays on the place,
  /// pinned, under Earlier versions.
  Future<SyncOutcome> send({bool overwriteTheirs = false}) =>
      _job(SyncPhase.packing, () async {
        final reason = busyReason(host.quiesceChecks);
        if (reason != null) return SyncFailed(reason);
        final place = await _open();
        final deviceId = await state.deviceId();
        final sender = LibrarySender(
          place: place,
          state: state,
          deviceId: deviceId,
          deviceName: deviceName,
          appVersion: appVersion,
          schemaVersion: host.database.schemaVersion,
          root: root,
          clock: _now,
          onBytes: _progress,
        );
        try {
          sender.checkConflict(
            await readPlaceHead(place),
            overwriteTheirs: overwriteTheirs,
          );
        } on SendConflict catch (c) {
          return SendNeedsChoice(c);
        }
        await host.flushSaves();
        final snap = await buildOutgoingSnapshot(
          live: host.database,
          root: root,
          hashes: _hashes,
          prefs: prefs,
        );
        _setPhase(SyncPhase.sending);
        try {
          await sender.send(snap, overwriteTheirs: overwriteTheirs);
        } on SendConflict catch (c) {
          return SendNeedsChoice(c);
        } on HeadChangedException {
          final read = await readPlaceHead(place);
          return SendNeedsChoice(
            SendConflict(SendConflictKind.newerHead, read?.head.headEntry),
          );
        }
        await saveDigest(root, deviceId, snap.digest);
        await outgoingDir(root).delete(recursive: true);
        unawaited(refresh());
        return SyncDone('Sent at ${syncWhen(_now())}.');
      });

  /// Fetches the newest library (or [snapshotId]) and checks it, without
  /// changing anything here. A [GetReady] waits for [applyGet].
  Future<SyncOutcome> prepareGet({String? snapshotId}) =>
      _job(SyncPhase.fetching, () async {
        final place = await _open();
        final read = await readPlaceHead(place);
        if (read == null) {
          return const SyncDone('Nothing has been sent to the sync place yet.');
        }
        final last = state.lastSync;
        if (snapshotId == null && last?.snapshotId == read.head.head) {
          final local = await _localChanges();
          return SyncDone(
            local.any
                ? 'Up to date. This device has changes to send.'
                : 'Up to date.',
          );
        }
        final incoming = await stageSnapshot(
          place: place,
          root: root,
          live: host.database,
          hashes: _hashes,
          schemaVersion: host.database.schemaVersion,
          snapshotId: snapshotId,
          onBytes: _progress,
        );
        if (incoming == null) return const SyncDone('Nothing to get.');
        _staged = incoming;
        final local = await _localChanges();
        final otherLibrary =
            last != null && last.libraryId != incoming.manifest.libraryId;
        return pendingGet = GetReady(
          theirs: incoming.manifest,
          changes: local.changes,
          changedChats: local.titles,
          neverSynced: local.neverSynced || otherLibrary,
          unknownChanges: local.unknown,
        );
      });

  /// Forgets a fetched library the person decided to keep theirs over.
  Future<void> discardGet() async {
    pendingGet = null;
    final staged = _staged;
    _staged = null;
    if (staged != null && await staged.dir.exists()) {
      await staged.dir.delete(recursive: true);
    }
    notifyListeners();
  }

  /// Take theirs: swaps the fetched library in.
  Future<SyncOutcome> applyGet() async {
    final incoming = _staged;
    if (incoming == null) return const SyncFailed('Get the library first.');
    final outcome = await _job(SyncPhase.replacing, () async {
      final manifest = incoming.manifest;
      final deviceId = await state.deviceId();
      final now = _now();
      final local = await listLibraryFiles(root);
      final theirs = {for (final f in manifest.files) f.path};
      return _swap(
        db: incoming.dbFile,
        files: incoming.files,
        remove: {
          for (final f in local)
            if (!theirs.contains(f.path)) f.path,
        },
        finish: (aside) => SwapFinish(
          deviceId: deviceId,
          prefs: manifest.prefs,
          sourceRoot: manifest.sourceRoot,
          lastSync: LastSync(
            snapshotId: manifest.id,
            libraryId: manifest.libraryId,
            at: now,
            sent: false,
            device: manifest.device,
          ),
          undo: UndoRecord(folder: aside, at: now, device: manifest.device),
          digest: incoming.digest,
        ),
        afterMoves: () async {
          if (await incoming.dir.exists()) {
            await incoming.dir.delete(recursive: true);
          }
        },
        done:
            'Got ${manifest.device}\'s library from ${syncWhen(manifest.sentAt)}.',
      );
    });
    pendingGet = null;
    _staged = null;
    return outcome;
  }

  /// Puts back the library the last Get set aside. What this device has now
  /// is set aside in turn, and the library counts as changed afterwards.
  Future<SyncOutcome> undo() => _job(SyncPhase.replacing, () async {
    final record = undoRecord;
    if (record == null) return const SyncFailed('There is nothing to undo.');
    final dbName = p.basename(await _dbPath());
    final source = await undoSources(root, record, dbName);
    if (source == null) {
      return const SyncFailed('The library set aside for Undo is gone.');
    }
    final deviceId = await state.deviceId();
    final oldPrefs = source.prefs ?? readLibraryPrefs(prefs);
    return _swap(
      db: source.db,
      files: source.files,
      remove: source.remove,
      finish: (_) =>
          SwapFinish(deviceId: deviceId, prefs: oldPrefs, sourceRoot: root),
      afterMoves: () async {},
      done:
          'Put back this device\'s library from before ${syncWhen(record.at)}.',
      keepAside: false,
    );
  });

  Future<String> _dbPath() async =>
      AppDatabase.dbFilePath ?? (await AppDatabase.locateFile()).path;

  Future<SyncOutcome> _swap({
    required File db,
    required Map<String, File> files,
    required Set<String> remove,
    required SwapFinish Function(String aside) finish,
    required Future<void> Function() afterMoves,
    required String done,
    bool keepAside = true,
  }) async {
    final reason = busyReason(host.quiesceChecks);
    if (reason != null) return SyncFailed(reason);
    try {
      final rebound = await runLibrarySwap(
        root: root,
        prefs: prefs,
        host: host,
        dbPath: await _dbPath(),
        db: db,
        files: files,
        remove: remove,
        finish: finish,
        afterMoves: afterMoves,
        keepAside: keepAside,
      );
      if (!rebound) {
        needsRestart =
            'The library was replaced. Close and reopen Front Porch AI to '
            'finish loading it.';
        notifyListeners();
      }
      return SyncDone(done);
    } on SwapStuck catch (e) {
      needsRestart =
          'Replacing the library did not finish (${syncErrorWords(e.cause)}). Close '
          'and reopen Front Porch AI to finish it.';
      notifyListeners();
      rethrow;
    }
  }

  Future<LocalChanges> _localChanges() =>
      checkLocalChanges(state: state, root: root, host: host, hashes: _hashes);

  /// Send on close (or on leaving the app, for a phone): skips when
  /// anything is busy or another device sent a newer library (it never
  /// chooses Send mine anyway), and gives up after [limit]. Returns whether
  /// the library was sent.
  Future<bool> sendIfWanted({
    Duration limit = const Duration(seconds: 60),
    bool closing = true,
  }) async {
    if (!settings.sendOnClose || !settings.isConfigured || busy || disabled) {
      return false;
    }
    closingSend = closing;
    notifyListeners();
    try {
      return await send().timeout(limit) is SyncDone;
    } on TimeoutException {
      debugPrint('[Sync] Send on close took too long; the place is unchanged');
      return false;
    } finally {
      closingSend = false;
    }
  }

  @override
  void dispose() {
    _place?.close();
    super.dispose();
  }
}
