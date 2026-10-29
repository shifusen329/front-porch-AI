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

import 'dart:async';

import 'package:flutter/foundation.dart';

/// One line Narrate All reads.
class NarrationLine {
  const NarrationLine({
    required this.index,
    required this.number,
    required this.speaker,
    required this.text,
    this.voiceKey,
  });

  /// Its place in the loaded chat; the bubble's Speak button follows it as
  /// `msg_$index`, so the line being read shows its stop button.
  final int index;

  /// The `#N` shown under the message's avatar.
  final int number;
  final String speaker;
  final String text;

  /// Null is the global voice.
  final String? voiceKey;
}

/// Reads a chat's lines aloud one after another, each in its own voice
/// (Narrate All). One per app, owned by the TTS service, since there is one
/// speaker. Any other speech, Stop, sending a message or leaving the chat
/// ends it.
class TtsNarration extends ChangeNotifier {
  TtsNarration({
    required Future<void> Function(
      String text, {
      String? voiceKey,
      String? messageId,
    })
    speak,
    required Future<void> Function() silence,
    required bool Function() failed,
  }) : _speak = speak,
       _silence = silence,
       _failed = failed;

  final Future<void> Function(
    String text, {
    String? voiceKey,
    String? messageId,
  })
  _speak;
  final Future<void> Function() _silence;

  /// Whether the line just spoken failed (the engine's error is already on
  /// its way to the user); the narration stops there.
  final bool Function() _failed;

  /// Bumped by every start and cancel: a loop from an older run ends at its
  /// next check.
  int _run = 0;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  NarrationLine? _current;

  bool get isRunning => _running;

  /// Lines finished so far, of [total].
  int get done => _done;
  int get total => _total;

  /// The line being read now.
  NarrationLine? get current => _current;

  /// Reads [lines] in order. [stillCurrent] is asked before every line (the
  /// chat it was started in is still open); a narration already running is
  /// left alone, so a double tap starts one.
  Future<void> start(
    List<NarrationLine> lines, {
    bool Function()? stillCurrent,
  }) async {
    if (_running || lines.isEmpty) return;
    final run = ++_run;
    _running = true;
    _done = 0;
    _total = lines.length;
    _current = null;
    notifyListeners();
    try {
      for (final line in lines) {
        if (run != _run || !(stillCurrent?.call() ?? true)) break;
        _current = line;
        notifyListeners();
        await _speak(
          line.text,
          voiceKey: line.voiceKey,
          messageId: 'msg_${line.index}',
        );
        if (run != _run || _failed()) break;
        _done++;
        notifyListeners();
      }
    } finally {
      if (run == _run) {
        _running = false;
        _current = null;
        notifyListeners();
      }
    }
  }

  /// Ends the narration. With [silence] the line being read stops too;
  /// without it the caller is about to take the speaker itself.
  void cancel({bool silence = true}) {
    if (!_running) return;
    _run++;
    _running = false;
    _current = null;
    notifyListeners();
    if (silence) unawaited(_silence());
  }
}
