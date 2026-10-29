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
import 'package:front_porch_ai/services/tts_playback/tts_playback.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// "Narrating 12 of 80 · #34 Riley": the line being read, counted from 1.
String narrationProgressLabel(TtsNarration n) {
  final at = (n.done + 1).clamp(1, n.total);
  final line = n.current;
  return 'Narrating $at of ${n.total}'
      '${line == null ? '' : ' · #${line.number} ${line.speaker}'}';
}

/// The strip above the message box while Narrate All runs, so it can be
/// stopped with the side panel (or the phone's sheet) closed. Nothing when
/// text-to-speech is off.
class NarrationStatusBar extends StatelessWidget {
  const NarrationStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    if (!storage.ttsSettings.ttsEnabled) return const SizedBox.shrink();
    final narration = Provider.of<TtsService>(context, listen: false).narration;
    return ListenableBuilder(
      listenable: narration,
      builder: (context, _) {
        if (!narration.isRunning) return const SizedBox.shrink();
        return Material(
          key: const Key('narration-status'),
          color: AppColors.surfaceOf(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  size: 16,
                  color: AppColors.porchAmberOf(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    narrationProgressLabel(narration),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: narration.cancel,
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
