// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Painting a missing scene against REAL servers: an OpenAI-compatible chat
// model on the chat's side lane describes an empty kitchen at night as
// danbooru tags, and a real AUTOMATIC1111-style server (A1111, Forge,
// reForge) paints it into the character's Scenes. Skipped unless all three
// are named (CI has neither):
//
//   SCENE_LIVE_SDAPI_URL=http://host:7860 \
//   SCENE_LIVE_LLM_URL=http://host:8006/v1 SCENE_LIVE_LLM_MODEL=name \
//     flutter test --tags live test/live/scene_painting_live_test.dart
//
// The server paints with whatever checkpoint it has loaded.

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show ScenePainter, SceneWant;
import 'package:front_porch_ai/services/services.dart';

import '../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sdapi = Platform.environment['SCENE_LIVE_SDAPI_URL'] ?? '';
  final llmUrl = Platform.environment['SCENE_LIVE_LLM_URL'] ?? '';
  final model = Platform.environment['SCENE_LIVE_LLM_MODEL'] ?? '';
  final skip = sdapi.isEmpty || llmUrl.isEmpty || model.isEmpty
      ? 'set SCENE_LIVE_SDAPI_URL, SCENE_LIVE_LLM_URL and '
            'SCENE_LIVE_LLM_MODEL to run'
      : false;

  setUpAll(() {
    // `flutter test` answers every HTTP call itself unless this is cleared.
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('fpai_scene_live_').path,
        );
  });

  test(
    'a real model writes tags for an empty kitchen, and a real server '
    'paints it',
    () async {
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final db = AppDatabase.forTesting();
      final storage = StorageService();
      await storage.initialized;
      final chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: llmUrl,
              modelName: model,
            );
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('a1111');
      await s.setLocalImageGenUrl(sdapi);
      await s.setImageGenPromptParadigm('tags');
      await s.setImageGenStyle('anime');
      final images = ImageGenService(storage);
      final library = SceneLibrary(() => storage.charactersDir);

      String? written;
      final painter = ScenePainter(
        generator: () => images,
        writePrompt: (instruction) async =>
            written = await chat.writeScenePrompt(instruction),
        storage: storage,
        library: library,
      );
      addTearDown(painter.dispose);
      painter.want(
        const SceneWant(
          owner: 'Mabel',
          place: 'kitchen',
          time: SceneTime.night,
          stance: 'standing at the kitchen counter',
          story:
              'Mabel set the kettle on the old iron stove and leaned on the '
              'counter while the rain ran down the window over the sink.',
          setting: 'A farmhouse in the hills, late autumn.',
          names: ['Mabel'],
        ),
      );
      await painter.idle;

      expect(painter.problem, isNull);
      expect(written, isNotNull, reason: 'the model wrote nothing');
      final tags = cleanSceneTags(
        written!,
        place: 'kitchen',
        time: SceneTime.night,
        names: ['Mabel'],
      );
      // ignore: avoid_print
      print('model: $written\nsent:  $tags');
      expect(written!.split(',').length, greaterThan(4), reason: 'not tags');
      expect(tags, startsWith('no humans, scenery'));
      expect(tags, isNot(contains('1girl')));
      expect(tags.toLowerCase(), isNot(contains('mabel')));

      final painted = await library.list('Mabel');
      expect(painted.map((p) => p.name), ['kitchen-night.png']);
      final bytes = await painted.single.file.readAsBytes();
      expect(sniffImageExt(bytes), 'png');
      // ignore: avoid_print
      print('painted: ${painted.single.file.path} (${bytes.length} bytes)');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
