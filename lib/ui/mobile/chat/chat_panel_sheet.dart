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

import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Width the panel's character portrait is drawn at in the sheet: the
/// desktop draws it as wide as the sidebar, which on a phone would be the
/// whole screen.
const double kPanelSheetPortraitSize = 160;

/// Opens the chat's side panel over the chat as a sheet, as a phone shows
/// it, instead of beside the transcript. [builder] gets the sheet's context
/// and a way to close it (a Journal receipt that jumps to a message closes
/// the sheet first). The panel itself is the desktop's, unchanged.
Future<void> showChatPanelSheet(
  BuildContext context, {
  required Widget Function(BuildContext sheet, VoidCallback close) builder,
}) {
  return showWarmSheet<void>(
    context,
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * 0.85,
      child: builder(sheet, () => Navigator.of(sheet).pop()),
    ),
  );
}
