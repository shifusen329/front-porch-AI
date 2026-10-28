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

import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/mobile/mobile.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The app's top-level screen: the desktop sidebar layout, or the phone
/// shell. A narrow desktop window stays on the desktop layout.
class ShellSwitch extends StatelessWidget {
  const ShellSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformCaps.current.usesMobileShell
        ? const MobileShell()
        : const MainLayout();
  }
}
