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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/mobile/library/library_sheets.dart';
import 'package:front_porch_ai/ui/mobile/library/phone_library_card.dart';
import 'package:front_porch_ai/ui/mobile/library/phone_library_header.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/mobile/shell/destination_actions.dart';
import 'package:front_porch_ai/ui/mobile/shell/phone_tab_scope.dart';
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/pages/home/library_controller.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The phone's Characters tab: the library the desktop's Home grid shows
/// (same [libraryViewOf], same card actions), laid out for a touch screen.
class PhoneLibraryTab extends StatefulWidget {
  const PhoneLibraryTab({super.key});

  @override
  State<PhoneLibraryTab> createState() => _PhoneLibraryTabState();
}

class _PhoneLibraryTabState extends State<PhoneLibraryTab> {
  late final LibraryController _library;
  late final HomeChatOpener _chats;

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    _library = LibraryController(storage.uiSettings)
      ..addListener(_onLibraryChanged);
    storage.initialized.then((_) {
      if (mounted) _library.reloadViewPrefs();
    });
    _chats = HomeChatOpener(
      context: context,
      isMounted: () => mounted,
      onChatClosed: _refreshActivity,
    );
    Future.microtask(_refreshActivity);
  }

  PhoneTabHooks? _hooks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hooks = PhoneTabScope.hooksOf(context)
      ?..register(kCharactersDestination, onBack: _back, onReselect: _toTop);
  }

  @override
  void dispose() {
    _hooks?.unregister(kCharactersDestination);
    _library
      ..removeListener(_onLibraryChanged)
      ..dispose();
    super.dispose();
  }

  /// Back leaves selection, then goes up a folder, before the shell's turn.
  bool _back() {
    final selection = _library.selection;
    if (selection.isSelecting) {
      selection.cancel();
      return true;
    }
    if (_library.activeFolderId == null) return false;
    _library.goUp(Provider.of<FolderService>(context, listen: false).folders);
    return true;
  }

  /// Tapping the open tab again returns to the library's top level.
  void _toTop() {
    final selection = _library.selection;
    if (selection.isSelecting) selection.cancel();
    _library.openFolder(null);
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshActivity() async {
    if (!mounted) return;
    await _library.refreshActivity(
      Provider.of<CharacterRepository>(context, listen: false),
    );
  }

  String? _metaFor(CharacterCard c) {
    final count = _library.messageCounts[c.stableGroupId] ?? 0;
    final at = _library.lastActivity[c.stableGroupId];
    final parts = [
      if (count > 0) '$count msg${count == 1 ? '' : 's'}',
      if (at != null) formatRelativeTime(at),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _characterMenu(CharacterCard c) async {
    final action = await showCardActionSheet(
      context,
      title: c.name,
      subtitle: _metaFor(c),
      entries: characterCardMenuEntries(
        inFolder: _library.activeFolderId != null,
      ),
    );
    if (action == null || !mounted) return;
    if (action == kSelectCardAction) return _startSelecting(c.stableGroupId);
    runHomeCharacterMenuAction(
      context,
      action,
      c,
      chats: _chats,
      activeFolderId: _library.activeFolderId,
    );
  }

  Future<void> _groupMenu(GroupChat g) async {
    final action = await showCardActionSheet(
      context,
      title: g.name,
      entries: groupCardMenuEntries(inFolder: _library.activeFolderId != null),
    );
    if (action == null || !mounted) return;
    if (action == kSelectCardAction) return _startSelecting(g.id, group: true);
    runHomeGroupMenuAction(
      context,
      action,
      g,
      chats: _chats,
      activeFolderId: _library.activeFolderId,
    );
  }

  void _startSelecting(String key, {bool group = false}) {
    final selection = _library.selection;
    if (!selection.isSelecting) selection.toggleSelectMode();
    selection.toggle(key, group: group);
  }

  Future<void> _create() async {
    final choice = await showCreateSheet(context);
    if (choice == null || !mounted) return;
    if (choice == kImportCardAction) {
      await HomeCardImport(context).pickCards();
      return;
    }
    await phoneDestinationActions[choice]?.call(context);
  }

  SelectionTally _tally() => tallyHomeSelection(
    context,
    _library.selection,
    activeFolderId: _library.activeFolderId,
    query: _library.searchQuery,
    scope: _library.searchScope,
    sortMode: _library.sortMode,
  );

  @override
  Widget build(BuildContext context) {
    return Consumer3<CharacterRepository, FolderService, GroupChatRepository>(
      builder: (context, repo, folders, groups, _) {
        final selection = _library.selection;
        return Scaffold(
          appBar: selection.isSelecting
              ? PhoneSelectionBar(
                  count: _tally().total,
                  onCancel: selection.cancel,
                  onMove: () => showHomeMoveSelectionDialog(
                    context,
                    picks: _tally(),
                    selection: selection,
                  ),
                  onExport: () => exportHomeSelectionPorch(
                    context,
                    selection.characterIds,
                    groupsLeftOut: selection.groupIds.isNotEmpty,
                    onSaved: selection.cancel,
                  ),
                  onDelete: () => massDeleteHomeSelection(
                    context,
                    selection.characterIds,
                    groupIds: selection.groupIds,
                    hiddenCount: () => _tally().hidden,
                    onDeleted: selection.cancel,
                  ),
                )
              : PhoneLibrarySearchBar(
                  library: _library,
                  folders: folders,
                  onStartSelecting: selection.toggleSelectMode,
                ),
          floatingActionButton: selection.isSelecting
              ? null
              : FloatingActionButton.extended(
                  heroTag: kCharactersDestination,
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                ),
          body: repo.isLoading
              ? const Center(child: CircularProgressIndicator())
              : repo.characters.isEmpty && groups.groups.isEmpty
              ? PhoneLibraryEmpty(onCreate: _create)
              : _grid(context, repo, folders, groups),
        );
      },
    );
  }

  Widget _grid(
    BuildContext context,
    CharacterRepository repo,
    FolderService folders,
    GroupChatRepository groups,
  ) {
    final view = libraryViewOf(
      characters: repo.characters,
      groups: groups.groups,
      folders: folders,
      activeFolderId: _library.activeFolderId,
      query: _library.searchQuery,
      scope: _library.searchScope,
      sortMode: _library.sortMode,
      lastActivity: _library.lastActivity,
      messageCount: _library.messageCounts,
    );
    final selection = _library.selection;
    final columns = (MediaQuery.sizeOf(context).width ~/ 180).clamp(2, 6);
    SliverGrid cards(List<Widget> tiles) => SliverGrid.count(
      crossAxisCount: columns,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 3 / 4,
      children: tiles,
    );
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PhoneLibraryChips(library: _library, subfolders: view.folders),
        ),
        if (view.groups.isNotEmpty) ...[
          const SliverToBoxAdapter(child: PhoneSectionLabel('GROUPS')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: cards([
              for (final g in view.groups)
                PhoneGroupCard(
                  key: ValueKey('group-${g.id}'),
                  group: g,
                  groupRepo: groups,
                  selecting: selection.isSelecting,
                  selected: selection.groupIds.contains(g.id),
                  onTap: () => selection.isSelecting
                      ? selection.toggle(g.id, group: true)
                      : _chats.tapGroup(g),
                  onMenu: () => _groupMenu(g),
                ),
            ]),
          ),
        ],
        if (view.characters.isNotEmpty) ...[
          const SliverToBoxAdapter(child: PhoneSectionLabel('CHARACTERS')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: cards([
              for (final c in view.characters)
                PhoneCharacterCard(
                  key: ValueKey('character-${c.stableGroupId}'),
                  character: c,
                  image: (card) => resolveHomeCardImage(context, card),
                  imageCacheEpoch: repo.coverEpoch,
                  meta: _metaFor(c),
                  selecting: selection.isSelecting,
                  selected: selection.characterIds.contains(c.stableGroupId),
                  onTap: () => selection.isSelecting
                      ? selection.toggle(c.stableGroupId, group: false)
                      : _chats.tapCharacter(c),
                  onMenu: () => _characterMenu(c),
                ),
            ]),
          ),
        ],
        if (view.groups.isEmpty && view.characters.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                _library.searchQuery.isEmpty
                    ? 'This folder is empty.'
                    : 'Nothing matches "${_library.searchQuery}".',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
          ),
        // Room under the last row for the New button.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}
