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
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Pre-release builds surface the first unexpected engine failure of the
/// session as a report-it notice: a quietly-broken engine is otherwise
/// indistinguishable from a working one (sidecar retirement playbook), and
/// users only report what visibly breaks. Each shell wires this into
/// [EngineHealth.onFirstFailure] while it is mounted.
void showEngineFailureNotice(
  BuildContext context,
  String engine, {
  required bool Function() isMounted,
}) {
  if (!isPreRelease || !isMounted()) return;
  // Engines report from service code that may be mid-frame; defer so the
  // snackbar never fires during a build.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isMounted()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.porchAmberOf(context),
        duration: const Duration(seconds: 10),
        // Without persist:false, action snackbars never auto-dismiss.
        persist: false,
        content: Text(
          '⚠️ $engine hit an engine error — please report this on Discord.',
          style: TextStyle(color: AppColors.onAccentOf(context)),
        ),
        action: SnackBarAction(
          label: 'Copy details',
          textColor: AppColors.onAccentOf(context),
          onPressed: () => Clipboard.setData(
            ClipboardData(text: EngineHealth.instance.buildReport()),
          ),
        ),
      ),
    );
  });
}
