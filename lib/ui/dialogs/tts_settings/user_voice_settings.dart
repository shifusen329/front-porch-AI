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

import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Whether the user's own messages are read as they send them, and the
/// voices for the user and for Narrator and Director lines. Sits under
/// Auto-Play; the phone web app's Voice & Media has the same three.
class UserVoiceSettings extends StatelessWidget {
  const UserVoiceSettings({super.key, required this.settings});

  final TtsSettings settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const Key('tts-speak-my-messages'),
          title: Text(
            'Speak my messages',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          subtitle: Text(
            'Read your own messages aloud as you send them, in your voice',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          value: settings.ttsAutoPlayUser,
          activeTrackColor: AppColors.formAccentOf(context),
          contentPadding: EdgeInsets.zero,
          onChanged: settings.setTtsAutoPlayUser,
        ),
        const SizedBox(height: 8),
        _label(context, 'Your voice', 'Your messages are read in this voice.'),
        CharacterVoicePicker(
          key: const Key('tts-user-voice'),
          value: settings.ttsUserVoice,
          onChanged: settings.setTtsUserVoice,
        ),
        const SizedBox(height: 12),
        _label(
          context,
          'Narrator voice',
          'Narrator and Director lines (/narrate, time skips) are read in '
              'this voice.',
        ),
        CharacterVoicePicker(
          key: const Key('tts-narrator-voice'),
          value: settings.ttsNarratorVoice,
          onChanged: settings.setTtsNarratorVoice,
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.textPrimary(context))),
          Text(
            hint,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
