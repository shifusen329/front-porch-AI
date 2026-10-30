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

import 'package:front_porch_ai/database/database.dart';

import 'library_digest.dart';
import 'library_sender.dart';
import 'sync_manifest.dart';

/// One thing that must be idle before the library is packed or replaced.
class QuiesceCheck {
  const QuiesceCheck(this.reason, this.busy);

  /// Said to the person when [busy]: "A reply is still being written."
  final String reason;
  final bool Function() busy;
}

/// What the sync service needs from the running app. The app wires the
/// real services; a test wires a small library of its own.
abstract class SyncHost {
  /// The live database (it changes after every swap).
  AppDatabase get database;

  /// Everything that writes to the library on its own.
  List<QuiesceCheck> get quiesceChecks;

  /// Writes any pending chat saves.
  Future<void> flushSaves();

  /// Closes the open chat so nothing in memory is written into the
  /// incoming library, and says which chat it was.
  Future<Object?> detachChat();

  /// Reopens [token]'s chat if the new library has it.
  Future<void> reattachChat(Object? token);

  /// Leaves every editor and dialog for the main screen.
  void popToRoot();

  /// Reopens the database and re-points every service. False when that
  /// failed and the app needs a restart.
  Future<bool> rebind();

  /// After a swap: settings re-read from prefs, picture caches cleared.
  Future<void> afterSwap();

  /// Session ids → a chat's name, for "3 chats changed here".
  Future<Map<String, String>> chatTitles(List<String> sessionIds);
}

/// The first busy [QuiesceCheck]'s reason, or null when all are idle.
String? busyReason(List<QuiesceCheck> checks) {
  for (final c in checks) {
    if (c.busy()) return c.reason;
  }
  return null;
}

/// What a Send or Get came to.
sealed class SyncOutcome {
  const SyncOutcome();
}

class SyncDone extends SyncOutcome {
  const SyncDone(this.message);
  final String message;
}

class SyncFailed extends SyncOutcome {
  const SyncFailed(this.message);
  final String message;
}

/// A Send that stopped to ask: Get theirs first, Send mine anyway, Cancel.
class SendNeedsChoice extends SyncOutcome {
  const SendNeedsChoice(this.conflict);
  final SendConflict conflict;
}

/// A fetched library waiting for the person: one confirm, or Keep mine /
/// Take theirs when [changes] (or [neverSynced]) says this device has its
/// own work.
class GetReady extends SyncOutcome {
  const GetReady({
    required this.theirs,
    required this.changes,
    required this.changedChats,
    required this.neverSynced,
    required this.unknownChanges,
  });

  final SnapshotManifest theirs;

  /// What changed here since the last sync, or null when nothing did.
  final DigestChanges? changes;

  /// Names of up to three changed chats.
  final List<String> changedChats;

  /// This device has a library of its own and has never synced.
  final bool neverSynced;

  /// The library was put back with Undo since the last sync, so what
  /// changed can't be listed.
  final bool unknownChanges;

  bool get conflicts =>
      neverSynced || unknownChanges || (changes != null && !changes!.isEmpty);
}

/// The sync place as last read.
class RemoteStatus {
  const RemoteStatus({
    required this.head,
    required this.manifest,
    required this.newer,
  });

  final RemoteHead head;
  final SnapshotManifest? manifest;

  /// Its newest library is one this device hasn't got.
  final bool newer;
}
