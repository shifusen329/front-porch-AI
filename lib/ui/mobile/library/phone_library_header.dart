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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/mobile/library/library_sheets.dart';
import 'package:front_porch_ai/ui/mobile/shell/destination_actions.dart';
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/pages/home/library_controller.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/toolbar/home_toolbar_controls.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The Characters tab's top bar: one search field, with back when inside a
/// folder and a ⋮ for importing, new folders and selection.
class PhoneLibrarySearchBar extends StatelessWidget
    implements PreferredSizeWidget {
  const PhoneLibrarySearchBar({
    super.key,
    required this.library,
    required this.folders,
    required this.onStartSelecting,
  });

  final LibraryController library;
  final FolderService folders;
  final VoidCallback onStartSelecting;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  void _menu(BuildContext context, String value) {
    switch (value) {
      case 'new_folder':
        runHomeFolderDialogAction(
          context,
          FolderDialogAction.create,
          parentId: library.activeFolderId,
          onLeaveFolder: library.leaveDeletedFolder,
        );
      case 'select':
        onStartSelecting();
      default:
        runHomeImportMenu(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inFolder = library.activeFolderId != null;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: SearchBar(
                hintText: inFolder
                    ? 'Search this folder...'
                    : 'Search by name or tag...',
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  AppColors.surfaceContainerOf(context),
                ),
                leading: inFolder
                    ? IconButton(
                        tooltip: 'Up one folder',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => library.goUp(folders.folders),
                      )
                    : const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.search),
                      ),
                onChanged: library.setSearchQuery,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Library actions',
              onSelected: (v) => _menu(context, v),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'cards',
                  child: Text('Import Cards'),
                ),
                // The phone's folder picker gives no folder dart:io can walk.
                if (PlatformCaps.current.canPickDirectories)
                  const PopupMenuItem(
                    value: 'folder',
                    child: Text('Import Folder'),
                  ),
                const PopupMenuItem(
                  value: 'byaf',
                  child: Text('Import Backyard AI (.byaf)'),
                ),
                const PopupMenuItem(
                  value: 'porch',
                  child: Text('Import .porch / .porchpack'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'new_folder',
                  child: Text('New Folder'),
                ),
                const PopupMenuItem(value: 'select', child: Text('Select')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Replaces the search bar while picking cards: how many, and what to do
/// with them.
class PhoneSelectionBar extends StatelessWidget implements PreferredSizeWidget {
  const PhoneSelectionBar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onMove,
    required this.onExport,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onMove;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final none = count == 0;
    return AppBar(
      leading: IconButton(
        tooltip: 'Stop selecting',
        icon: const Icon(Icons.close),
        onPressed: onCancel,
      ),
      title: Text('$count selected'),
      actions: [
        IconButton(
          tooltip: 'Move to Folder',
          icon: const Icon(Icons.drive_file_move),
          onPressed: none ? null : onMove,
        ),
        IconButton(
          tooltip: 'Export',
          icon: const Icon(Icons.upload),
          onPressed: none ? null : onExport,
        ),
        IconButton(
          tooltip: 'Delete',
          icon: Icon(Icons.delete, color: AppColors.negativeAccentOf(context)),
          onPressed: none ? null : onDelete,
        ),
      ],
    );
  }
}

/// Sort, the search scope inside a folder, and the folders at this level.
class PhoneLibraryChips extends StatelessWidget {
  const PhoneLibraryChips({
    super.key,
    required this.library,
    required this.subfolders,
  });

  final LibraryController library;
  final List<CharacterFolder> subfolders;

  static const _folderScopes = [
    (SearchScope.currentFolder, 'This Folder Only'),
    (SearchScope.folderRecursive, 'Folder & Subfolders'),
    (SearchScope.allCharacters, 'All Characters'),
  ];

  Future<void> _folderMenu(BuildContext context, CharacterFolder f) async {
    final action = await showCardActionSheet(
      context,
      title: f.name,
      entries: folderCardMenuEntries,
    );
    if (action == null || !context.mounted) return;
    runHomeFolderDialogAction(
      context,
      switch (action) {
        'rename' => FolderDialogAction.rename,
        'subfolder' => FolderDialogAction.create,
        _ => FolderDialogAction.delete,
      },
      folder: f,
      parentId: action == 'subfolder' ? f.id : null,
      onLeaveFolder: library.leaveDeletedFolder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortLabel = kHomeToolbarSortItems
        .firstWhere(
          (i) => i.$1 == library.sortMode,
          orElse: () => kHomeToolbarSortItems.first,
        )
        .$2;
    final inFolder = library.activeFolderId != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        spacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.swap_vert, size: 18),
            label: Text(sortLabel),
            onPressed: () async {
              final mode = await showSortSheet(
                context,
                current: library.sortMode,
              );
              if (mode != null) library.setSortMode(mode);
            },
          ),
          if (inFolder)
            PopupMenuButton<SearchScope>(
              tooltip: 'Where a search looks',
              initialValue: library.searchScope,
              onSelected: library.setSearchScope,
              itemBuilder: (_) => [
                for (final (scope, label) in _folderScopes)
                  PopupMenuItem(value: scope, child: Text(label)),
              ],
              child: Chip(
                avatar: const Icon(Icons.filter_list, size: 18),
                label: Text(
                  _folderScopes
                      .firstWhere((s) => s.$1 == library.searchScope)
                      .$2,
                ),
              ),
            ),
          for (final f in subfolders)
            GestureDetector(
              onLongPress: () => _folderMenu(context, f),
              child: ActionChip(
                avatar: Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: AppColors.porchAmberOf(context),
                ),
                label: Text(f.name),
                onPressed: () => library.openFolder(f.id),
              ),
            ),
        ],
      ),
    );
  }
}

class PhoneSectionLabel extends StatelessWidget {
  const PhoneSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textTertiary(context),
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A library with nothing in it yet.
class PhoneLibraryEmpty extends StatelessWidget {
  const PhoneLibraryEmpty({super.key, required this.onCreate});

  final VoidCallback onCreate;

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
              Icons.people_outline,
              size: 56,
              color: AppColors.iconSecondary(context),
            ),
            Text(
              'No characters yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () =>
                  phoneDestinationActions['ai_creator']?.call(context),
              icon: const Icon(Icons.psychology),
              label: const Text('Create with AI'),
            ),
            OutlinedButton.icon(
              onPressed: () => HomeCardImport(context).pickCards(),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import a card'),
            ),
            TextButton(
              onPressed: onCreate,
              child: const Text('More ways to start'),
            ),
          ],
        ),
      ),
    );
  }
}
