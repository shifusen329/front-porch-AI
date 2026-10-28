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

import 'package:flutter/widgets.dart';

/// What a tab (or a Porch sub-tab) does when the system back reaches it, or
/// when it is tapped again. True from [onBack]: it handled it (left
/// selection, went up a folder, closed a form), so the shell does nothing
/// more. Keyed by destination id, so tabs and sub-tabs never clash.
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
/// comes back into view (Chats re-reads its list), the hooks a tab
/// registers for back and re-tap, and which Porch sub-tab is open (so
/// "show the library" from anywhere lands on Characters).
class PhoneTabScope extends InheritedWidget {
  const PhoneTabScope({
    super.key,
    required this.selected,
    required this.hooks,
    required this.porchView,
    required super.child,
  });

  final String selected;
  final PhoneTabHooks hooks;
  final ValueNotifier<String> porchView;

  static String? selectedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhoneTabScope>()?.selected;

  static PhoneTabHooks? hooksOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PhoneTabScope>()?.hooks;

  static ValueNotifier<String>? porchViewOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PhoneTabScope>()?.porchView;

  @override
  bool updateShouldNotify(PhoneTabScope oldWidget) =>
      oldWidget.selected != selected;
}
