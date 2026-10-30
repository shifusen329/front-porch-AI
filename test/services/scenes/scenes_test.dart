// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Scene backgrounds: a character's pictures of places, named by place
// (porch.png, porch-night.png), read against where the Realism Engine says
// the character is. Names round-trip, the library writes real files, the
// matcher reads whole words, and a real ChatService's backdrop follows the
// stance stamped on each reply: it holds through a reply that names no
// place, lets go at a place with no picture, and rewinds when the newest
// reply is deleted.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Router;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show SceneBackdrop;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/scene_library/scene_library.dart';

import '../../helpers/chat_db_teardown.dart';
import '../../helpers/double_tap.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_scenes_').path;
        }
        return null;
      });
}

/// A small real PNG, a different picture per [shade].
Uint8List _png(int shade) {
  final image = img.Image(width: 4, height: 4);
  img.fill(image, color: img.ColorRgb8(shade * 20 % 256, 60, 90));
  return img.encodePng(image);
}

SceneImage _scene(String name) => SceneImage.parse(File(name))!;

/// Lets real file work finish between frames until [until] finds
/// something; each file step needs its own round.
Future<void> settle(WidgetTester tester, Finder until) async {
  for (var i = 0; i < 200 && until.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentScenes';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  group('scene names', () {
    test('a name reads back as its place, time and alternate', () {
      for (final (name, place, time, alt) in [
        ('porch.png', 'porch', null, 0),
        ('porch-night.png', 'porch', SceneTime.night, 0),
        ('living-room-evening-2.jpg', 'living room', SceneTime.evening, 2),
        ('Living_Room.PNG', 'living room', null, 0),
        ('night.png', 'night', null, 0),
        ('night-2.webp', 'night', null, 2),
      ]) {
        final s = _scene(name);
        expect((s.place, s.time, s.alt), (place, time, alt), reason: name);
        final ext = p.extension(name).substring(1).toLowerCase();
        expect(
          SceneImage.parse(
            File(SceneImage.fileName(place, time: time, alt: alt, ext: ext)),
          )!.toJson(),
          {...s.toJson(), 'name': isNotNull},
          reason: 'round trip of $name',
        );
      }
      expect(SceneImage.parse(File('porch.txt')), isNull);
      expect(SceneImage.parse(File('.png')), isNull);
    });

    test('a place that would not read back is refused', () {
      expect(scenePlaceProblem('porch'), isNull);
      expect(scenePlaceProblem('living room'), isNull);
      expect(scenePlaceProblem('101'), isNull);
      expect(scenePlaceProblem(''), isNotNull);
      expect(scenePlaceProblem('room 101'), isNotNull);
      expect(scenePlaceProblem('porch night'), isNotNull);
      expect(scenePlaceProblem('con'), isNotNull);
      expect(scenePlaceProblem('x' * 61), isNotNull);
    });

    test('the story clock maps to a picture time', () {
      expect(SceneTime.fromPeriod('dawn'), SceneTime.morning);
      expect(SceneTime.fromPeriod('morning'), SceneTime.morning);
      expect(SceneTime.fromPeriod('late_morning'), SceneTime.day);
      expect(SceneTime.fromPeriod('afternoon'), SceneTime.day);
      expect(SceneTime.fromPeriod('evening'), SceneTime.evening);
      expect(SceneTime.fromPeriod('night'), SceneTime.night);
    });
  });

  group('reading a location phrase', () {
    String? placeOf(String phrase, List<String> places) =>
        switch (SceneMatcher.read(phrase, places)) {
          AtPicturedPlace(:final place) => place,
          AtOtherPlace() => '(elsewhere)',
          NoPlace() => null,
        };

    test('whole words, plurals, and the longest place', () {
      const places = ['porch', 'kitchen', 'room', 'living room'];
      expect(placeOf('sitting on the porch swing', places), 'porch');
      expect(placeOf('pacing between the porches', places), 'porch');
      expect(placeOf('under the porchlight', places), isNull);
      expect(placeOf('curled up in the living room', places), 'living room');
      expect(placeOf('Standing at the KITCHEN counter', places), 'kitchen');
    });

    test('synonyms work both ways', () {
      expect(placeOf('out on the veranda', ['porch']), 'porch');
      expect(placeOf('out on the porch', ['veranda']), 'veranda');
      expect(placeOf('lying on the bed', ['bedroom', 'porch']), 'bedroom');
    });

    test('a place with no picture ends the scene; no place holds it', () {
      expect(placeOf('walks into the hallway', ['porch']), '(elsewhere)');
      expect(placeOf('leaning back, eyes closed', ['porch']), isNull);
      expect(placeOf('', ['porch']), isNull);
    });

    test('the picture for the time of day', () {
      final porch = _scene('porch.png');
      final night = _scene('porch-night.png');
      final morning = _scene('porch-morning.png');
      final evening = _scene('porch-evening.png');
      expect(SceneMatcher.pick([porch, night], SceneTime.night, 's'), night);
      expect(SceneMatcher.pick([porch, night], SceneTime.day, 's'), porch);
      // No untimed one: the nearest time with the same light.
      expect(
        SceneMatcher.pick([morning, evening], SceneTime.night, 's'),
        evening,
      );
      expect(SceneMatcher.pick([morning, night], SceneTime.day, 's'), morning);
      expect(SceneMatcher.pick(const [], SceneTime.day, 's'), isNull);
    });

    test('alternates are picked the same way every time', () {
      final all = [
        _scene('porch.png'),
        _scene('porch-2.png'),
        _scene('porch-3.png'),
      ];
      final first = SceneMatcher.pick(all, SceneTime.day, 'chat-1|porch|day');
      for (var i = 0; i < 5; i++) {
        expect(
          SceneMatcher.pick(
            all.reversed.toList(),
            SceneTime.day,
            'chat-1|porch|day',
          )!.name,
          first!.name,
        );
      }
    });
  });

  group('a character\'s library', () {
    late Directory root;
    late SceneLibrary library;

    setUp(() {
      root = Directory.systemTemp.createTempSync('fpai_scene_lib_');
      library = SceneLibrary(() => root);
      addTearDown(() => root.delete(recursive: true));
    });

    test('adds, numbers alternates, renames, removes and clears', () async {
      final before = SceneLibrary.revision.value;
      final porch = await library.add('Mabel Lee', _png(1), place: 'Porch');
      expect(porch.name, 'porch.png');
      expect(porch.file.parent.path, p.join(root.path, 'Mabel_Lee', 'scenes'));
      expect(SceneLibrary.revision.value, greaterThan(before));

      final again = await library.add('Mabel Lee', _png(2), place: 'porch');
      expect(again.name, 'porch-2.png');
      final night = await library.add(
        'Mabel Lee',
        _png(3),
        place: 'porch',
        time: SceneTime.night,
      );
      expect(night.name, 'porch-night.png');

      await expectLater(
        library.add(
          'Mabel Lee',
          Uint8List.fromList(utf8.encode('hi')),
          place: 'porch',
        ),
        throwsFormatException,
      );
      await expectLater(
        library.add('Mabel Lee', _png(4), place: 'room 101'),
        throwsFormatException,
      );

      final moved = await library.rename(
        'Mabel Lee',
        'porch-2.png',
        place: 'porch',
        time: SceneTime.night,
      );
      expect(moved!.name, 'porch-night-2.png');
      expect((await library.list('Mabel Lee')).map((s) => s.name), [
        'porch-night-2.png',
        'porch-night.png',
        'porch.png',
      ]);
      expect(await library.rename('Mabel Lee', '../x.png', place: 'a'), isNull);

      expect(await library.remove('Mabel Lee', 'porch.png'), isTrue);
      expect(await library.remove('Mabel Lee', 'porch.png'), isFalse);
      expect(await library.clear('Mabel Lee'), 2);
      expect(await library.list('Mabel Lee'), isEmpty);
    });

    test('imports a ZIP named by place, folders and all', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('scenes/porch.png', 0, _png(1)))
        ..addFile(ArchiveFile('porch-night.png', 0, _png(2)))
        ..addFile(ArchiveFile('Kitchen.png', 0, _png(3)))
        ..addFile(ArchiveFile('readme.txt', 0, utf8.encode('hello')))
        ..addFile(ArchiveFile('notes.png', 0, utf8.encode('not a picture')))
        ..addFile(ArchiveFile('con.png', 0, _png(4)));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive));
      final result = await library.importZip('Mabel', zip);
      expect(result.added, 3);
      expect(result.skipped, 2);
      expect((await library.list('Mabel')).map((s) => s.name), [
        'kitchen.png',
        'porch-night.png',
        'porch.png',
      ]);
      await expectLater(
        library.importZip('Mabel', Uint8List.fromList(utf8.encode('nope'))),
        throwsFormatException,
      );
    });
  });

  group('the chat background follows the stance', () {
    AppDatabase? db;
    StorageService? storage;
    CharacterRepository? repo;
    ChatService? chat;
    late SceneLibrary library;

    Future<void> drain() async {
      for (
        var i = 0;
        i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<String?> shown() async {
      final backdrop = SceneBackdrop.of(chat!, storage!);
      await drain();
      await backdrop.settled;
      return backdrop.current?.scene.name;
    }

    Future<void> boot({Map<String, Object> prefs = const {}}) async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'passage_of_time_default': true,
        ...prefs,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      repo = CharacterRepository(db!, storage!);
      chat =
          ChatService(
              KoboldService(storage!),
              UserPersonaService(db!),
              storage!,
              WorldRepository(storage!, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo!)
            ..testLlmServiceOverride = _SilentLlm();
      await storage!.initialized;
      library = SceneLibrary(() => storage!.charactersDir);
      final mabel = CharacterCard(
        name: 'Mabel',
        firstMessage: 'Evening.',
        imagePath: p.join(Directory.systemTemp.path, 'mabel-scene.png'),
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );
      await repo!.addCharacter(mabel);
      await chat!.setActiveCharacter(mabel);
      await drain();
      await library.add('Mabel', _png(1), place: 'porch');
      await library.add(
        'Mabel',
        _png(2),
        place: 'porch',
        time: SceneTime.night,
      );
      await library.add('Mabel', _png(3), place: 'kitchen');
    }

    /// Replaces the chat with replies stamped with these stances, at [hour]
    /// on the story clock.
    Future<void> plant(List<String> stances, {int hour = 15}) async {
      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      await db!.deleteMessagesForSession(sid);
      var pos = 0;
      for (final stance in stances) {
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'm$pos',
            sessionId: sid,
            position: pos++,
            sender: 'Mabel',
            isUser: false,
            swipes: Value(jsonEncode(['Line $pos.'])),
            metadata: Value(
              jsonEncode({
                'realism_state': {'spatialStance': stance},
              }),
            ),
          ),
        );
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'm$pos',
            sessionId: sid,
            position: pos++,
            sender: 'You',
            isUser: true,
            swipes: Value(jsonEncode(['And $pos.'])),
          ),
        );
      }
      final clock = DateTime.utc(2026, 6, 28, hour).toIso8601String();
      await db!.patchSession(
        SessionsCompanion(
          id: Value(sid),
          spatialStance: const Value(''),
          passageOfTimeEnabled: const Value(true),
          passageOfTimeGateMigrated: const Value(true),
          storyClock: Value(clock),
          storyStartDate: const Value('2026-06-28'),
        ),
      );
      await chat!.reloadCurrentSession();
      await drain();
    }

    tearDown(() => disposeChatThenCloseDb(chat, db));

    test('holds through a reply with no place, lets go at a place with no '
        'picture, and rewinds when that reply is deleted', () async {
      await boot();
      await plant(['sitting on the porch swing', 'leaning back, eyes closed']);
      expect(await shown(), 'porch.png');

      await plant(['sitting on the porch swing', 'walks into the hallway']);
      expect(await shown(), isNull);

      final hallway = chat!.messages.lastIndexWhere((m) => !m.isUser);
      await chat!.deleteMessage(chat!.messages.length - 1);
      await chat!.deleteMessage(hallway);
      expect(await shown(), 'porch.png');

      await plant(['standing at the kitchen counter']);
      expect(await shown(), 'kitchen.png');
    });

    test('shows the night picture at night', () async {
      await boot();
      await plant(['out on the veranda'], hour: 23);
      expect(await shown(), 'porch-night.png');
    });

    test(
      'needs the Realism Engine, and the chat or Appearance switch',
      () async {
        await boot();
        await plant(['sitting on the porch swing']);
        expect(await shown(), 'porch.png');

        await chat!.setRealismEnabled(false);
        expect(await shown(), isNull);
        await chat!.setRealismEnabled(true);
        expect(await shown(), 'porch.png');

        await storage!.expressionSettings.setSceneBackgrounds(false);
        expect(await shown(), isNull);
        chat!.sessionThemeOverrides = chat!.sessionThemeOverrides.copy()
          ..followScene = true;
        expect(await shown(), 'porch.png');
        chat!.sessionThemeOverrides = chat!.sessionThemeOverrides.copy()
          ..followScene = false;
        expect(await shown(), isNull);
      },
    );

    testWidgets('the layer cross-fades to the scene, and swaps at once with '
        'reduce motion', (tester) async {
      await tester.runAsync(() async {
        await boot();
        await plant(['sitting on the porch swing']);
        await shown();
      });
      final backdrop = SceneBackdrop.of(chat!, storage!);
      Finder scene(String name) => find.byKey(ValueKey('scene:Mabel/$name'));
      Future<void> moveTo(String stance, String name) async {
        await tester.runAsync(() async {
          await plant([stance]);
          await shown();
        });
        await settle(tester, scene(name));
      }

      Widget layer({bool still = false}) => MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: SceneBackdropLayer(backdrop: backdrop),
          ),
        ),
      );

      await tester.pumpWidget(layer());
      await settle(tester, scene('porch.png'));
      await tester.pump(SceneBackdropLayer.fade);
      expect(scene('porch.png'), findsOneWidget);

      await moveTo('standing at the kitchen counter', 'kitchen.png');
      await tester.pump(SceneBackdropLayer.fade ~/ 2);
      expect(scene('porch.png'), findsOneWidget, reason: 'mid-fade');
      expect(scene('kitchen.png'), findsOneWidget, reason: 'mid-fade');
      await tester.pump(SceneBackdropLayer.fade);
      expect(scene('porch.png'), findsNothing);

      await tester.pumpWidget(layer(still: true));
      await moveTo('sitting on the porch swing', 'porch.png');
      // No fade: the old picture goes on the next frame, not 600 ms later.
      await tester.pump();
      await tester.pump();
      expect(scene('porch.png'), findsOneWidget);
      expect(scene('kitchen.png'), findsNothing, reason: 'no fade');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => disposeChatThenCloseDb(chat, db));
      (chat, db) = (null, null);
    });

    test('the phone reads the same scene and its picture', () async {
      await boot();
      await plant(['out on the porch steps'], hour: 22);
      final router = Router();
      WebChatStageRoutes(ChatStageFacade(chat!, storage!), router);
      final stage = await router.call(
        shelf.Request('GET', Uri.parse('http://localhost/api/chat/stage')),
      );
      final scene = (jsonDecode(await stage.readAsString()) as Map)['scene'];
      expect(scene, {
        'who': 'Mabel',
        'v': 'porch-night.png',
        'place': 'porch',
        'time': 'night',
      });
      final picture = await router.call(
        shelf.Request(
          'GET',
          Uri.parse(
            'http://localhost/api/chat/scene/image?who=Mabel&v=porch-night.png',
          ),
        ),
      );
      expect(picture.statusCode, 200);
      expect(
        await picture.read().expand((b) => b).toList(),
        await File(
          p.join(
            storage!.charactersDir.path,
            'Mabel',
            'scenes',
            'porch-night.png',
          ),
        ).readAsBytes(),
      );
      for (final bad in ['who=Other&v=porch.png', 'who=Mabel&v=../x.png']) {
        final miss = await router.call(
          shelf.Request(
            'GET',
            Uri.parse('http://localhost/api/chat/scene/image?$bad'),
          ),
        );
        expect(miss.statusCode, 404, reason: bad);
      }
    });

    test('the phone adds, renames, imports and deletes scenes', () async {
      await boot();
      final id = repo!.characters.single.dbId!;
      final router = Router();
      WebCharacterSceneRoutes(
        CharacterAuthoringFacade(repo!, storage!).scenes,
        router,
        thumbnails: ThumbnailCache(storage!.webThumbnailCacheDir),
      );
      Future<(int, Map)> call(
        String method,
        String path, [
        Object? body,
      ]) async {
        final r = await router.call(
          shelf.Request(
            method,
            Uri.parse('http://localhost/api/characters/$id$path'),
            body: body is Map ? jsonEncode(body) : body,
          ),
        );
        final text = await r.readAsString();
        return (
          r.statusCode,
          text.startsWith('{') ? jsonDecode(text) as Map : {},
        );
      }

      List<Object?> names(Map m) => [for (final s in m['scenes']) s['name']];

      var (status, body) = await call('GET', '/scenes');
      expect(names(body), ['kitchen.png', 'porch-night.png', 'porch.png']);

      (status, body) = await call(
        'POST',
        '/scenes?place=Living%20Room&time=evening',
        _png(5),
      );
      expect(status, 200);
      expect(body['added'], {
        'name': 'living-room-evening.png',
        'place': 'living room',
        'time': 'evening',
        'alt': 0,
      });
      (status, body) = await call(
        'POST',
        '/scenes?place=porch',
        utf8.encode('x'),
      );
      expect(status, 400);
      (status, body) = await call('POST', '/scenes?place=room%20101', _png(6));
      expect(status, 400);

      (status, body) = await call('POST', '/scenes/rename', {
        'name': 'kitchen.png',
        'place': 'kitchen',
        'time': 'night',
      });
      expect(body['name'], 'kitchen-night.png');
      (status, body) = await call('POST', '/scenes/rename', {
        'name': '../porch.png',
        'place': 'x',
      });
      expect(status, 404);

      final zip = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('beach.png', 0, _png(7))),
      );
      (status, body) = await call('POST', '/scenes/zip', zip);
      expect(body['added'], 1);
      (status, body) = await call('POST', '/scenes/zip', utf8.encode('nope'));
      expect(status, 400);

      final image = await router.call(
        shelf.Request(
          'GET',
          Uri.parse(
            'http://localhost/api/characters/$id/scenes/beach.png/image',
          ),
        ),
      );
      expect(image.statusCode, 200);

      (status, body) = await call('POST', '/scenes/delete', {
        'name': 'beach.png',
      });
      expect(names(body), isNot(contains('beach.png')));
      (status, body) = await call('POST', '/scenes/delete', {});
      expect(status, 400);
      (status, body) = await call('POST', '/scenes/delete', {'clear': true});
      expect(body['scenes'], isEmpty);
    });
  });

  group('the Scenes dialog', () {
    late StorageService storage;
    final card = CharacterCard(name: 'Mabel');

    Future<void> open(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({'update_auto_check': false});
        storage = StorageService();
        await storage.initialized;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSceneLibrary(
                context,
                character: card,
                storage: storage,
                pickImage: (_) async => _png(9),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester, find.byKey(const ValueKey('scene-add')));
    }

    Future<void> close(WidgetTester tester) async {
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Add tapped twice in one frame writes one picture', (
      tester,
    ) async {
      await open(tester, const Size(1440, 900));
      await doubleTapNoFrame(tester, find.byKey(const ValueKey('scene-add')));
      await settle(tester, find.byKey(const ValueKey('scene-place')));
      expect(find.byKey(const ValueKey('scene-place')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('scene-place')),
        'porch',
      );
      await tester.tap(find.byKey(const ValueKey('scene-place-save')));
      await settle(tester, find.text('Added porch.'));

      final files = await tester.runAsync(
        () => SceneLibrary(() => storage.charactersDir).list('Mabel'),
      );
      expect(files!.map((s) => s.name), ['porch.png']);
      expect(
        find.byKey(const ValueKey('scene-tile-porch.png')),
        findsOneWidget,
      );
      expect(find.text('Added porch.'), findsOneWidget);
    });

    testWidgets('fits a phone, a wide window and a short one', (tester) async {
      for (final size in const [
        Size(400, 800),
        Size(1440, 900),
        Size(1024, 420),
      ]) {
        await open(tester, size);
        await tester.runAsync(() async {
          final library = SceneLibrary(() => storage.charactersDir);
          for (final place in [
            'porch',
            'kitchen',
            'living room',
            'back yard',
          ]) {
            await library.add('Mabel', _png(place.length), place: place);
          }
        });
        await close(tester);
        await tester.tap(find.text('Open'));
        await settle(
          tester,
          find.byKey(const ValueKey('scene-tile-porch.png')),
        );
        expect(
          find.byKey(const ValueKey('scene-tile-porch.png')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: '$size');
        await close(tester);
      }
    });
  });
}
