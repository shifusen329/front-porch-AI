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

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// What the host can do that a desktop build takes for granted. A phone
/// (Android) runs the app as a REST client: no window manager, no child
/// processes, no KoboldCpp, no web server for the PWA, and `localhost` is
/// the phone itself, so the loopback presets (LM Studio, oMLX) mean nothing.
///
/// Ask [current] instead of `Platform.isX` when the question is one of
/// these, so a new platform lands on a deliberate answer rather than
/// falling into a desktop `else`.
class PlatformCaps {
  const PlatformCaps({required this.isDesktop});

  PlatformCaps.host()
    : isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  final bool isDesktop;

  /// The live answer. A test may set it and must put it back.
  @visibleForTesting
  static PlatformCaps debugOverride = PlatformCaps.host();

  static PlatformCaps get current => debugOverride;

  /// `window_manager` and `screen_retriever` have a plugin here.
  bool get hasWindowManager => isDesktop;

  /// `Process.start` of a binary the app downloaded is allowed. Android 10+
  /// refuses to execute files from app storage.
  bool get canSpawnProcesses => isDesktop;

  /// The app can download and run KoboldCpp itself.
  bool get canRunLocalEngine => isDesktop;

  /// The built-in server can find and serve the PWA bundle.
  bool get canHostWebServer => isDesktop;

  /// `localhost` is a computer the user runs model servers on.
  bool get hasLoopbackPresets => isDesktop;

  /// The phone shell (bottom navigation, sheets) instead of the desktop
  /// sidebar. Layout inside it follows the screen's form factor.
  bool get usesMobileShell => !isDesktop;

  /// `getDirectoryPath` returns a folder `dart:io` can walk. Android's
  /// picker hands back a content tree instead.
  bool get canPickDirectories => isDesktop;
}
