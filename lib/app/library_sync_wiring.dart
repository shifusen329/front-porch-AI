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

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/widgets/unsaved_changes_guard.dart';

/// The app's one navigator, so a library swap can leave every editor and
/// dialog for the main screen before the files move.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// The sync service over the running app. [context] is the provider
/// element's own, which lives as long as the app; everything is read from
/// it when needed, since several services are re-pointed on a swap.
LibrarySyncService createLibrarySync(
  BuildContext context,
  SharedPreferences prefs,
) {
  final storage = Provider.of<StorageService>(context, listen: false);
  final sync = LibrarySyncService(
    root: () => storage.rootPath ?? '',
    prefs: prefs,
    host: _AppSyncHost(context),
  );
  Provider.of<WebServerHost>(context, listen: false).setLibrarySync(sync);
  return sync;
}

/// Which chat was open before a swap, to reopen it if the new library has it.
typedef _OpenChat = ({String? characterId, String? groupId, String sessionId});

class _AppSyncHost implements SyncHost {
  _AppSyncHost(this._context);

  final BuildContext _context;

  T _read<T>() => Provider.of<T>(_context, listen: false);

  ChatService get _chat => _read<ChatService>();

  @override
  AppDatabase get database => AppDatabase.current ?? _read<AppDatabase>();

  @override
  List<QuiesceCheck> get quiesceChecks => [
    QuiesceCheck(
      'A reply is still being written. Wait for it to finish.',
      () => _chat.isTurnBusy || _chat.isGenerating,
    ),
    QuiesceCheck('A chat is still being imported.', () => _chat.isImporting),
    QuiesceCheck(
      'Memory is being rebuilt. Wait for it to finish.',
      () => _chat.memoryService?.vectorRebuilder.running ?? false,
    ),
    QuiesceCheck(
      'Image Batches is working. Pause it first.',
      () => _read<ImageGenService>().batches.working,
    ),
    QuiesceCheck(
      'A story is being written. Wait for it to finish.',
      () => _read<StoryPipelineService>().isRunning,
    ),
    QuiesceCheck(
      'An editor has unsaved changes. Save or close it first.',
      () => UnsavedChanges.instance.hasUnsaved,
    ),
  ];

  @override
  Future<void> flushSaves() => _chat.flushPendingSaves();

  @override
  Future<Object?> detachChat() async {
    final chat = _chat;
    final sessionId = chat.currentSessionId;
    final open = sessionId == null
        ? null
        : (
            characterId: chat.activeCharacter?.dbId,
            groupId: chat.activeGroup?.id,
            sessionId: sessionId,
          );
    // Closing the chat drops its transcript from memory, so the rebind's
    // reload can't write this device's chat into the incoming library.
    await chat.setActiveCharacter(null);
    return open;
  }

  @override
  Future<void> reattachChat(Object? token) async {
    if (token is! _OpenChat) return;
    final session = await database.getSessionById(token.sessionId);
    if (session == null || session.deletedAt != null) return;
    final chat = _chat;
    if (token.groupId != null) {
      final groups = _read<GroupChatRepository>().groups;
      final group = groups.where((g) => g.id == token.groupId).firstOrNull;
      if (group == null) return;
      await chat.setActiveGroup(group);
    } else {
      final cards = _read<CharacterRepository>().characters;
      final card = cards.where((c) => c.dbId == token.characterId).firstOrNull;
      if (card == null) return;
      await chat.setActiveCharacter(card);
    }
    await chat.loadSession(token.sessionId);
  }

  @override
  void popToRoot() =>
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);

  @override
  Future<bool> rebind() async =>
      await DatabaseRebinder.of(_context).rebind() != null;

  @override
  Future<void> afterSwap() async {
    final storage = _read<StorageService>();
    await reloadLibraryPrefs(storage);
    // Portraits and thumbnails are cached by path, and the paths are the
    // same: only the pictures behind them changed.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    try {
      final thumbs = storage.webThumbnailCacheDir;
      if (await thumbs.exists()) await thumbs.delete(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('[Sync] Could not clear the web thumbnail cache: $e');
    }
  }

  @override
  Future<Map<String, String>> chatTitles(List<String> sessionIds) async {
    if (sessionIds.isEmpty) return const {};
    final marks = List.filled(sessionIds.length, '?').join(', ');
    final rows = await database
        .customSelect(
          'SELECT s.id AS id, s.name AS name, c.name AS card, g.name AS grp '
          'FROM sessions s '
          'LEFT JOIN characters c ON c.id = s.character_id '
          'LEFT JOIN groups g ON g.id = s.group_id '
          'WHERE s.id IN ($marks)',
          variables: [for (final id in sessionIds) Variable(id)],
        )
        .get();
    final names = {
      for (final r in rows)
        r.read<String>('id'):
            _title(r.readNullable<String>('name')) ??
            r.readNullable<String>('card') ??
            r.readNullable<String>('grp') ??
            'a chat',
    };
    return {for (final id in sessionIds) id: names[id] ?? 'a deleted chat'};
  }

  static String? _title(String? name) =>
      name == null || name.trim().isEmpty ? null : name.trim();
}

/// "Send my library when I leave the app" on a phone, which has no quit.
/// The send starts five seconds after the app leaves view, so a file picker
/// or share sheet that comes straight back doesn't start one. If Android
/// freezes the app mid-send, the place is left as it was and the send runs
/// again when the app comes back.
class SyncOnLeave {
  Timer? _timer;
  bool _owed = false;

  static LibrarySyncService? _of(BuildContext context) {
    try {
      return Provider.of<LibrarySyncService>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  void paused(BuildContext context) {
    final sync = _of(context);
    if (sync == null || !sync.settings.sendOnClose) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {
      _owed = true;
      unawaited(_send(sync));
    });
  }

  void resumed(BuildContext context) {
    _timer?.cancel();
    final sync = _of(context);
    if (_owed && sync != null && !sync.busy) unawaited(_send(sync));
  }

  Future<void> _send(LibrarySyncService sync) async {
    if (await sync.sendIfWanted(closing: false)) _owed = false;
  }
}
