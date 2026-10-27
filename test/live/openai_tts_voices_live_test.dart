// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The OpenAI TTS voice list against a REAL OpenAI-compatible server: the app
// reads the voices it publishes, then speaks with one of them. Skipped unless
// a server is named (CI has none):
//
//   OPENAI_TTS_LIVE_URL=http://host:8006/v1 OPENAI_TTS_LIVE_MODEL=omnivoice \
//     flutter test --tags live test/live/openai_tts_voices_live_test.dart
//
// OPENAI_TTS_LIVE_KEY is sent as the API key when set.

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/openai_tts_engine.dart';

void main() {
  final url = Platform.environment['OPENAI_TTS_LIVE_URL'] ?? '';
  final skip = url.isEmpty ? 'set OPENAI_TTS_LIVE_URL to run' : false;

  // `flutter test` answers every HTTP call itself unless this is cleared.
  setUpAll(() => HttpOverrides.global = null);

  test(
    'a real server lists its voices, and the first one speaks',
    () async {
      final engine = OpenAiTtsEngine(
        baseUrl: url,
        apiKey: Platform.environment['OPENAI_TTS_LIVE_KEY'] ?? 'live-test',
        model: Platform.environment['OPENAI_TTS_LIVE_MODEL'] ?? 'tts-1',
      );

      final voices = await engine.fetchVoices();

      expect(voices, isNotNull, reason: '$url published no voice list');
      expect(voices, isNotEmpty);
      expect(engine.availableVoices.map((v) => v.id), voices!.map((v) => v.id));

      final audio = await engine.generateAudio('Testing.', voices.first.id, 1);
      addTearDown(() => audio?.deleteSync());
      expect(audio, isNotNull, reason: '${voices.first.id} did not speak');
      expect(audio!.lengthSync(), greaterThan(1000));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
