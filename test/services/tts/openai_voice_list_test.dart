// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The OpenAI TTS voice list. OpenAI's own address offers its documented
// voices; any other OpenAI-compatible server offers only the voices it
// publishes at `{base}/audio/voices`, read by itself at startup and when the
// address changes, saved for the next launch, and re-read on Refresh (desktop)
// or Refresh voices (web, through /api/voice/list-voices).
//
// Every request goes over real HTTP to a loopback server answering with the
// body shape a real server sent (test/fixtures/tts/). The same reads against
// a real server: test/live/openai_tts_voices_live_test.dart.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/openai_tts_engine.dart';
import 'package:front_porch_ai/services/tts/openai_voice_list.dart';
import 'package:front_porch_ai/services/web/facade/voice_facade.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/speech_server.dart';
import '../../helpers/tts_voice_server.dart';

const _listPath = '/v1/audio/voices';
const _dataList = 'test/fixtures/tts/voices_data_list.json';
const _bareNames = 'test/fixtures/tts/voices_bare_names.json';

/// TtsService's audio player calls its platform channels as it is built.
void _mockAudioChannels() {
  for (final name in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }
}

FakeStorageService _openAiAt(String baseUrl) {
  final storage = FakeStorageService();
  storage.ttsSettings
    ..setTtsEngine('openai')
    ..setOpenaiTtsApiKey('sk-test')
    ..setOpenaiTtsBaseUrl(baseUrl);
  addTearDown(storage.dispose);
  return storage;
}

TtsService _ttsOn(FakeStorageService storage) {
  final tts = TtsService(storage, FakeVoiceManager());
  addTearDown(tts.dispose);
  return tts;
}

List<String> _ids(TtsService tts) => [for (final v in tts.activeVoices) v.id];

Future<void> _waitFor(bool Function() done, String what) async {
  final until = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(until)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_mockAudioChannels);

  test('a custom server fills the voice list by itself, and the list is '
      'there at the next launch before the server is asked again', () async {
    final server = await TtsVoiceServer.start();
    server.serveFile(_listPath, _dataList);
    final storage = _openAiAt(server.baseUrl);

    final tts = _ttsOn(storage);
    await _waitFor(() => _ids(tts).isNotEmpty, 'the server voices');

    expect(_ids(tts), ['willa', 'orrin', 'design', 'auto']);
    expect(tts.activeVoices.first.name, 'Willa');
    expect(tts.activeVoices.first.gender, '', reason: 'the server sent none');
    expect(server.hits(_listPath), 1);
    expect(server.requests.single.authorization, 'Bearer sk-test');

    final relaunched = _ttsOn(storage);
    expect(_ids(relaunched), [
      'willa',
      'orrin',
      'design',
      'auto',
    ], reason: 'the saved list must show before any request');
    expect(server.hits(_listPath), 1);
  });

  test('OpenAI\'s own address keeps the documented voices; another address '
      'offers only its own', () async {
    final server = await TtsVoiceServer.start();
    server.serveFile(_listPath, _dataList);
    final storage = _openAiAt(kOpenAiTtsBaseUrl);
    final tts = _ttsOn(storage);

    expect(_ids(tts), contains('coral'));
    expect(tts.activeVoices, hasLength(10));
    expect(await tts.listEndpointVoices(), isNull);

    await storage.ttsSettings.setOpenaiTtsBaseUrl(server.baseUrl);
    await _waitFor(() => _ids(tts).contains('willa'), 'the server voices');
    expect(_ids(tts), isNot(contains('coral')));

    await storage.ttsSettings.setOpenaiTtsBaseUrl(kOpenAiTtsBaseUrl);
    await _waitFor(() => _ids(tts).contains('coral'), 'OpenAI voices back');
    expect(server.hits(_listPath), 1);
  });

  test(
    'a server that lists nothing offers no OpenAI names in their place',
    () async {
      final server = await TtsVoiceServer.start();
      final storage = _openAiAt(server.baseUrl);
      final tts = _ttsOn(storage);

      await _waitFor(() => server.hits(_listPath) == 1, 'the list request');
      expect(await tts.listEndpointVoices(), isNull);

      expect(tts.activeVoices, isEmpty);
      expect(storage.ttsSettings.openaiTtsVoiceList, '');
    },
  );

  test('a list of bare names becomes voices named by their ids', () async {
    final server = await TtsVoiceServer.start();
    server.serveFile(_listPath, _bareNames);
    final tts = _ttsOn(_openAiAt('${server.baseUrl}/'));

    await _waitFor(() => _ids(tts).isNotEmpty, 'the server voices');

    expect(_ids(tts), ['af_bella', 'am_adam']);
    expect([for (final v in tts.activeVoices) v.name], ['af_bella', 'am_adam']);
  });

  test('two reads at once ask the server once', () async {
    final server = await TtsVoiceServer.start();
    server.serveFile(_listPath, _dataList);
    final tts = _ttsOn(_openAiAt(server.baseUrl));
    await _waitFor(() => _ids(tts).isNotEmpty, 'the first read');

    final both = await Future.wait([
      tts.listEndpointVoices(),
      tts.listEndpointVoices(),
    ]);

    expect(both.map((v) => v?.length), [4, 4]);
    expect(server.hits(_listPath), 2);
  });

  test('the web relay re-reads the list and says how many came back', () async {
    final server = await TtsVoiceServer.start();
    final storage = _openAiAt(server.baseUrl);
    final tts = _ttsOn(storage);
    await _waitFor(() => server.hits(_listPath) == 1, 'the first read');
    final router = Router();
    WebVoiceRoutes(VoiceFacade(tts, FakeSttService(), storage), router);

    Future<Map<String, dynamic>> call(String method, String path) async {
      final response = await router.call(
        shelf.Request(method, Uri.parse('http://localhost$path')),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    final before = await call('GET', '/api/voice/status');
    expect(before['listsVoices'], isTrue);
    expect(before['voices'], isEmpty);

    // A voice was added on the server since the app last asked.
    server.serveFile(_listPath, _dataList);
    final after = await call('POST', '/api/voice/list-voices');

    expect(after['found'], 4);
    expect(
      [for (final v in after['voices'] as List) v['id']],
      ['willa', 'orrin', 'design', 'auto'],
    );
    expect(server.hits(_listPath), 2);
  });

  test('a server of your own needs no API key: the request goes out with '
      'none, and its audio comes back', () async {
    final server = await SpeechServer.start();
    final engine = OpenAiTtsEngine(
      baseUrl: server.baseUrl,
      model: SpeechServer.model,
    );

    expect(await engine.isAvailable, isTrue);
    final audio = await engine.generateAudio('Hello there.', 'aisha', 1);
    addTearDown(() => audio?.deleteSync());

    expect(audio, isNotNull, reason: '${engine.lastFailure}');
    expect(String.fromCharCodes(audio!.readAsBytesSync().take(4)), 'RIFF');
    expect(server.requests.single.authorization, isNull);
    expect(engine.lastFailure, isNull);
  });

  test('a server that refuses says why: the wrong model and an unknown '
      'voice each name the reason', () async {
    final server = await SpeechServer.start();
    final engine = OpenAiTtsEngine(baseUrl: server.baseUrl);

    expect(await engine.generateAudio('Hi.', 'aisha', 1), isNull);
    expect(
      engine.lastFailure,
      contains("Unsupported model 'tts-1'. Supported: omnivoice."),
    );

    engine.model = SpeechServer.model;
    expect(await engine.generateAudio('Hi.', 'af_heart', 1), isNull);
    expect(engine.lastFailure, contains("Voice 'af_heart' not found."));
  });

  test('Speak on a server that refuses shows its reason instead of '
      'staying silent', () async {
    final server = await SpeechServer.start();
    final storage = _openAiAt(server.baseUrl);
    await storage.ttsSettings.setTtsEnabled(true);
    await storage.ttsSettings.setTtsVoiceModel('aisha');
    final tts = _ttsOn(storage);

    await tts.speak('Hello there.');

    expect(server.requests, isNotEmpty);
    expect(tts.lastError, contains("Unsupported model 'tts-1'"));
    expect(tts.isSpeaking, isFalse);
  });
}
