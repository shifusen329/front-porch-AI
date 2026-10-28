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

import 'package:front_porch_ai/database/database.dart' show RecentSession;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

enum RecentChatAction { newChat, allChats, rename, delete }

/// A conversation's long-press actions.
Future<RecentChatAction?> showRecentChatSheet(
  BuildContext context,
  RecentSession row,
) {
  Widget tile(
    BuildContext sheet,
    RecentChatAction action,
    IconData icon,
    String label, {
    Color? color,
  }) => ListTile(
    leading: Icon(icon, color: color ?? AppColors.iconSecondary(sheet)),
    title: Text(label, style: color == null ? null : TextStyle(color: color)),
    onTap: () => Navigator.of(sheet).pop(action),
  );

  return showWarmSheet<RecentChatAction>(
    context,
    builder: (sheet) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              row.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: row.sessionName == null ? null : Text(row.sessionName!),
          ),
          const Divider(),
          tile(
            sheet,
            RecentChatAction.newChat,
            Icons.add_comment_outlined,
            'Start New Chat',
            color: AppColors.porchAmberOf(sheet),
          ),
          tile(sheet, RecentChatAction.allChats, Icons.history, 'Manage Chats'),
          tile(
            sheet,
            RecentChatAction.rename,
            Icons.drive_file_rename_outline,
            'Rename',
          ),
          const Divider(),
          tile(
            sheet,
            RecentChatAction.delete,
            Icons.delete,
            'Delete',
            color: AppColors.negativeAccentOf(sheet),
          ),
        ],
      ),
    ),
  );
}

/// The chat's new name, or null when the user backs out.
Future<String?> askRecentChatName(BuildContext context, RecentSession row) {
  final controller = TextEditingController(text: row.sessionName ?? '');
  return showWarmDialogOf<String>(
    context,
    builder: (dialog) => WarmDialog(
      title: 'Rename Chat',
      icon: Icons.drive_file_rename_outline,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: 'A chat with ${row.displayName}'),
        onSubmitted: (v) => Navigator.of(dialog).pop(v.trim()),
      ),
      actions: [
        warmDialogCancel(dialog),
        warmDialogConfirm(
          dialog,
          label: 'Save',
          onPressed: () => Navigator.of(dialog).pop(controller.text.trim()),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Asks before a conversation is deleted for good.
Future<bool> confirmDeleteRecentChat(
  BuildContext context,
  RecentSession row,
) async {
  final ok = await showWarmDialog<bool>(
    context,
    title: 'Delete Chat?',
    icon: Icons.delete,
    destructive: true,
    content: WarmDialogText(
      'This chat with ${row.displayName} and its '
      '${row.messageCount} message${row.messageCount == 1 ? '' : 's'} '
      'will be deleted. This cannot be undone.',
    ),
    actions: [
      warmDialogCancel(context, value: false),
      Builder(
        builder: (dialog) => warmDialogConfirm(
          dialog,
          label: 'Delete',
          destructive: true,
          onPressed: () => Navigator.of(dialog).pop(true),
        ),
      ),
    ],
  );
  return ok ?? false;
}

/// The Chats tab's "Chat" button: pick who to talk to, then start fresh.
Future<void> startChatFromPicker(
  BuildContext context,
  HomeChatOpener chats,
) async {
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  final groups = Provider.of<GroupChatRepository>(context, listen: false);
  final characters = [...repo.characters]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final casts = [...groups.groups]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final picked = await showWarmSheet<Object>(
    context,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheet).height * 0.7,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text(
              'Chat with…',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final g in casts)
            ListTile(
              leading: Icon(
                Icons.groups,
                color: AppColors.porchTerracottaOf(sheet),
              ),
              title: Text(g.name),
              onTap: () => Navigator.of(sheet).pop(g),
            ),
          for (final c in characters)
            ListTile(
              leading: Icon(
                Icons.person_outline,
                color: AppColors.iconSecondary(sheet),
              ),
              title: Text(c.name),
              onTap: () => Navigator.of(sheet).pop(c),
            ),
          if (characters.isEmpty && casts.isEmpty)
            const ListTile(title: Text('No characters yet.')),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await chats.startNewChatWith(
    character: picked is CharacterCard ? picked : null,
    group: picked is GroupChat ? picked : null,
  );
}
