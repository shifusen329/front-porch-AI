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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show ScenePainter, ScenePlaceReader, SceneWant;
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

  // reForge never reloads the checkpoint it already has, so an unload before
  // the first picture left every picture failing with "Expected all tensors
  // to be on the same device" until it was restarted.
  test(
    'the first picture after a launch, on the checkpoint the server already '
    'has, paints, and so does the next',
    () async {
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final storage = StorageService();
      await storage.initialized;
      final options = await http.get(Uri.parse('$sdapi/sdapi/v1/options'));
      final loaded = (jsonDecode(options.body) as Map)['sd_model_checkpoint'];
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('a1111');
      await s.setLocalImageGenUrl(sdapi);
      await s.setImageGenModel('$loaded');
      await s.setImageGenSize('512x512');
      await s.setImageGenSteps(4);
      // A new service has no checkpoint of its own yet, as after a launch.
      final images = ImageGenService(storage);

      for (final picture in ['first', 'next']) {
        final bytes = await images.generateImage(prompt: 'scenery, porch');
        expect(
          bytes,
          isNotNull,
          reason: '$picture picture: ${images.statusMessage}',
        );
      }
    },
    skip: sdapi.isEmpty ? 'set SCENE_LIVE_SDAPI_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // The place comes from the model, not a word list: a stairwell (the
  // stance, word for word, from a chat that painted nothing), a gazebo only
  // the reply names, a pictured place under another word, and a stance
  // that names none.
  test(
    'a real model names the place a reply leaves the character in',
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
      final reader = ScenePlaceReader(
        ask: chat.nameScenePlace,
        cacheFile: () => File(
          '${Directory.systemTemp.createTempSync('fpai_place_').path}'
          '/scene_places.json',
        ),
      );

      final cases = [
        (
          'Standing upright on the top step of the stairwell, clutching her '
              'phone under crossed arms',
          'Becky stands so fast her knee knocks the railing. "Nothing! I '
              'was just— nobody comes down these stairs," she says.',
          const <String>[],
          ['stair'],
        ),
        (
          'leaning on the white railing, looking out over the water',
          'Mabel walked down the garden path to the old gazebo by the lake '
              'and leaned on its railing while the sun went down.',
          const ['kitchen', 'porch'],
          ['gazebo'],
        ),
        (
          'curled up on the veranda swing with a blanket',
          'Mabel pushed the swing with one foot and listened to the crickets '
              'in the yard.',
          const ['kitchen', 'porch'],
          ['porch'],
        ),
        (
          'leaning back, eyes closed',
          'Mabel let out a long breath and said nothing for a while.',
          const <String>[],
          [''],
        ),
      ];
      for (final (stance, story, pictured, want) in cases) {
        final place = await reader.read(
          who: stance.startsWith('Standing') ? 'Becky' : 'Mabel',
          stance: stance,
          story: story,
          pictured: pictured,
        );
        // ignore: avoid_print
        print('"$stance" -> "$place"');
        expect(place, isNotNull, reason: 'no answer for "$stance"');
        expect(
          want.any((w) => w.isEmpty ? place!.isEmpty : place!.contains(w)),
          isTrue,
          reason: '"$stance" read as "$place"',
        );
      }
    },
    skip: llmUrl.isEmpty || model.isEmpty
        ? 'set SCENE_LIVE_LLM_URL and SCENE_LIVE_LLM_MODEL to run'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
