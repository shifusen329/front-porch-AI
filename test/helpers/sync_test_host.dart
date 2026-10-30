// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

/// A [SyncHost] over one test library's real services. It does what the
/// app's wiring does on a swap: detach the chat, then after the swap re-point
/// the repository and chat at the reopened database and reload them.
class SyncTestHost implements SyncHost {
  SyncTestHost(this._db, {this.chat, this.repo, this.detach = true});

  AppDatabase _db;
  final ChatService? chat;
  final CharacterRepository? repo;

  /// False plays an app that forgot to close the open chat before a swap.
  final bool detach;

  int rebinds = 0;

  @override
  AppDatabase get database => _db;

  @override
  List<QuiesceCheck> quiesceChecks = [];

  @override
  Future<void> flushSaves() async => chat?.flushPendingSaves();

  @override
  Future<Object?> detachChat() async {
    final id = chat?.currentSessionId;
    if (detach) await chat?.setActiveCharacter(null);
    return id;
  }

  @override
  Future<void> reattachChat(Object? token) async {}

  @override
  void popToRoot() {}

  @override
  Future<bool> rebind() async {
    final db = await AppDatabase.instance();
    _db = db;
    rebinds++;
    repo?.updateDatabase(db);
    chat?.updateDatabase(db);
    await repo?.loadCharacters();
    await chat?.reloadCurrentSession();
    return true;
  }

  @override
  Future<void> afterSwap() async {}

  @override
  Future<Map<String, String>> chatTitles(List<String> sessionIds) async => {
    for (final id in sessionIds) id: id,
  };
}
