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

import 'package:front_porch_ai/services/services.dart';

/// Settings → Sync for the phone web app. It drives the desktop's own sync:
/// what the phone sends and gets is the desktop's library.
///
/// Sends and Gets take minutes, so each starts and returns at once; the page
/// polls [status]. A Get restarts the web server once the library is
/// swapped, so how a job ended lives on the service, not here.
class SyncFacade {
  SyncFacade(this.sync);

  final LibrarySyncService sync;

  Map<String, Object?> _entry(SnapshotEntry e) => {
    'id': e.id,
    'device': e.device,
    'sentAt': e.sentAt.toUtc().toIso8601String(),
    'when': syncWhen(e.sentAt),
    if (e.pinned) 'pinned': true,
  };

  Map<String, Object?>? _outcome(SyncOutcome? o) => switch (o) {
    null => null,
    SyncDone(:final message) => {'kind': 'done', 'message': message},
    SyncFailed(:final message) => {'kind': 'failed', 'message': message},
    SendNeedsChoice(:final conflict) => {
      'kind': 'sendConflict',
      'otherLibrary': conflict.kind == SendConflictKind.otherLibrary,
      'message': '$conflict',
      if (conflict.theirs != null) 'theirs': _entry(conflict.theirs!),
    },
    GetReady() => {
      'kind': 'getReady',
      'conflicts': o.conflicts,
      'summary':
          '${o.theirs.device}\'s library from ${syncWhen(o.theirs.sentAt)}: '
          '${syncSummary(o.theirs)}.',
      'changes': describeLocalChanges(
        neverSynced: o.neverSynced,
        unknown: o.unknownChanges,
        changes: o.changes,
        chatNames: o.changedChats,
      ),
    },
  };

  Future<Map<String, Object?>> status() async {
    final settings = sync.settings;
    bool passwordSaved;
    try {
      passwordSaved = await sync.passwords.read() != null;
    } on SyncPasswordStoreException {
      passwordSaved = false;
    }
    final remote = sync.remote;
    final head = remote?.head;
    final last = sync.state.lastSync;
    final undo = sync.undoRecord;
    final here = sync.here;
    return {
      'disabled': sync.disabled,
      if (sync.disabled) 'disabledReason': kSyncDisabledReason,
      'configured': settings.isConfigured,
      'place': {
        'kind': settings.kind.name,
        'serverUrl': settings.serverUrl,
        'username': settings.username,
        'folderName': settings.folderName,
        'folderPath': settings.folderPath,
        'passwordSaved': passwordSaved,
      },
      'deviceName': settings.deviceName,
      'deviceNameShown': sync.deviceName,
      'sendOnClose': settings.sendOnClose,
      'checkOnStart': settings.checkOnStart,
      'remote': head == null
          ? null
          : {
              ...?_entryOrNull(head.headEntry),
              if (remote!.manifest != null)
                'summary': syncSummary(remote.manifest!),
              'newer': remote.newer,
              'earlier': [
                for (final s in head.snapshots)
                  if (s.id != head.head) _entry(s),
              ],
            },
      'remoteError': sync.remoteError,
      'lastSync': last == null
          ? null
          : {
              'sent': last.sent,
              'when': syncWhen(last.at),
              'device': last.device,
            },
      'here': here == null || last == null
          ? null
          : describeLocalChanges(
              neverSynced: here.neverSynced,
              unknown: here.unknown,
              changes: here.changes,
              chatNames: here.titles,
            ),
      'undo': undo == null
          ? null
          : {'when': syncWhen(undo.at), 'device': undo.device},
      'phase': sync.phase.name,
      'progress': {'done': sync.progressDone, 'total': sync.progressTotal},
      'needsRestart': sync.needsRestart,
      'outcome': _outcome(sync.lastOutcome),
    };
  }

  Map<String, Object?>? _entryOrNull(SnapshotEntry? e) =>
      e == null ? null : _entry(e);

  /// Saves the place and switches. A new password is saved only after the
  /// route checked the person's web password (step-up).
  Future<void> saveSettings(Map<String, dynamic> body) async {
    final settings = sync.settings;
    final kind = SyncPlaceKind.values
        .where((k) => k.name == body['kind'])
        .firstOrNull;
    if (kind != null) {
      await settings.setPlace(
        kind: kind,
        serverUrl: body['serverUrl']?.toString(),
        username: body['username']?.toString(),
        folderPath: body['folderPath']?.toString(),
        folderName: body['folderName']?.toString(),
      );
    }
    if (body['deviceName'] is String) {
      await settings.setDeviceName(body['deviceName'] as String);
    }
    if (body['sendOnClose'] is bool) {
      await settings.setSendOnClose(body['sendOnClose'] as bool);
    }
    if (body['checkOnStart'] is bool) {
      await settings.setCheckOnStart(body['checkOnStart'] as bool);
    }
    final password = body['password']?.toString() ?? '';
    if (password.isNotEmpty) await sync.passwords.save(password);
  }

  Future<String?> testConnection() async {
    final error = await sync.testConnection();
    if (error == null) unawaited(sync.refresh());
    return error;
  }

  Future<void> refresh() async {
    await sync.refresh();
    if (sync.state.lastSync != null) unawaited(sync.checkHere());
  }

  /// Starts a job and returns at once; false when one is already running.
  bool _start(Future<void> Function() run) {
    if (sync.busy) return false;
    unawaited(run());
    return true;
  }

  bool send({bool overwriteTheirs = false}) =>
      _start(() => sync.send(overwriteTheirs: overwriteTheirs));

  bool prepareGet({String? snapshotId}) =>
      _start(() => sync.prepareGet(snapshotId: snapshotId));

  bool applyGet() => _start(sync.applyGet);

  Future<void> discardGet() async {
    await sync.discardGet();
    sync.lastOutcome = null;
  }

  bool undo() => _start(sync.undo);

  void cancel() => sync.cancel();
}
