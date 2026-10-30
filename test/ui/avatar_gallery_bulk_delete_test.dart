// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Avatar Gallery's Select mode, Clear, Replace-on-ZIP-import and Undo,
// driven through the real dialog over a real library on disk. Web twin:
// web_ui/src/components/AvatarManager.test.tsx; the shared removal is pinned
// in test/services/character_repository_media_test.dart.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_dialog.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../helpers/double_tap.dart';

Uint8List _picture(int seed) {
  final image = img.Image(width: 20, height: 24);
  img.fill(image, color: img.ColorRgb8(30 + seed * 20, 60, 90));
  image.setPixelRgb(3, 4, 200, 10, seed * 30);
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _zip(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late AppDatabase db;
  late Directory tempRoot;
  late StorageService storage;
  late CharacterRepository repository;
  late CharacterCard card;

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'timed out waiting');
    await tester.pump();
  }

  bool shows(String text) => find.text(text).evaluate().isNotEmpty;

  /// Until the gallery's saving spinner is gone: the write has settled.
  Future<void> idle(WidgetTester tester) => settle(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );

  Future<void> tapImportZip(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Import ZIP sprite pack'));
    await tester.pump();
    await tester.tap(find.text('Import ZIP sprite pack'));
    await tester.pump();
  }

  Future<List<AvatarImage>> rows(WidgetTester tester) async =>
      (await tester.runAsync(() => repository.getAvatarImages(card.dbId!)))!;

  /// A portrait, two looks and three expressions (two joy, one sadness).
  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      tempRoot = Directory.systemTemp.createTempSync('fpai_gallery_bulk_');
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
      await storage.charactersDir.create(recursive: true);
      final source = File(p.join(tempRoot.path, 'face.png'))
        ..writeAsBytesSync(_picture(9));
      final draft = CharacterCard(name: 'Bulk Gallery');
      final png = p.join(storage.charactersDir.path, 'Bulk_Gallery_1.png');
      await V2CardService().saveCardAsPng(draft, png, source.path);
      draft.imagePath = png;
      await repository.addCharacter(draft);
      card = repository.characters.single;
      for (var i = 0; i < 2; i++) {
        await repository.addLook(card.dbId!, card.name, _picture(i));
      }
      for (final (i, label) in ['joy', 'joy', 'sadness'].indexed) {
        await repository.addAvatar(
          card.dbId!,
          card.name,
          _picture(3 + i),
          label,
        );
      }
      card.avatarImages = await repository.getAvatarImages(card.dbId!);
    });
    addTearDown(() async {
      PickerPrefs.testPickFilesOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      repository.dispose();
      await db.close();
      // Best-effort: Windows can still hold a just-decoded picture open.
      try {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      } on FileSystemException {
        // Left for the OS to clear with the rest of the temp folder.
      }
    });
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAvatarGallery(
                context: context,
                character: card,
                repository: repository,
                storage: storage,
                mode: WardrobeMode.library,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await settle(tester, () => shows('Expression images'));
  }

  Future<void> menu(
    WidgetTester tester,
    String item, {
    bool looks = false,
  }) async {
    final more = find.byTooltip('More');
    await tester.tap(looks ? more.first : more.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(item).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 15));
  }

  testWidgets('Select all, then Delete twice in one frame: one batch, one '
      'confirm; Undo brings every picture back', (tester) async {
    await seed(tester);
    final before = (await rows(tester)).map((a) => a.id).toSet();
    await open(tester);

    await menu(tester, 'Select…');
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('5 selected'), findsOneWidget);
    await doubleTapNoFrame(tester, find.text('Delete 5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Delete 5 images?'),
      findsOneWidget,
      reason: 'one confirm',
    );

    await doubleTapNoFrame(tester, find.text('Delete 5').last);
    await tester.pump();
    await settle(tester, () => shows('Deleted 5 images'));
    expect(
      find.text('Expression images'),
      findsOneWidget,
      reason: 'the gallery stays open',
    );
    expect(await rows(tester), isEmpty);
    final batches = galleryUndoRoot(storage).listSync();
    expect(batches, hasLength(1), reason: 'one removal, not five');

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await settle(tester, () => !shows('Deleted 5 images'));
    await idle(tester);
    expect((await rows(tester)).map((a) => a.id).toSet(), before);
    await finish(tester);
  });

  testWidgets('Clear expressions keeps the looks and the portrait', (
    tester,
  ) async {
    await seed(tester);
    await open(tester);
    await menu(tester, 'Clear expressions');
    expect(find.text('Delete all 3 expression images?'), findsOneWidget);
    await tester.tap(find.text('Delete all'));
    await tester.pump();
    await settle(tester, () => shows('Deleted 3 images'));
    final left = await rows(tester);
    expect(left.where((a) => !a.isLook), isEmpty);
    expect(left.where((a) => a.isLook), hasLength(2));
    expect(File(card.imagePath!).existsSync(), isTrue);
    await finish(tester);
  });

  testWidgets('a ZIP with nothing recognizable leaves the gallery as it was', (
    tester,
  ) async {
    await seed(tester);
    final before = (await rows(tester)).map((a) => a.id).toSet();
    final zip = _zip({
      'readme.txt': Uint8List.fromList('hi'.codeUnits),
      'random.png': _picture(1),
    });
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async =>
            FilePickerResult([
              MemoryPlatformFile(name: 'pack.zip', bytes: zip),
            ]);
    await open(tester);
    await tapImportZip(tester);
    await settle(
      tester,
      () => shows(
        'Nothing in that ZIP is named for an expression. The gallery was not changed.',
      ),
    );
    expect(find.text('Add to these, or replace them?'), findsNothing);
    expect((await rows(tester)).map((a) => a.id).toSet(), before);
    await finish(tester);
  });

  testWidgets(
    'Replace swaps the expressions for the pack; Undo swaps them back',
    (tester) async {
      await seed(tester);
      final before = (await rows(tester)).map((a) => a.id).toSet();
      final zip = _zip({'anger.png': _picture(7), 'joy.png': _picture(8)});
      PickerPrefs.testPickFilesOverride =
          ({required String category, List<String>? allowedExtensions}) async =>
              FilePickerResult([
                MemoryPlatformFile(name: 'pack.zip', bytes: zip),
              ]);
      await open(tester);
      await tapImportZip(tester);
      await settle(tester, () => shows('Add to these, or replace them?'));
      await tester.tap(find.text('Replace them'));
      await tester.pump();
      await settle(
        tester,
        () => shows('Replaced 3 expression images with 2 from the pack'),
      );
      final replaced = await rows(tester);
      expect(replaced.where((a) => !a.isLook).map((a) => a.label).toSet(), {
        'anger',
        'joy',
      });
      expect(replaced.where((a) => a.isLook), hasLength(2));

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await settle(
        tester,
        () => !shows('Replaced 3 expression images with 2 from the pack'),
      );
      await idle(tester);
      expect((await rows(tester)).map((a) => a.id).toSet(), before);
      await finish(tester);
    },
  );

  for (final size in const [Size(400, 900), Size(1440, 900)]) {
    testWidgets(
      'the select bar and the Undo banner fit a ${size.width.toInt()} px window',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await seed(tester);
        await open(tester);
        await menu(tester, 'Select…');
        await tester.tap(find.text('Select all'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Delete 5'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Delete 5').last);
        await tester.pump();
        await settle(tester, () => shows('Deleted 5 images'));
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }
}
