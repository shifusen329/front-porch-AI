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

// Who reads a chat message aloud, and whether it is read at all. One answer
// for the Speak button, auto-play, Narrate All and the phone web app, so a
// line never changes voice depending on how it was asked for.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage/settings/tts_settings.dart';

import 'director/director_note.dart';
import 'group_speaker_resolution.dart';

class MessageVoice {
  const MessageVoice._(this.speak, this.voiceKey);

  static const silent = MessageVoice._(false, null);

  /// False for lines that are not story: System notices, status banners and
  /// messages with no text (a photo on its own).
  final bool speak;

  /// The voice to read it in; null is the global voice.
  final String? voiceKey;
}

/// Narrator and Director lines take the narrator voice, the user's own
/// messages the user's voice, a group member their own voice (matched by the
/// speaker the message was stamped with) and a 1:1 reply the character's.
/// Any of them unset falls back to the global voice.
MessageVoice voiceFor(
  ChatMessage m, {
  required TtsSettings tts,
  CharacterCard? activeCharacter,
  List<CharacterCard> groupCharacters = const [],
  bool isGroup = false,
}) {
  if (m.isStatusBanner ||
      m.sender == 'System' ||
      m.displayText.trim().isEmpty) {
    return MessageVoice.silent;
  }
  String? orGlobal(String? voice) =>
      (voice == null || voice.isEmpty) ? null : voice;
  if (m.characterId == kDirectorCharacterId) {
    return MessageVoice._(true, orGlobal(tts.ttsNarratorVoice));
  }
  if (m.isUser) return MessageVoice._(true, orGlobal(tts.ttsUserVoice));
  final speaker = isGroup
      ? resolveGroupSpeakerForMessage(groupCharacters, m, logOnMiss: false)
      : activeCharacter;
  return MessageVoice._(true, orGlobal(speaker?.ttsVoice));
}

extension ChatMessageVoice on ChatService {
  /// [voiceFor] with this chat's cast.
  MessageVoice voiceOf(ChatMessage m, TtsSettings tts) => voiceFor(
    m,
    tts: tts,
    activeCharacter: activeCharacter,
    groupCharacters: groupCharacters,
    isGroup: isGroupMode,
  );
}
