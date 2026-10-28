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

import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/mobile/library/phone_library_tab.dart';
import 'package:front_porch_ai/ui/mobile/shell/phone_tab_scope.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The first screen of each Porch sub-tab, keyed by [AppDestination.id].
/// test/hygiene/destination_registry_test.dart checks every sub-tab has one.
final Map<String, WidgetBuilder> porchViewRoots = {
  kCharactersDestination: (_) => const PhoneLibraryTab(),
  kPersonasDestination: (_) => const UserPersonaPage(embedded: true),
  kWorldsDestination: (_) => const WorldManagementPage(),
  // The view draws its own header (title, count, New).
  kStoriesDestination: (_) => const Scaffold(body: StoryHomeView()),
};

/// The phone's Porch tab: the main content (characters, the user's
/// personas, worlds and stories) under one row of sub-tabs. Sub-tabs keep
/// their place across switches like the shell's tabs do, except Personas,
/// which is built only while it is in view, so leaving an edit after
/// "Discard" really throws it away.
class PorchTab extends StatefulWidget {
  const PorchTab({super.key});

  @override
  State<PorchTab> createState() => _PorchTabState();
}

class _PorchTabState extends State<PorchTab>
    with SingleTickerProviderStateMixin {
  static final List<AppDestination> _views = destinationsPlaced(
    PhonePlacement.porch,
  ).toList();

  late final TabController _tabs = TabController(
    length: _views.length,
    vsync: this,
  );

  /// The shell's, so "show the library" from elsewhere lands on Characters;
  /// a Porch built outside the shell keeps its own.
  ValueNotifier<String>? _view;
  ValueNotifier<String>? _ownView;
  PhoneTabHooks? _hooks;
  final Set<String> _visited = {};

  String get _current => _view!.value;

  int _indexOf(String id) => _views.indexWhere((v) => v.id == id);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view =
        PhoneTabScope.porchViewOf(context) ??
        (_ownView ??= ValueNotifier(kCharactersDestination));
    if (!identical(view, _view)) {
      _view?.removeListener(_onViewChanged);
      _view = view..addListener(_onViewChanged);
      _sync();
    }
    _hooks = PhoneTabScope.hooksOf(context)
      ?..register(
        kPorchDestination,
        onBack: () => _hooks?.back(_current) ?? false,
        onReselect: () => _hooks?.reselect(_current),
      );
  }

  @override
  void dispose() {
    _hooks?.unregister(kPorchDestination);
    _view?.removeListener(_onViewChanged);
    _ownView?.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _sync() {
    final index = _indexOf(_current);
    if (_tabs.index != index) _tabs.index = index;
    _visited.add(_current);
  }

  void _onViewChanged() {
    if (!mounted) return;
    setState(_sync);
  }

  /// Tapping the open sub-tab takes it back to its start; another one is
  /// switched to once any unsaved edit has been answered for.
  Future<void> _onTap(int index) async {
    final to = _views[index].id;
    if (to == _current) {
      _hooks?.reselect(to);
      return;
    }
    if (UnsavedChanges.instance.hasUnsaved) {
      // Hold the old sub-tab until the question is answered.
      _tabs.index = _indexOf(_current);
      if (!await UnsavedChanges.instance.confirmLeave(context)) return;
      if (!mounted) return;
    }
    _view!.value = to;
  }

  @override
  Widget build(BuildContext context) {
    final inView =
        (PhoneTabScope.selectedOf(context) ?? kPorchDestination) ==
        kPorchDestination;
    final current = _current;
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _bar(context),
            Expanded(
              child: IndexedStack(
                index: _indexOf(current),
                children: [
                  for (final v in _views)
                    TickerMode(
                      enabled: inView && v.id == current,
                      child: _builds(v.id, current, inView)
                          ? Builder(builder: porchViewRoots[v.id]!)
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _builds(String id, String current, bool inView) =>
      id == kPersonasDestination
      ? inView && current == id
      : _visited.contains(id);

  Widget _bar(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: TabBar(
        key: const Key('porch-tabs'),
        controller: _tabs,
        onTap: _onTap,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppColors.textPrimary(context),
        unselectedLabelColor: AppColors.textSecondary(context),
        indicatorColor: AppColors.porchAmberOf(context),
        dividerColor: AppColors.borderOf(context).withValues(alpha: 0),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        tabs: [for (final v in _views) Tab(text: v.label)],
      ),
    );
  }
}
