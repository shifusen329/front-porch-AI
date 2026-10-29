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

import 'package:front_porch_ai/services/services.dart';

/// Narrate All for the phone web app: the open chat's lines with the voice
/// the desktop reads each in. The browser fetches each line's audio from
/// `/api/tts/speak` and plays it there.
class ChatNarrationFacade {
  ChatNarrationFacade(this._chat);

  final ChatService _chat;

  /// The lines from `#[from]` to the end; none when the chat changed while
  /// its older messages were still loading.
  Future<Map<String, dynamic>> script({int from = 1}) async {
    final lines = await _chat.narrationScript(from: from) ?? const [];
    return {
      'lines': [
        for (final l in lines)
          {
            'number': l.number,
            'speaker': l.speaker,
            'text': l.text,
            'voiceKey': l.voiceKey,
          },
      ],
    };
  }
}
