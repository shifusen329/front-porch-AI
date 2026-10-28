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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseRecentSessions, RecentSession;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show recentChatSnippet;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/mobile/chats/chats_sheets.dart';
import 'package:front_porch_ai/ui/mobile/chats/recent_chat_row.dart';
import 'package:front_porch_ai/ui/mobile/shell/destination_actions.dart';
import 'package:front_porch_ai/ui/mobile/shell/mobile_shell.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// How many conversations the list reads.
const _kRecentLimit = 100;

/// The phone's start screen: recent conversations, newest first, 1:1 and
/// group together. Tapping one opens exactly that chat.
class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late final HomeChatOpener _chats = HomeChatOpener(
    context: context,
    isMounted: () => mounted,
    onChatClosed: _reload,
  );
  List<RecentSession>? _rows;
  bool _failed = false;
  String _query = '';
  bool _searching = false;
  String? _shownTab;

  PhoneTabHooks? _hooks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Back into view after another tab (a chat may have been had there).
    final tab = PhoneTabScope.selectedOf(context);
    if (tab == kChatsDestination && tab != _shownTab) _reload();
    _shownTab = tab;
    _hooks = PhoneTabScope.hooksOf(context)
      ?..register(
        kChatsDestination,
        onBack: () {
          if (!_searching) return false;
          _stopSearching();
          return true;
        },
        onReselect: () {
          if (_searching) _stopSearching();
          _reload();
        },
      );
  }

  @override
  void dispose() {
    _hooks?.unregister(kChatsDestination);
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    try {
      final rows = await liveDatabase(context).getRecentSessions(_kRecentLimit);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _failed = false;
      });
    } catch (e) {
      debugPrint('[Chats] recent chats could not be read: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  ({CharacterCard? character, GroupChat? group}) _ownerOf(
    RecentSession row,
    CharacterRepository repo,
    GroupChatRepository groups,
  ) => (
    character: row.isGroup
        ? null
        : repo.characters.where((c) => c.dbId == row.characterId).firstOrNull,
    group: row.isGroup
        ? groups.groups.where((g) => g.id == row.groupId).firstOrNull
        : null,
  );

  Future<void> _menu(
    RecentSession row,
    ({CharacterCard? character, GroupChat? group}) owner,
  ) async {
    final action = await showRecentChatSheet(context, row);
    if (action == null || !mounted) return;
    switch (action) {
      case RecentChatAction.newChat:
        await _chats.startNewChatWith(
          character: owner.character,
          group: owner.group,
        );
      case RecentChatAction.allChats:
        await _chats.showChatHistory(
          character: owner.character,
          group: owner.group,
        );
        await _reload();
      case RecentChatAction.rename:
        final name = await askRecentChatName(context, row);
        if (name == null || !mounted) return;
        await Provider.of<ChatService>(
          context,
          listen: false,
        ).renameSession(row.sessionId, name);
        await _reload();
      case RecentChatAction.delete:
        if (!await confirmDeleteRecentChat(context, row) || !mounted) return;
        await Provider.of<ChatService>(
          context,
          listen: false,
        ).deleteSession(row.sessionId, startReplacement: false);
        await _reload();
    }
  }

  void _stopSearching() => setState(() {
    _searching = false;
    _query = '';
  });

  bool _matches(RecentSession row, String? snippet) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return row.displayName.toLowerCase().contains(q) ||
        (row.sessionName?.toLowerCase().contains(q) ?? false) ||
        (snippet?.toLowerCase().contains(q) ?? false);
  }

  PreferredSizeWidget _appBar() {
    if (!_searching) {
      return AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Search chats',
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _searching = true),
          ),
        ],
      );
    }
    return AppBar(
      leading: IconButton(
        tooltip: 'Stop searching',
        icon: const Icon(Icons.arrow_back),
        onPressed: _stopSearching,
      ),
      title: TextField(
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search by name or words',
          border: InputBorder.none,
        ),
        onChanged: (q) => setState(() => _query = q),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      floatingActionButton: FloatingActionButton.extended(
        // Every tab stays mounted, so each FAB needs its own hero tag.
        heroTag: kChatsDestination,
        onPressed: () => startChatFromPicker(context, _chats),
        icon: const Icon(Icons.edit_square),
        label: const Text('Chat'),
      ),
      body: Consumer2<CharacterRepository, GroupChatRepository>(
        builder: (context, repo, groups, _) {
          final rows = _rows;
          if (_failed) {
            return _Message(
              'Your chats could not be read.',
              action: TextButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            );
          }
          if (rows == null || repo.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (rows.isEmpty) return const _EmptyChats();
          final shown = [
            for (final row in rows)
              if (recentChatSnippet(row) case final snippet
                  when _matches(row, snippet))
                (row, snippet),
          ];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 86),
              itemBuilder: (context, i) {
                final (row, snippet) = shown[i];
                final owner = _ownerOf(row, repo, groups);
                return RecentChatRow(
                  key: ValueKey(row.sessionId),
                  session: row,
                  snippet: snippet,
                  character: owner.character,
                  group: owner.group,
                  groupRepo: groups,
                  imageCacheEpoch: repo.coverEpoch,
                  onTap: () {
                    if (owner.character == null && owner.group == null) {
                      return;
                    }
                    _chats.openSession(
                      sessionId: row.sessionId,
                      character: owner.character,
                      group: owner.group,
                    );
                  },
                  onMenu: () => _menu(row, owner),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// No conversation yet: point at the characters, or making one.
class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: AppColors.iconSecondary(context),
            ),
            Text(
              'No conversations yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Pick a character to start one.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: () =>
                  Provider.of<AppState>(context, listen: false).showLibrary(),
              icon: const Icon(Icons.people_outline),
              label: const Text('Go to Characters'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  phoneDestinationActions['ai_creator']?.call(context),
              icon: const Icon(Icons.psychology),
              label: const Text('Create with AI'),
            ),
          ],
        ),
      ),
    );
  }
}
