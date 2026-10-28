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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/mobile/chats/chats_tab.dart';
import 'package:front_porch_ai/ui/mobile/library/phone_library_tab.dart';
import 'package:front_porch_ai/ui/mobile/more/more_tab.dart';
import 'package:front_porch_ai/ui/mobile/shell/destination_actions.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The first screen of each tab, keyed by [AppDestination.id].
/// test/hygiene/destination_registry_test.dart checks every tab has one.
final Map<String, WidgetBuilder> phoneTabRoots = {
  kChatsDestination: (_) => const ChatsTab(),
  kCharactersDestination: (_) => const PhoneLibraryTab(),
  kStoopDestination: (_) => const RepositoryPage(),
  // The view brings its own header (title, count, New); it only needs to
  // keep clear of the status bar.
  kStoriesDestination: (_) =>
      const Scaffold(body: SafeArea(bottom: false, child: StoryHomeView())),
  kMoreDestination: (_) => const MoreTab(),
};

/// What a tab does when the system back reaches it, or when its tab is
/// tapped again. True from [onBack]: the tab handled it (left selection,
/// went up a folder, closed search), so the shell does nothing more.
class PhoneTabHooks {
  final Map<String, bool Function()> _back = {};
  final Map<String, VoidCallback> _reselect = {};

  void register(
    String tab, {
    bool Function()? onBack,
    VoidCallback? onReselect,
  }) {
    if (onBack != null) _back[tab] = onBack;
    if (onReselect != null) _reselect[tab] = onReselect;
  }

  void unregister(String tab) {
    _back.remove(tab);
    _reselect.remove(tab);
  }

  bool back(String tab) => _back[tab]?.call() ?? false;

  void reselect(String tab) => _reselect[tab]?.call();
}

/// Which tab the phone shell is showing, for a tab that refreshes when it
/// comes back into view (Chats re-reads its list), and the hooks a tab
/// registers for back and re-tap.
class PhoneTabScope extends InheritedWidget {
  const PhoneTabScope({
    super.key,
    required this.selected,
    required this.hooks,
    required super.child,
  });

  final String selected;
  final PhoneTabHooks hooks;

  static String? selectedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhoneTabScope>()?.selected;

  static PhoneTabHooks? hooksOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PhoneTabScope>()?.hooks;

  @override
  bool updateShouldNotify(PhoneTabScope oldWidget) =>
      oldWidget.selected != selected;
}

/// The phone's shell: five tabs in a bottom bar (a rail when the screen is
/// wide or the phone is on its side). Tabs keep their state across
/// switches; anything a tab opens pushes on the app's one navigator and
/// covers the bar, so dialogs and pages written for the desktop's single
/// navigator behave the same here.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> implements ShellIntents {
  static final List<AppDestination> _tabs = destinationsPlaced(
    PhonePlacement.tab,
  ).toList();

  final PhoneTabHooks _hooks = PhoneTabHooks();

  /// Chats is where the app opens.
  int _index = 0;

  /// Tabs are built on first visit, then kept, so each keeps its scroll
  /// position and depth across switches.
  final Set<int> _visited = {0};

  AppState? _appState;

  @override
  void initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false)
      ..shellIntents = this;
    EngineHealth.instance.onFirstFailure = _onEngineFailure;
  }

  @override
  void dispose() {
    if (identical(_appState?.shellIntents, this)) {
      _appState?.shellIntents = null;
    }
    if (EngineHealth.instance.onFirstFailure == _onEngineFailure) {
      EngineHealth.instance.onFirstFailure = null;
    }
    super.dispose();
  }

  void _onEngineFailure(String engine, String reason) =>
      showEngineFailureNotice(context, engine, isMounted: () => mounted);

  int _indexOf(String id) => _tabs.indexWhere((t) => t.id == id);

  String get _current => _tabs[_index].id;

  @override
  bool get isShowingLibrary => _current == kCharactersDestination;

  @override
  void showLibrary() => _show(_indexOf(kCharactersDestination));

  @override
  void showCreateCharacter() =>
      phoneDestinationActions['create_character']?.call(context);

  void _show(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  Future<void> _onSelect(int index) async {
    if (index == _index) {
      // Re-tapping the open tab takes it back to its start (the library's
      // top level, the top of the list).
      _hooks.reselect(_current);
      return;
    }
    // A tab switch keeps the state it leaves, but a page asking about
    // unsaved edits is asked first, as the desktop sidebar does.
    if (!await UnsavedChanges.instance.confirmLeave(context)) return;
    if (mounted) _show(index);
  }

  /// Back reaches the shell only when nothing is pushed over it. The open
  /// tab gets it first, then back returns to Chats, then leaves the app.
  Future<void> _onBack() async {
    if (_hooks.back(_current)) return;
    if (_index != 0) {
      _show(0);
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = PhoneTabScope(
      selected: _current,
      hooks: _hooks,
      child: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _visited.contains(i)
                ? Builder(builder: phoneTabRoots[_tabs[i].id]!)
                : const SizedBox.shrink(),
        ],
      ),
    );
    final rail =
        formFactorOf(context) != FormFactor.phone ||
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        // The tabs keep one keyed place whichever navigation shows, so
        // turning the phone (bar <-> rail) keeps every tab's state.
        body: Row(
          children: [
            if (rail) SafeArea(right: false, child: _rail(context)),
            Expanded(key: const ValueKey('phone-tabs'), child: body),
          ],
        ),
        bottomNavigationBar: rail ? null : _bar(context),
      ),
    );
  }

  /// The selected icon takes the tab's own colour: the Stoop keeps its teal
  /// from the desktop sidebar, every other tab the porch amber.
  Color _selectedColor(BuildContext context, AppDestination tab) =>
      tab.id == kStoopDestination
      ? NavColors.stoopOf(context)
      : AppColors.porchAmberOf(context);

  Widget _bar(BuildContext context) {
    return NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: _onSelect,
      backgroundColor: AppColors.surfaceOf(context),
      indicatorColor: AppColors.navigationSelectionOf(context),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final t in _tabs)
          NavigationDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.icon, color: _selectedColor(context, t)),
            label: t.label,
          ),
      ],
    );
  }

  Widget _rail(BuildContext context) {
    return NavigationRail(
      selectedIndex: _index,
      onDestinationSelected: _onSelect,
      backgroundColor: AppColors.surfaceOf(context),
      indicatorColor: AppColors.navigationSelectionOf(context),
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final t in _tabs)
          NavigationRailDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.icon, color: _selectedColor(context, t)),
            label: Text(t.label),
          ),
      ],
    );
  }
}
