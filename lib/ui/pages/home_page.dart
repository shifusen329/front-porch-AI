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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';
import 'package:front_porch_ai/ui/pages/home/home_page_chrome.dart';
import 'package:front_porch_ai/ui/pages/home/library_controller.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_mode_toggle.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Search, folder, sort, grid size, picks and activity: what the library
  /// shows. This page is its desktop chrome.
  late final LibraryController _library;

  final _searchController = TextEditingController();

  // Chats / Porch Stories / Waifu Coder
  HomeMode _homeMode = HomeMode.chats;

  /// Every way into a chat (taps, menus, Manage Chats, OPEN_CHAT) and the
  /// busy guard that stops stacked open-chat taps.
  late final HomeChatOpener _chats;

  // Scroll controller for the character grid (visible scrollbar)
  final ScrollController _gridScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _chats = HomeChatOpener(
      context: context,
      isMounted: () => mounted,
      onChatClosed: _refreshLastActivityCache,
    );
    final storage = Provider.of<StorageService>(context, listen: false);
    _library = LibraryController(storage.uiSettings)
      ..addListener(_onLibraryChanged);
    // StorageService._init() is async — settings may not be loaded yet.
    // Wait for init to complete so persisted values are reflected.
    storage.initialized.then((_) {
      if (!mounted) return;
      _library.reloadViewPrefs();
    });
    Future.microtask(() => _refreshLastActivityCache());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _chats.maybeOpenChatFromEnv(),
    );
  }

  // The notifiers we subscribed to, held so dispose() can unsubscribe: they
  // are app-scoped providers, MainLayout swaps HomePage out of the tree on
  // every sidebar navigation, and a Provider.of lookup is no longer legal
  // once the element is defunct — so the reference has to be captured here.
  KoboldService? _koboldListened;
  CharacterRepository? _charRepoListened;
  AppState? _appStateListened;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for model-ready events from KoboldService
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      _koboldListened?.removeListener(_onKoboldUpdate);
      kobold.removeListener(_onKoboldUpdate);
      kobold.addListener(_onKoboldUpdate);
      _koboldListened = kobold;
    } catch (_) {
      // KoboldService might not be in the provider tree
    }
    // Listen for CharacterRepository changes to refresh cache after characters load
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      _charRepoListened?.removeListener(_onCharactersChanged);
      charRepo.removeListener(_onCharactersChanged);
      charRepo.addListener(_onCharactersChanged);
      _charRepoListened = charRepo;
    } catch (_) {}
    // Re-tapping the sidebar's Home entry bumps AppState.homeResetTick —
    // treat it as "take me back to the main screen" (library top level).
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      _lastHomeResetTick ??= appState.homeResetTick;
      _appStateListened?.removeListener(_onAppStateChanged);
      appState.removeListener(_onAppStateChanged);
      appState.addListener(_onAppStateChanged);
      appState.pageBack = _stepBack;
      _appStateListened = appState;
    } catch (_) {}
  }

  /// Back on Home (Escape): a sub-app returns to Chats, then picks are
  /// called off, then the open folder goes up a level.
  bool _stepBack() {
    if (_homeMode != HomeMode.chats) {
      _setHomeMode(HomeMode.chats);
      return true;
    }
    final selection = _library.selection;
    if (selection.picking) {
      selection.cancel();
      return true;
    }
    if (_library.activeFolderId == null) return false;
    _library.goUp(Provider.of<FolderService>(context, listen: false).folders);
    return true;
  }

  int? _lastHomeResetTick;

  Timer? _activityRefreshDebounce;

  @override
  void dispose() {
    _activityRefreshDebounce?.cancel();
    _library
      ..removeListener(_onLibraryChanged)
      ..dispose();
    _searchController.dispose();
    _gridScrollController.dispose();
    _koboldListened?.removeListener(_onKoboldUpdate);
    _charRepoListened?.removeListener(_onCharactersChanged);
    _appStateListened?.removeListener(_onAppStateChanged);
    if (_appStateListened?.pageBack == _stepBack) {
      _appStateListened?.pageBack = null;
    }
    // A remounted Home opens on Chats, so the sidebar comes back with it.
    _appStateListened?.setSidebarHidden(false, notify: false);
    super.dispose();
  }

  Widget _buildModeToggle() {
    return HomeModeToggle(
      showStories: _homeMode == HomeMode.stories,
      showWaifu: _homeMode == HomeMode.waifu,
      studio: _homeMode == HomeMode.stories,
      onShowChats: () => _setHomeMode(HomeMode.chats),
      onShowStories: () => _setHomeMode(HomeMode.stories),
      onShowWaifu: () => _setHomeMode(HomeMode.waifu),
    );
  }

  void _setHomeMode(HomeMode mode) {
    setState(() => _homeMode = mode);
    Provider.of<AppState>(
      context,
      listen: false,
    ).setSidebarHidden(mode != HomeMode.chats);
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.homeResetTick != _lastHomeResetTick) {
        _lastHomeResetTick = appState.homeResetTick;
        _library.openFolder(null);
      }
    } catch (_) {}
  }

  void _onCharactersChanged() {
    if (!mounted) return;
    _activityRefreshDebounce?.cancel();
    _activityRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
      _activityRefreshDebounce = null;
      if (mounted) _refreshLastActivityCache();
    });
    // Characters often land after Home's first frame — retry the launch hook.
    _chats.maybeOpenChatFromEnv();
  }

  // No toast when a model finishes loading: dual-local mouth/worker swaps
  // mark ready on every GGUF load, and the success SnackBars stacked.
  // Kobold notifies per console burst. While the chat route covers Home the
  // Overlay turns its tickers off; build depends on that, so Home redraws
  // fresh once it is uncovered and skips every update until then.
  void _onKoboldUpdate() {
    if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) {
      return;
    }
    setState(() {}); // Rebuild to update status bar
  }

  /// The library changed (search, folder, sort, picks, activity): redraw.
  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshLastActivityCache() async {
    if (!mounted) return;
    await _library.refreshActivity(
      Provider.of<CharacterRepository>(context, listen: false),
    );
  }

  /// A drop on a folder tile or on a level of the path (null: the top
  /// level). A dragged selection moves in one go and says so; a single
  /// card moves quietly, as it always has.
  Future<void> _handleDropOnLevel(Object item, String? folderId) async {
    final moved = await _library.selection.drop(
      item,
      folderId,
      folders: Provider.of<FolderService>(context, listen: false),
      library: Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).characters,
    );
    if (moved != null && item is LibraryDragPayload && mounted) {
      snackHomeMoved(context, moved, folderId);
    }
  }

  SelectionTally _selectionTally() => tallyHomeSelection(
    context,
    _library.selection,
    activeFolderId: _library.activeFolderId,
    query: _library.searchQuery,
    scope: _library.searchScope,
    sortMode: _library.sortMode,
  );

  /// Desktop PNG/BYAF/.porch drop on the chats library. [context] is the
  /// library view's, which survives the empty → populated switch.
  Widget _wrapChatsWithDrop(BuildContext context, Widget child) {
    return HomeDropZone(
      onDrop: (sources) => HomeDropImport(
        context,
        importPorchPaths: (paths) => importHomePorchPaths(this.context, paths),
      ).importDroppedFiles(sources),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    TickerMode.valuesOf(context); // see _onKoboldUpdate
    return Consumer3<CharacterRepository, FolderService, GroupChatRepository>(
      builder: (context, repo, folderService, groupRepo, child) {
        if (repo.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Porch Stories BEFORE the empty-library check: a story needs no
        // characters, so stories mode has to win over the "create your first
        // character" panel. Checked after it, tapping the toggle on a fresh
        // install set stories mode but still fell into the empty branch, so
        // the view never opened.
        if (_homeMode != HomeMode.chats) {
          final stories = _homeMode == HomeMode.stories;
          final bar = HomeModeToggleBar(toggle: _buildModeToggle());
          return HomeStatusFrame(
            content: Column(
              children: [
                if (stories)
                  ColoredBox(color: StudioColors.sideOf(context), child: bar)
                else
                  bar,
                Expanded(
                  child: stories
                      ? const StoryHomeView()
                      : const WaifuHomeView(),
                ),
              ],
            ),
          );
        }

        if (repo.characters.isEmpty && groupRepo.groups.isEmpty) {
          // The mode toggle rides ABOVE the empty state: Porch Stories needs
          // no characters, so a brand-new library must still be able to reach
          // it. Without this the toggle simply did not exist on a fresh
          // install and Stories was unreachable (found by the E2E suite).
          return _wrapChatsWithDrop(
            context,
            Column(
              children: [
                HomeModeToggleBar(toggle: _buildModeToggle()),
                Expanded(
                  child: HomeEmptyLibrary(
                    onImportCards: () => HomeCardImport(context).pickCards(),
                    onBulkImport: () => HomeBulkImport(context).importFolder(),
                    onImportByaf: () => HomeCardImport(context).pickByaf(),
                  ),
                ),
              ],
            ),
          );
        }

        final library = _library;
        final selection = library.selection;
        return _wrapChatsWithDrop(
          context,
          HomeStatusFrame(
            content: CharacterCardGrid(
              searchQuery: library.searchQuery,
              searchScope: library.searchScope,
              activeFolderId: library.activeFolderId,
              sortMode: library.sortMode,
              lastActivityCache: library.lastActivity,
              messageCountCache: library.messageCounts,
              gridScale: library.gridScale,
              isSelecting: selection.isSelecting,
              isOrganizing: selection.isOrganizing,
              selectedCharacterIds: selection.characterIds,
              selectedGroupIds: selection.groupIds,
              searchController: _searchController,
              gridScrollController: _gridScrollController,
              repo: repo,
              folderService: folderService,
              groupRepo: groupRepo,
              modeToggle: _buildModeToggle(),
              onTapCharacter: _chats.tapCharacter,
              onTapGroup: _chats.tapGroup,
              onToggleSelect: (c) =>
                  selection.toggle(c.stableGroupId, group: false),
              onToggleSelectGroup: (g) => selection.toggle(g.id, group: true),
              onToggleSelectMode: selection.toggleSelectMode,
              onToggleOrganizeMode: selection.toggleOrganizeMode,
              onContextMenuAction: (action, character) =>
                  runHomeCharacterMenuAction(
                    this.context,
                    action,
                    character,
                    chats: _chats,
                    activeFolderId: library.activeFolderId,
                  ),
              onImport: (source) => runHomeImportMenu(this.context, source),
              // Both draggable kinds: characters keyed by image filename, group
              // casts by their group id (see FolderService).
              onAcceptFolderDrop: (item, folder) =>
                  _handleDropOnLevel(item, folder.id),
              onFolderDialogAction: (action, {folder, parentId}) =>
                  runHomeFolderDialogAction(
                    this.context,
                    action,
                    folder: folder,
                    parentId: parentId,
                    onLeaveFolder: library.leaveDeletedFolder,
                  ),
              onFolderTap: (folder) => library.openFolder(folder.id),
              onFolderNavigateBack: () => library.goUp(folderService.folders),
              onFolderJump: library.openFolder,
              onCancelSelection: selection.cancel,
              onDeleteSelected: (ids) => massDeleteHomeSelection(
                this.context,
                ids,
                groupIds: selection.groupIds,
                hiddenCount: () => _selectionTally().hidden,
                onDeleted: selection.cancel,
              ),
              // onCreateGroup no longer wired — old select-for-group path deprecated.
              onMoveToFolder: (_) => showHomeMoveSelectionDialog(
                this.context,
                picks: _selectionTally(),
                selection: selection,
              ),
              onExportSelected: (ids) => exportHomeSelectionPorch(
                this.context,
                ids,
                groupsLeftOut: selection.groupIds.isNotEmpty,
                onSaved: selection.cancel,
              ),
              onSortChanged: library.setSortMode,
              onGridScaleChanged: library.previewGridScale,
              onGridScaleChangeEnd: library.commitGridScale,
              onSearchScopeChanged: library.setSearchScope,
              onSearchQueryChanged: library.setSearchQuery,
              onResolveCharImage: (c) => resolveHomeCardImage(this.context, c),
              onDeleteGroup: (group) =>
                  confirmDeleteHomeGroup(this.context, group),
              onAfterNavigateBack: _refreshLastActivityCache,
              onGroupContextMenuAction: (action, group) =>
                  runHomeGroupMenuAction(
                    this.context,
                    action,
                    group,
                    chats: _chats,
                    activeFolderId: library.activeFolderId,
                  ),
              onSelectAll: selection.selectAll,
              onSelectNone: selection.selectNone,
              selection: selection,
              onDropOnLevel: _handleDropOnLevel,
            ),
          ),
        );
      },
    );
  }
}
