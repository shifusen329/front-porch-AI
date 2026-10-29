// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/services/tts_playback/tts_playback.dart';

import '../golden/support/fakes_services.dart';
import '../golden/support/fakes_storage.dart';
import 'speech_server.dart';

/// Voices the rig's speech server has: the global voice, the user's, a
/// character's and the narrator's.
const kRigGlobalVoice = 'aisha';
const kRigUserVoice = 'me';
const kRigCharacterVoice = 'riley';
const kRigNarratorVoice = 'teller';

/// audioplayers has no platform here; its calls answer null.
void mockAudioChannels() {
  for (final name in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }
}

/// The audio device. Ungated, every line ends at once; gated, a line plays
/// until [finishLine] or Stop, as a real clip does. Implements rather than
/// extends, so no audioplayers player (and its platform stream) is made.
class TestPlayer implements TtsWavPlayer {
  TestPlayer({this.gated = false});

  final bool gated;
  int played = 0;
  Completer<void>? _line;

  bool get playing => _line != null;

  @override
  Future<void> play(File wavFile) async {
    played++;
    if (!gated) return;
    final line = _line = Completer<void>();
    await line.future;
  }

  void finishLine() {
    final line = _line;
    _line = null;
    line?.complete();
  }

  @override
  Future<void> stop() async => finishLine();

  @override
  void dispose() => finishLine();
}

/// A real TtsService on the OpenAI-compatible engine, pointed at a real
/// loopback [SpeechServer], with text-to-speech on and the user's and
/// narrator's voices set. Only the audio device is [TestPlayer].
class TtsTestRig {
  TtsTestRig._(this.server, this.storage, this.tts, this.player);

  final SpeechServer server;
  final FakeStorageService storage;
  final TtsService tts;
  final TestPlayer player;

  TtsSettings get settings => storage.ttsSettings;

  /// The voice each request to the server asked for, in order.
  List<String?> get voicesAsked => [
    for (final r in server.requests) r.body['voice'] as String?,
  ];

  static Future<TtsTestRig> start({bool gated = false}) async {
    final server = await SpeechServer.start(
      voices: {
        kRigGlobalVoice,
        kRigUserVoice,
        kRigCharacterVoice,
        kRigNarratorVoice,
        'sam',
      },
    );
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    final s = storage.ttsSettings;
    await s.setTtsEnabled(true);
    await s.setTtsEngine('openai');
    await s.setOpenaiTtsBaseUrl(server.baseUrl);
    await s.setOpenaiTtsModel(SpeechServer.model);
    await s.setTtsConcurrency(1);
    await s.setTtsVoiceModel(kRigGlobalVoice);
    await s.setTtsUserVoice(kRigUserVoice);
    await s.setTtsNarratorVoice(kRigNarratorVoice);
    final player = TestPlayer(gated: gated);
    final tts = TtsService(storage, FakeVoiceManager(), player: player);
    addTearDown(tts.dispose);
    return TtsTestRig._(server, storage, tts, player);
  }
}

/// In a widget test, work started from a tap runs in the test's fake time
/// while the speech server answers in real time: alternate the two until
/// [done].
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() done,
  String what,
) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (!done()) fail('timed out waiting for $what');
}

/// Polls [done] on real time.
Future<void> untilTrue(bool Function() done, String what) async {
  final until = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(until)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
