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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/storage/settings/tts_settings.dart';
import 'package:front_porch_ai/services/tts_playback/tts_playback.dart';

import 'message_voice.dart';

/// The lines Narrate All reads, from `#[from]` (1 is the chat's first
/// message) to the end, each in the voice [voiceOf] gives it. A line the
/// narration filters leave silent (quoted-only on a line with no quotes) is
/// left out, so "12 of 80" counts only what is read. [base] is the loaded
/// window's first `#N` less one, as under the avatars.
List<NarrationLine> narrationLines(
  List<ChatMessage> messages, {
  required int base,
  required MessageVoice Function(ChatMessage) voiceOf,
  required TtsSettings tts,
  int from = 1,
}) {
  final lines = <NarrationLine>[];
  for (var i = 0; i < messages.length; i++) {
    final number = base + i + 1;
    if (number < from) continue;
    final m = messages[i];
    final voice = voiceOf(m);
    if (!voice.speak) continue;
    final spoken = sanitizeTtsText(
      m.displayText,
      replaceCurlyQuotes: tts.ttsReplaceCurlyQuotes,
      ignoreAsterisks: tts.ttsIgnoreAsterisks,
      narrateQuotedOnly: tts.ttsNarrateQuotedOnly,
    );
    if (spoken.trim().isEmpty) continue;
    lines.add(
      NarrationLine(
        index: i,
        number: number,
        speaker: m.sender,
        text: m.displayText,
        voiceKey: voice.voiceKey,
      ),
    );
  }
  return lines;
}
