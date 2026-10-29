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

// The Avatar Gallery's expressions: up to 40 distinct expressions, and any
// number of alternates of one (joy.png, joy-1.png …), which never count. A
// ZIP sprite pack past 40 skips only the new expressions; the counter says
// how many expressions and how many images. A real library on disk.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_expressions_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late AppDatabase db;
  late Directory tempRoot;
  late StorageService storage;
  late CharacterRepository repository;
  late AvatarGalleryController controller;

  final png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
  List<({Uint8List bytes, String emotion})> pack(List<String> labels) => [
    for (final l in labels) (bytes: png, emotion: l),
  ];

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('fpai_gallery_limit_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempRoot.path;
          }
          return null;
        });
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    await storage.initialized;
    repository = CharacterRepository(db, storage);
    while (repository.isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    await repository.addCharacter(
      CharacterCard(name: 'Limit Tester', firstMessage: 'Hello.'),
    );
    await repository.loadCharacters();
    controller = AvatarGalleryController(
      libraryCard: repository.characters.single,
      repository: repository,
      storage: storage,
      mode: WardrobeMode.library,
    );
    await controller.init();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    controller.dispose();
    repository.dispose();
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  final fortyOne = [for (var i = 0; i <= 40; i++) 'e$i'];

  test('a pack past 40 skips only the new expressions; alternates all go '
      'in', () async {
    final (added, unrecognized, skipped) = await controller.importSpritePack(
      pack(['e0', 'e0', ...fortyOne, 'e0', 'E5']),
      2,
    );

    expect(controller.lastError, isNull);
    expect(skipped, 1, reason: 'e40 is a 41st expression');
    expect(added, 44, reason: '40 expressions and 4 alternates');
    expect(unrecognized, 2);
    expect(controller.usedLabels, hasLength(40));
    expect(controller.usedLabels, isNot(contains('e40')));
    expect(controller.expressions, hasLength(44));
  });

  test('at 40, one more image of an expression is added, a new expression '
      'is not', () async {
    await controller.importSpritePack(pack(fortyOne.take(40).toList()), 0);
    expect(controller.usedLabels, hasLength(40));

    await controller.addExpression(png, 'cowgirl');
    expect(controller.expressions, hasLength(40));

    await controller.addExpression(png, 'e7');
    expect(controller.expressions, hasLength(41));
    expect(controller.usedLabels, hasLength(40));
  });

  testWidgets('the counter reads expressions, then images when alternates '
      'exist', (tester) async {
    await tester.runAsync(
      () => controller.importSpritePack(
        pack([...fortyOne.take(40), 'e1', 'e2']),
        0,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AvatarGalleryExpressionsSection(
              controller: controller,
              onAddExpression: () {},
              onImportZip: () {},
              onExpand: () {},
              onRelabel: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('40/40 expressions · 42 images'), findsOneWidget);
    // Alternates still fit at 40, so adding stays open.
    expect(find.text('Add expression'), findsOneWidget);
  });

  testWidgets('on a phone the section fits, collapsed and with the counter', (
    tester,
  ) async {
    // The gallery dialog on a 360-wide phone leaves the section about 300.
    tester.view.physicalSize = const Size(300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget section() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AvatarGalleryExpressionsSection(
            controller: controller,
            onAddExpression: () {},
            onImportZip: () {},
            onExpand: () {},
            onRelabel: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(section());
    expect(find.text('Add expression images'), findsOneWidget);

    await tester.runAsync(
      () => controller.importSpritePack(pack(['joy', 'joy', 'anger']), 0),
    );
    await tester.pumpWidget(section());
    expect(find.text('2/40 expressions · 3 images'), findsOneWidget);
  });
}
