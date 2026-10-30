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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Covers the whole app while a library Get or Undo replaces the files, and
/// after a swap that needs a restart to finish. Nothing may be edited while
/// the database is closed; a Get started from the phone web app shows it too.
class LibrarySyncOverlay extends StatelessWidget {
  const LibrarySyncOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<LibrarySyncService>();
    final stuck = sync.needsRestart;
    if (!sync.replacing && !sync.closingSend && stuck == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(
            dismissible: false,
            color: AppColors.backgroundOf(context).withValues(alpha: 0.85),
          ),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stuck == null)
                    CircularProgressIndicator(
                      color: AppColors.porchAmberOf(context),
                    )
                  else
                    Icon(
                      Icons.restart_alt_rounded,
                      size: 36,
                      color: StatusColors.warningOf(context),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    stuck ??
                        (sync.closingSend
                            ? 'Sending your library before closing…'
                            : 'Replacing this device\'s library…'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
