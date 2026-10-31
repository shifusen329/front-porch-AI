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
import 'package:front_porch_ai/ui/mobile/porch/porch_tab.dart';
import 'package:front_porch_ai/ui/mobile/shell/destination_actions.dart';
import 'package:front_porch_ai/ui/mobile/shell/phone_tab_scope.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The first screen of each tab, keyed by [AppDestination.id].
/// test/hygiene/destination_registry_test.dart checks every tab has one.
final Map<String, WidgetBuilder> phoneTabRoots = {
  kChatsDestination: (_) => const ChatsTab(),
  kPorchDestination: (_) => const PorchTab(),
  // Not pushed, so it shows no back arrow; its own app bar clears the
  // status bar.
  kSettingsDestination: (_) => const SettingsPage(),
};

/// The phone's shell: Chats, Porch and Settings tabs in a bottom bar (a rail
/// when the screen is wide or the phone is on its side), with an Images
/// button that opens Image Studio over them. Tabs keep their state across
/// switches; anything a tab opens pushes on the app's one navigator and
/// covers the bar, so dialogs and pages written for the desktop's single
/// navigator behave the same here.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> implements ShellIntents {
  /// What the bar shows: the tabs, and buttons that open a page over them.
  static final List<AppDestination> _items = phoneBarItems.toList();
  static final List<AppDestination> _tabs = destinationsPlaced(
    PhonePlacement.tab,
  ).toList();

  final PhoneTabHooks _hooks = PhoneTabHooks();
  final ValueNotifier<String> _porchView = ValueNotifier(
    kCharactersDestination,
  );

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
    _porchView.dispose();
    super.dispose();
  }

  void _onEngineFailure(String engine, String reason) =>
      showEngineFailureNotice(context, engine, isMounted: () => mounted);

  int _indexOf(String id) => _tabs.indexWhere((t) => t.id == id);

  String get _current => _tabs[_index].id;

  @override
  bool get isShowingLibrary =>
      _current == kPorchDestination &&
      _porchView.value == kCharactersDestination;

  @override
  void showLibrary() {
    _porchView.value = kCharactersDestination;
    _show(_indexOf(kPorchDestination));
  }

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

  /// A bar button opens its page over the tabs and leaves the selection
  /// where it was; a tab is switched to.
  Future<void> _onBarSelect(int position) async {
    final item = _items[position];
    if (item.phone == PhonePlacement.barButton) {
      await phoneDestinationActions[item.id]?.call(context);
      return;
    }
    await _onSelect(_indexOf(item.id));
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
    if (!back()) await SystemNavigator.pop();
  }

  @override
  bool back() {
    if (_hooks.back(_current)) return true;
    if (_index == 0) return false;
    _show(0);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final body = PhoneTabScope(
      selected: _current,
      hooks: _hooks,
      porchView: _porchView,
      child: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            // A tab out of view keeps its state but not its animations.
            TickerMode(
              enabled: i == _index,
              child: _visited.contains(i)
                  ? Builder(builder: phoneTabRoots[_tabs[i].id]!)
                  : const SizedBox.shrink(),
            ),
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

  int get _barPosition => _items.indexWhere((d) => d.id == _current);

  Widget _bar(BuildContext context) {
    return NavigationBar(
      selectedIndex: _barPosition,
      onDestinationSelected: _onBarSelect,
      backgroundColor: AppColors.surfaceOf(context),
      indicatorColor: AppColors.navigationSelectionOf(context),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final t in _items)
          NavigationDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.icon, color: AppColors.porchAmberOf(context)),
            label: t.label,
          ),
      ],
    );
  }

  Widget _rail(BuildContext context) {
    return NavigationRail(
      selectedIndex: _barPosition,
      onDestinationSelected: _onBarSelect,
      backgroundColor: AppColors.surfaceOf(context),
      indicatorColor: AppColors.navigationSelectionOf(context),
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final t in _items)
          NavigationRailDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.icon, color: AppColors.porchAmberOf(context)),
            label: Text(t.label),
          ),
      ],
    );
  }
}
