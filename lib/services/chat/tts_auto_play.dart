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

// Text-to-speech auto-play: the user's own line as it is sent, and a line
// the model finishes. A voice call speaks its replies as they stream, so
// neither runs during one.

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/storage/settings/tts_settings.dart';
import 'package:front_porch_ai/services/tts_service.dart';

import 'director/director_note.dart';
import 'message_voice.dart';

/// The user has sent [line] (at [index]): any narration ends, since they
/// have moved on, and with Speak my messages on the line is read in their
/// voice, cutting off an older reply still being read.
void autoPlaySentLine(
  TtsService? tts,
  TtsSettings settings, {
  required ChatMessage line,
  required int index,
  required MessageVoice voice,
  required bool inCall,
}) {
  if (tts == null) return;
  tts.narration.cancel();
  if (!settings.ttsEnabled ||
      !settings.ttsAutoPlayUser ||
      inCall ||
      !voice.speak) {
    return;
  }
  unawaited(
    tts.speak(
      line.displayText,
      voiceKey: voice.voiceKey,
      messageId: 'msg_$index',
    ),
  );
}

/// The model has finished [line] (at [index]). A reply or a narrator's beat
/// follows Auto-Play; a line written for the user (impersonation, a
/// Director user turn) follows Speak my messages. It waits for the line
/// before it, so a reply never cuts off the user's own.
void autoPlayFinishedLine(
  TtsService? tts,
  TtsSettings settings, {
  required ChatMessage line,
  required int index,
  required MessageVoice voice,
  required bool inCall,
}) {
  if (tts == null || !settings.ttsEnabled || inCall || !voice.speak) return;
  final usersOwn = line.isUser && line.characterId != kDirectorCharacterId;
  if (!(usersOwn ? settings.ttsAutoPlayUser : settings.ttsAutoPlay)) return;
  unawaited(
    tts.speakAfterCurrent(
      line.displayText,
      voiceKey: voice.voiceKey,
      messageId: 'msg_$index',
    ),
  );
}
