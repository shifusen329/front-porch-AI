// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/expression/expression.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/voice_facade.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';

import '../../golden/support/fakes.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return Directory.systemTemp.createTempSync('fpai_docs_').path;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('VoiceFacade', () {
    late StorageService storage;
    late VoiceFacade facade;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      facade = VoiceFacade(FakeTtsService(), FakeSttService(), storage);
    });

    test('status reflects storage flags + STT availability', () {
      final s = facade.status();
      // Defaults: TTS/STT off, so nothing is usable yet.
      expect(s['ttsEnabled'], isFalse);
      expect(s['sttEnabled'], isFalse);
      expect(s['sttAvailable'], isFalse);
      expect(s.containsKey('ttsEngine'), isTrue);
    });

    test('speak is a no-op when TTS is disabled', () async {
      expect(await facade.speak('hello'), isNull);
    });

    test('transcribe is a no-op when STT is unavailable or body empty', () async {
      expect(await facade.transcribe(const [1, 2, 3]), isNull); // STT off
      expect(await facade.transcribe(const []), isNull); // empty body
    });
  });

  // The web Voice & Media card sets the Local ONNX expression classifier's
  // model through /api/voice/settings. Desktop twin: the model field test in
  // test/ui/settings/voice_media_tab_interaction_test.dart.
  group('expression classifier model over the relay', () {
    late StorageService storage;
    late Router router;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.initialized;
      router = Router();
      WebVoiceRoutes(
        VoiceFacade(FakeTtsService(), FakeSttService(), storage),
        router,
      );
    });

    Future<(int, Map<String, dynamic>)> call(
      String method,
      String path, [
      Map<String, dynamic>? body,
    ]) async {
      final response = await router.call(
        shelf.Request(
          method,
          Uri.parse('http://localhost$path'),
          body: body == null ? null : jsonEncode(body),
        ),
      );
      return (
        response.statusCode,
        jsonDecode(await response.readAsString()) as Map<String, dynamic>,
      );
    }

    test('a pasted link sets the model; a non-id is refused and changes '
        'nothing', () async {
      final (_, before) = await call('GET', '/api/voice/status');
      expect(before['expressionModel'], kDefaultExpressionModel);
      expect(before['expressionModelLabels'], isNull);

      final (ok, after) = await call('POST', '/api/voice/settings', {
        'expressionModel':
            'https://huggingface.co/Shifusen/distilbert-go_emotions-nsfw',
      });
      expect(ok, 200);
      expect(after['expressionModel'], 'Shifusen/distilbert-go_emotions-nsfw');

      final (refused, _) = await call('POST', '/api/voice/settings', {
        'expressionModel': 'not a model',
        'ttsEnabled': true,
      });
      expect(refused, 400);
      expect(
        storage.expressionSettings.expressionOnnxModel,
        'Shifusen/distilbert-go_emotions-nsfw',
      );
      expect(storage.ttsSettings.ttsEnabled, isFalse);

      await storage.expressionSettings.setExpressionModelLabels(
        'Shifusen/distilbert-go_emotions-nsfw',
        ['joy', 'cowgirl'],
      );
      final (_, labelled) = await call('GET', '/api/voice/status');
      expect(labelled['expressionModelLabels'], ['joy', 'cowgirl']);
    });
  });
}
