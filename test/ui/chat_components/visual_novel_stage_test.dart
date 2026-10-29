// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Visual novel mode: the character stands on stage in the expression image
// for how they feel (changed here with /expression, as a user would), in
// their portrait with expressions off, and nowhere with neither; a chat's
// own choice overrules Settings → Appearance and is saved even with no
// theme; the log panel grows to the full height and back, and a drag
// resizes it; the phone web app's relay names the same figure and serves
// the same picture. A real ChatService and real files on disk.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_stage_facade.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/chat_db_teardown.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_vn_').path;
        }
        return null;
      });
}

/// A 1×1 PNG, a different colour per [shade], so each file is its own
/// picture.
Uint8List _png(int shade) {
  const base =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  final bytes = base64Decode(base);
  bytes[bytes.length - 20] = shade; // inside the IDAT: a distinct file
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late CharacterCard card;
  late File joy;
  late File neutral;
  late File portrait;

  Future<void> boot({bool expressions = true}) async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'expression_enabled': expressions,
      'visual_novel_mode': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    final dir = storage.characterAvatarDir('Mabel')
      ..createSync(recursive: true);
    joy = File(p.join(dir.path, 'joy.png'))..writeAsBytesSync(_png(1));
    neutral = File(p.join(dir.path, 'neutral.png'))..writeAsBytesSync(_png(2));
    portrait = File(p.join(Directory.systemTemp.path, 'mabel_portrait.png'))
      ..writeAsBytesSync(_png(3));
    AvatarImage face(String label, int order) => AvatarImage(
      id: 'face-$label',
      characterId: 'mabel',
      filename: '$label.png',
      label: label,
      displayOrder: order,
      createdAt: DateTime(2026),
    );
    card = CharacterCard(
      name: 'Mabel',
      firstMessage: 'The kettle is on.',
      imagePath: portrait.path,
      avatarImages: [face('neutral', 0), face('joy', 1)],
    );
    await chat.setActiveCharacter(card);
  }

  Future<void> teardown() => disposeChatThenCloseDb(chat, db);

  test('the character stands in the picture for how they feel, and changes '
      'with it', () async {
    await boot();
    addTearDown(teardown);

    var sprites = stageSpritesFor(chat, storage);
    expect(sprites, hasLength(1));
    expect(sprites.single.name, 'Mabel');
    expect(sprites.single.speaking, isTrue);
    expect(sprites.single.image.path, neutral.path);

    await chat.sendMessage('/expression joy');
    sprites = stageSpritesFor(chat, storage);
    expect(sprites.single.image.path, joy.path);
  });

  test('with Expression Images off the portrait stands in; with no picture '
      'at all nobody is on stage', () async {
    await boot(expressions: false);
    addTearDown(teardown);

    expect(stageSpritesFor(chat, storage).single.image.path, portrait.path);

    await chat.setActiveCharacter(
      CharacterCard(name: 'Nobody', firstMessage: 'Hi.'),
    );
    expect(stageSpritesFor(chat, storage), isEmpty);
  });

  test("a chat's own choice overrules Settings, and is saved with no "
      'theme', () async {
    await boot();
    addTearDown(teardown);
    expect(visualNovelOn(chat, storage), isTrue);

    final own = ChatThemeOverrides(visualNovel: false);
    chat.sessionThemeOverrides = own;
    expect(visualNovelOn(chat, storage), isFalse);

    final saved = own.toJsonString();
    expect(saved, isNotNull, reason: 'a VN choice alone must persist');
    expect(ChatThemeOverrides.fromJsonString(saved).visualNovel, isFalse);
  });

  testWidgets('the stage draws the figure, and the log panel grows to the '
      'full height and back', (tester) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(teardown));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: VisualNovelStageLayer()),
                Positioned.fill(
                  child: VisualNovelLogPanel(child: Text('the chat')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final figure = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('vn-stage')),
        matching: find.byType(Image),
      ),
    );
    expect((figure.image as ResizeImage).imageProvider, FileImage(neutral));

    final panel = find.byKey(const Key('vn-log-panel'));
    expect(
      tester.getSize(panel).height,
      closeTo(800 * VisualNovelLogPanel.defaultShare, 1),
    );
    await tester.tap(find.byKey(const Key('vn-log-handle')));
    await tester.pump();
    expect(tester.getSize(panel).height, 800);
    await tester.tap(find.byKey(const Key('vn-log-handle')));
    await tester.pump();
    expect(tester.getSize(panel).height, closeTo(304, 1));

    await tester.drag(
      find.byKey(const Key('vn-log-handle')),
      const Offset(0, -160),
    );
    await tester.pump();
    expect(
      tester.getSize(panel).height,
      greaterThan(304 + 100),
      reason: 'dragging the handle up gives the log more room',
    );
  });

  test('the phone web app is told the same figure and served the same '
      'picture', () async {
    await boot();
    addTearDown(teardown);
    await chat.sendMessage('/expression joy');
    final router = Router();
    WebChatStageRoutes(ChatStageFacade(chat, storage), router);

    final state = await router.call(
      shelf.Request('GET', Uri.parse('http://localhost/api/chat/stage')),
    );
    final json = jsonDecode(await state.readAsString()) as Map;
    expect(json['visualNovel'], isTrue);
    final figure = (json['stage'] as List).single as Map;
    expect(figure['name'], 'Mabel');
    expect(figure['v'], 'joy.png');

    final picture = await router.call(
      shelf.Request(
        'GET',
        Uri.parse(
          'http://localhost/api/chat/stage/'
          '${Uri.encodeComponent(figure['id'] as String)}',
        ),
      ),
    );
    expect(picture.statusCode, 200);
    expect(picture.headers['content-type'], 'image/png');
    final bytes = await picture.read().expand((c) => c).toList();
    expect(bytes, joy.readAsBytesSync());
  });

  test("a group's speaker follows ONNX mode and /expression; the others "
      'keep their own feeling', () {
    // ONNX mode's label and /expression both describe the last reply,
    // which is the speaker's.
    expect(followsChatExpression(speaking: true, mode: 'onnx'), isTrue);
    expect(followsChatExpression(speaking: false, mode: 'onnx'), isFalse);
    expect(followsChatExpression(speaking: true, mode: 'llm'), isFalse);
    expect(
      followsChatExpression(speaking: true, mode: 'llm', manualLabel: 'joy'),
      isTrue,
    );
    expect(
      followsChatExpression(speaking: false, mode: 'llm', manualLabel: 'joy'),
      isFalse,
    );
  });

  test("a group member's feeling can be one of the classifier model's own "
      'labels', () {
    const withModel = [...EmotionLabels.all, 'cowgirl'];
    expect(standardExpressionLabel('Cowgirl', withModel), 'cowgirl');
    expect(standardExpressionLabel('cowgirl'), 'neutral');
    expect(standardExpressionLabel('flustered', withModel), 'embarrassment');
  });
}
