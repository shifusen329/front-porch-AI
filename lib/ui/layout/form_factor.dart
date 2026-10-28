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

/// Same numbers as web_ui/src/hooks/useBreakpoint.ts (TABLET_MIN /
/// DESKTOP_MIN), so the phone web app and the app change layout at the same
/// widths. test/hygiene/breakpoint_parity_test.dart holds them together.
const double kTabletMinWidth = 768;
const double kDesktopMinWidth = 1024;

/// A handset in landscape is still a handset (Material 3's compact height).
const double kHandsetMaxShortestSide = 600;

enum FormFactor { phone, tablet, desktop }

/// Which layout a screen of [size] gets inside the phone shell. Which shell
/// runs at all is [PlatformCaps.usesMobileShell]'s question, not this one.
FormFactor formFactorFor(Size size) {
  if (size.shortestSide < kHandsetMaxShortestSide &&
      size.width < kDesktopMinWidth) {
    return FormFactor.phone; // portrait and landscape phones
  }
  if (size.width >= kDesktopMinWidth) return FormFactor.desktop;
  return size.width >= kTabletMinWidth ? FormFactor.tablet : FormFactor.phone;
}

FormFactor formFactorOf(BuildContext context) =>
    formFactorFor(MediaQuery.sizeOf(context));
