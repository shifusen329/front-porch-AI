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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// How a card-menu row is coloured: plain, an amber icon, an amber icon and
/// label, the journal teal icon, or a destructive red row.
enum CardMenuTone { plain, accent, accentLabel, journal, danger }

/// One action on a home-grid card. The desktop shows these as a right-click
/// menu, the phone as a sheet; [value] is what the card's action handler
/// dispatches on, so both run the same code.
class CardMenuEntry {
  const CardMenuEntry(
    this.value,
    this.icon,
    this.label, {
    this.tone = CardMenuTone.plain,
  });

  final String value;
  final IconData icon;
  final String label;
  final CardMenuTone tone;

  Color iconColor(BuildContext context) => switch (tone) {
    CardMenuTone.plain => AppColors.iconSecondary(context),
    CardMenuTone.accent ||
    CardMenuTone.accentLabel => AppColors.porchAmberOf(context),
    CardMenuTone.journal => AppColors.journalAccentOf(context),
    CardMenuTone.danger => AppColors.negativeAccentOf(context),
  };

  Color labelColor(BuildContext context) => switch (tone) {
    CardMenuTone.accentLabel => AppColors.porchAmberOf(context),
    CardMenuTone.danger => AppColors.negativeAccentOf(context),
    _ => AppColors.textPrimary(context),
  };
}

/// One row of a home-grid card's right-click menu.
PopupMenuItem<String> homeCardMenuItem(
  BuildContext context,
  CardMenuEntry entry,
) {
  return PopupMenuItem<String>(
    value: entry.value,
    child: ListTile(
      leading: Icon(entry.icon, color: entry.iconColor(context), size: 20),
      title: Text(
        entry.label,
        style: TextStyle(color: entry.labelColor(context)),
      ),
      dense: true,
      contentPadding: EdgeInsets.zero,
    ),
  );
}

const _removeFromFolder = CardMenuEntry(
  'remove_folder',
  Icons.folder_off,
  'Remove from Folder',
  tone: CardMenuTone.accentLabel,
);

const _delete = CardMenuEntry(
  'delete',
  Icons.delete,
  'Delete',
  tone: CardMenuTone.danger,
);

/// The character card's actions. Values are dispatched by
/// `runHomeCharacterMenuAction`.
List<CardMenuEntry> characterCardMenuEntries({required bool inFolder}) => [
  // Start-fresh sits first: it's the most common intent after "open", and
  // it picks its own persona (never inheriting whatever the last chat used).
  const CardMenuEntry(
    'new_chat',
    Icons.add_comment_outlined,
    'Start New Chat',
    tone: CardMenuTone.accent,
  ),
  const CardMenuEntry('chat_history', Icons.history, 'Manage Chats'),
  const CardMenuEntry('edit', Icons.edit, 'Edit Character'),
  // Grow the card from a real chat: interview + rewrite grounded in how the
  // character was actually played. Saves as a new "(Enhanced)" duplicate.
  const CardMenuEntry(
    'ai_enhance',
    Icons.auto_awesome,
    'AI Enhance',
    tone: CardMenuTone.accent,
  ),
  const CardMenuEntry(
    'avatar_gallery',
    Icons.photo_library_outlined,
    'Avatar Gallery',
  ),
  const CardMenuEntry('duplicate', Icons.copy, 'Duplicate Character'),
  // SillyTavern's "Convert to Persona": a copy you can play as.
  const CardMenuEntry('use_as_persona', Icons.switch_account, 'Use as Persona'),
  const CardMenuEntry('export', Icons.upload, 'Export PNG'),
  const CardMenuEntry('export_json', Icons.data_object, 'Export JSON'),
  // Filing a single character was drag-only before this — the menu could
  // take one OUT of a folder but never put one in, or move it between
  // folders (the picker lists every folder by full path, so it doubles as
  // "move up one level" when nested). Group cards already had this.
  const CardMenuEntry(
    'move_folder',
    Icons.drive_file_move,
    'Move to Folder…',
    tone: CardMenuTone.accent,
  ),
  if (inFolder) _removeFromFolder,
  _delete,
];

/// Group card actions (same ordering rule as character cards).
List<CardMenuEntry> groupCardMenuEntries({required bool inFolder}) => [
  const CardMenuEntry(
    'new_chat',
    Icons.add_comment_outlined,
    'Start New Chat',
    tone: CardMenuTone.accent,
  ),
  const CardMenuEntry('chat_history', Icons.history, 'Manage Chats'),
  const CardMenuEntry('edit', Icons.edit, 'Edit Group'),
  const CardMenuEntry('duplicate', Icons.copy, 'Duplicate Group'),
  const CardMenuEntry('export', Icons.upload, 'Export PNG'),
  const CardMenuEntry(
    'extract',
    Icons.call_split,
    'Extract Characters',
    tone: CardMenuTone.journal,
  ),
  const CardMenuEntry(
    'move_folder',
    Icons.drive_file_move,
    'Move to Folder',
    tone: CardMenuTone.accent,
  ),
  if (inFolder) _removeFromFolder,
  _delete,
];

/// A folder's actions. Values map to `FolderDialogAction`s.
const folderCardMenuEntries = <CardMenuEntry>[
  CardMenuEntry('rename', Icons.drive_file_rename_outline, 'Rename Folder'),
  CardMenuEntry(
    'subfolder',
    Icons.create_new_folder,
    'New Subfolder',
    tone: CardMenuTone.accent,
  ),
  CardMenuEntry(
    'delete',
    Icons.delete,
    'Delete Folder…',
    tone: CardMenuTone.danger,
  ),
];

/// The character card's right-click menu.
List<PopupMenuItem<String>> characterCardMenuItems(
  BuildContext context, {
  required bool inFolder,
}) => [
  for (final e in characterCardMenuEntries(inFolder: inFolder))
    homeCardMenuItem(context, e),
];

/// The group card's right-click menu.
List<PopupMenuItem<String>> groupCardMenuItems(
  BuildContext context, {
  required bool inFolder,
}) => [
  for (final e in groupCardMenuEntries(inFolder: inFolder))
    homeCardMenuItem(context, e),
];
