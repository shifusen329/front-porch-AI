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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// One chat's visual-novel choice: follow Settings → Appearance (null), or
/// on or off for this chat alone.
class VisualNovelChoice extends StatelessWidget {
  const VisualNovelChoice({
    super.key,
    required this.value,
    required this.appearanceOn,
    required this.onChanged,
  });

  final bool? value;

  /// What Settings → Appearance says, for the "follow" choice's hint.
  final bool appearanceOn;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textTertiary(context);
    return Column(
      key: const ValueKey('chat-visual-novel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visual Novel',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.formAccentOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'The characters on stage, with the chat in a panel over them. '
          '${appearanceOn ? 'On' : 'Off'} in Settings → Appearance.',
          style: TextStyle(fontSize: 12, height: 1.4, color: muted),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('As Settings')),
            ButtonSegment(value: 1, label: Text('On')),
            ButtonSegment(value: 2, label: Text('Off')),
          ],
          selected: {
            switch (value) {
              null => 0,
              true => 1,
              false => 2,
            },
          },
          onSelectionChanged: (s) => onChanged(switch (s.first) {
            1 => true,
            2 => false,
            _ => null,
          }),
        ),
      ],
    );
  }
}
