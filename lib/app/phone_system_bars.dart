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

/// The system bars as the app's own theme wants them: transparent, with
/// icons that read on the app's background.
SystemUiOverlayStyle systemBarsFor(Brightness appBrightness) {
  final base = appBrightness == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
  return base.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    // SystemUiOverlayStyle.dark keeps light navigation icons for its black
    // bar; over a transparent bar they follow the status bar's.
    systemNavigationBarIconBrightness: base.statusBarIconBrightness,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Wraps every route on a phone. The app draws edge to edge behind the
/// status and navigation bars (screens take their insets from their app
/// bars and SafeAreas), and the bars' icons follow the app's theme rather
/// than the OS setting, since the app picks its own light or dark.
class PhoneSystemBars extends StatefulWidget {
  const PhoneSystemBars({super.key, required this.child});

  final Widget child;

  @override
  State<PhoneSystemBars> createState() => _PhoneSystemBarsState();
}

class _PhoneSystemBarsState extends State<PhoneSystemBars> {
  @override
  void initState() {
    super.initState();
    // Android 15+ is edge to edge already; this makes 11–14 match.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).catchError(
      (Object e) => debugPrint('[SystemBars] edge-to-edge refused: $e'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemBarsFor(Theme.of(context).brightness),
      child: widget.child,
    );
  }
}
