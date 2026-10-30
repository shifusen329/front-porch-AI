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

// Behavior-pinning net for the FILE-SIDE media surfaces of
// CharacterRepository that the god-file split (see the split map for
// lib/services/character_repository.dart) moves verbatim into a new
// `character_repository.media.dart` part. These are exactly the members the
// sibling suite (test/services/character_repository_test.dart) does not
// exercise: cleanOrphanedPngs, removeAvatar's on-disk delete (and its
// avatars/ vs looks/ subfolder resolution), updateAvatarLabel,
// addLook's portrait-bootstrap branch, and duplicateCharacter's
// targetDirOverride/skipLibraryInsert group-private-copy path. A refactor
// that changed any of these — e.g. moving a file-deletion call, dropping the
// skipLibraryInsert guard, or losing the subfolder-by-label lookup — would
// go green on every other suite today. This file exists so it doesn't.
//
// Everything here goes through the PUBLIC CharacterRepository API against a
// real temp-dir-backed StorageService + in-memory Drift DB — same
// construction pattern as character_repository_test.dart's "DB integration"
// group (path_provider mocked to a fresh temp dir per StorageService, real
// AppDatabase.forTesting()). No network, no fixtures resembling real chat
// content — every character here is a neutral placeholder name.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/avatar_gallery_removal.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/scenes/scenes.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

/// Mocks path_provider so StorageService can resolve
/// getApplicationDocumentsDirectory() without a real platform channel.
/// Test-local duplicate of character_repository_test.dart's helper (kept
/// self-contained rather than shared, per this being a standalone net).
void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          final tmp = Directory.systemTemp.createTempSync('fpai_media_test_');
          return tmp.path;
        }
        return null;
      });
}

/// A small, non-uniform, non-400x600 PNG: real enough for `img.decodeImage`
/// to succeed, but never mistaken for the V2 creator's solid-color
/// placeholder (which is always exactly 400x600 and single-color).
Uint8List _realPng({int width = 24, int height = 24, int seed = 0}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(20 + seed, 40 + seed, 60 + seed));
  image.setPixelRgb(width ~/ 2, height ~/ 2, 210, 30, 30);
  return img.encodePng(image);
}

class _Ctx {
  _Ctx(this.db, this.storage, this.repo);
  final AppDatabase db;
  final StorageService storage;
  final CharacterRepository repo;
}

/// Robust wait for the constructor's fire-and-forget loadCharacters() to
/// settle — same polling helper as character_repository_test.dart (a bare
/// Duration.zero delay is racy).
Future<void> _waitUntilNotLoading(
  CharacterRepository r, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (r.isLoading) {
    if (DateTime.now().isAfter(deadline)) {
      fail('loadCharacters did not complete within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

/// Fresh, fully isolated repo: a brand-new temp-dir StorageService (the
/// path_provider mock hands out a new systemTemp dir on every call) plus a
/// brand-new in-memory Drift DB. Every test below calls this once so there
/// is zero cross-test disk/DB bleed — no shared tearDown bookkeeping needed.
Future<_Ctx> _freshRepo() async {
  _setupPathProviderMock();
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.initialized;
  final db = AppDatabase.forTesting();
  final repo = CharacterRepository(db, storage);
  await Future<void>.delayed(Duration.zero);
  await _waitUntilNotLoading(repo);
  return _Ctx(db, storage, repo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterRepository — media file-side surfaces (split net)', () {
    test(
      'cleanOrphanedPngs deletes unreferenced PNGs only, leaves referenced '
      'PNGs and non-PNG files untouched, and reports the deleted count',
      () async {
        final ctx = await _freshRepo();
        final charDir = ctx.storage.charactersDir;

        // Referenced: a loaded character's imagePath points straight at it.
        final referencedPath = p.join(charDir.path, 'kept_referenced.png');
        await File(referencedPath).writeAsBytes(_realPng(seed: 1));
        final card = CharacterCard(name: 'Kept', imagePath: referencedPath);
        await ctx.repo.addCharacter(card);

        // Orphan: a PNG sitting in the same folder that no character points at.
        final orphanPath = p.join(charDir.path, 'orphan_unused.png');
        await File(orphanPath).writeAsBytes(_realPng(seed: 2));

        // A non-PNG file must never be touched, referenced or not.
        final txtPath = p.join(charDir.path, 'notes.txt');
        await File(txtPath).writeAsString('not a PNG, leave me alone');

        final deletedCount = await ctx.repo.cleanOrphanedPngs();

        expect(deletedCount, 1);
        expect(File(orphanPath).existsSync(), isFalse);
        expect(File(referencedPath).existsSync(), isTrue);
        expect(File(txtPath).existsSync(), isTrue);

        await ctx.db.close();
      },
    );

    test(
      'removeAvatar deletes the expression PNG from avatars/ on disk and '
      'drops the DB row',
      () async {
        final ctx = await _freshRepo();
        final card = CharacterCard(name: 'ExpressionOwner');
        await ctx.repo.addCharacter(card);
        final characterId = card.dbId!;

        final avatarId = await ctx.repo.addAvatar(
          characterId,
          card.name,
          _realPng(seed: 3),
          'happy',
        );

        final avatarsDir = Directory(
          p.join(ctx.storage.characterBaseDir(card.name).path, 'avatars'),
        );
        final written = avatarsDir.listSync().whereType<File>().toList();
        expect(written, hasLength(1));
        final avatarFile = written.first;
        expect(avatarFile.existsSync(), isTrue);

        await ctx.repo.removeAvatar(characterId, avatarId);

        expect(avatarFile.existsSync(), isFalse);
        expect(await ctx.repo.getAvatarImages(characterId), isEmpty);

        await ctx.db.close();
      },
    );

    test(
      'removeAvatar deletes a gallery LOOK from looks/ (not avatars/), '
      'proving it resolves the subfolder off the row label rather than a '
      'fixed path',
      () async {
        final ctx = await _freshRepo();
        // Give the character a real, non-placeholder portrait up front so
        // addLook below takes the genuine-look branch, not the
        // portrait-bootstrap branch (pinned separately further down).
        final portraitPath = p.join(
          ctx.storage.charactersDir.path,
          'look_owner_portrait.png',
        );
        await File(portraitPath).writeAsBytes(_realPng(seed: 4));
        final card = CharacterCard(
          name: 'LookOwner',
          imagePath: portraitPath,
        );
        await ctx.repo.addCharacter(card);
        final characterId = card.dbId!;

        final lookId = await ctx.repo.addLook(
          characterId,
          card.name,
          _realPng(seed: 5, width: 30, height: 30),
        );
        expect(lookId, isNotEmpty);

        final looksDir = Directory(
          p.join(ctx.storage.characterBaseDir(card.name).path, 'looks'),
        );
        final lookFiles = looksDir.listSync().whereType<File>().toList();
        expect(lookFiles, hasLength(1));
        final lookFile = lookFiles.first;
        expect(lookFile.existsSync(), isTrue);

        await ctx.repo.removeAvatar(characterId, lookId);

        expect(lookFile.existsSync(), isFalse);
        expect(await ctx.repo.getAvatarImages(characterId), isEmpty);

        await ctx.db.close();
      },
    );

    test(
      'updateAvatarLabel persists a new label that getAvatarImages reflects, '
      'and never touches the file on disk',
      () async {
        final ctx = await _freshRepo();
        final card = CharacterCard(name: 'LabelOwner');
        await ctx.repo.addCharacter(card);
        final characterId = card.dbId!;

        final avatarId = await ctx.repo.addAvatar(
          characterId,
          card.name,
          _realPng(seed: 6),
          'happy',
        );
        var avatars = await ctx.repo.getAvatarImages(characterId);
        expect(avatars.single.label, 'happy');

        await ctx.repo.updateAvatarLabel(avatarId, 'sad');

        avatars = await ctx.repo.getAvatarImages(characterId);
        expect(avatars.single.label, 'sad');

        final avatarsDir = Directory(
          p.join(ctx.storage.characterBaseDir(card.name).path, 'avatars'),
        );
        expect(avatarsDir.listSync().whereType<File>(), hasLength(1));

        await ctx.db.close();
      },
    );

    test(
      'addLook bootstraps a missing portrait on the first call (empty id, '
      'no gallery row written) and only writes a genuine gallery look once '
      'a real portrait is already in place',
      () async {
        final ctx = await _freshRepo();
        final card = CharacterCard(name: 'Portraitless'); // no imagePath yet
        await ctx.repo.addCharacter(card);
        final characterId = card.dbId!;

        final firstId = await ctx.repo.addLook(
          characterId,
          card.name,
          _realPng(seed: 7, width: 18, height: 18),
        );
        // '' is the documented signal: bytes were applied as the portrait,
        // not stored as a gallery row.
        expect(firstId, '');

        final bootstrapped = ctx.repo.characters.firstWhere(
          (c) => c.dbId == characterId,
        );
        expect(bootstrapped.imagePath, isNotNull);
        expect(File(bootstrapped.imagePath!).existsSync(), isTrue);
        expect(await ctx.repo.getAvatarImages(characterId), isEmpty);

        final secondId = await ctx.repo.addLook(
          characterId,
          card.name,
          _realPng(seed: 8, width: 18, height: 18),
        );
        expect(secondId, isNotEmpty);

        final avatars = await ctx.repo.getAvatarImages(characterId);
        expect(avatars, hasLength(1));
        expect(avatars.single.label, AvatarImage.lookLabel);
        final lookFile = File(
          p.join(
            ctx.storage.characterBaseDir(card.name).path,
            'looks',
            avatars.single.filename,
          ),
        );
        expect(lookFile.existsSync(), isTrue);

        await ctx.db.close();
      },
    );

    test(
      'duplicateCharacter with targetDirOverride + skipLibraryInsert clones '
      'the file into the caller-supplied directory under forcedBasename, '
      'writes NO library DB row, and leaves the in-memory list untouched '
      '(the group private-copy path)',
      () async {
        final ctx = await _freshRepo();
        final srcPath = p.join(
          ctx.storage.charactersDir.path,
          'group_source.png',
        );
        await File(srcPath).writeAsBytes(_realPng(seed: 9));
        final card = CharacterCard(
          name: 'GroupSource',
          imagePath: srcPath,
          frontPorchExtensions: FrontPorchExtensions(stableId: 'src-stable'),
        );
        await ctx.repo.addCharacter(card);
        final beforeCount = ctx.repo.characters.length;

        final overrideDir = Directory(
          p.join(ctx.storage.rootPath!, 'groups', 'grp-42', 'avatars'),
        );

        final clone = await ctx.repo.duplicateCharacter(
          card,
          targetDirOverride: overrideDir.path,
          forcedBasename: 'member-uuid-123',
          skipLibraryInsert: true,
        );

        expect(clone, isNotNull);
        expect(clone!.dbId, isNull); // never touched the library DB
        expect(ctx.repo.characters.length, beforeCount); // list untouched

        final expectedPath = p.join(overrideDir.path, 'member-uuid-123.png');
        expect(clone.imagePath, expectedPath);
        expect(File(expectedPath).existsSync(), isTrue);

        // Never leaked into the global library folder under the same name.
        expect(
          File(
            p.join(ctx.storage.charactersDir.path, 'member-uuid-123.png'),
          ).existsSync(),
          isFalse,
        );

        await ctx.db.close();
      },
    );
  });

  group('Gallery bulk delete and Undo', () {
    Future<(CharacterCard, List<String>)> seeded(_Ctx ctx) async {
      final portrait = File(p.join(ctx.storage.charactersDir.path, 'src.png'))
        ..writeAsBytesSync(_realPng(seed: 9));
      final card = CharacterCard(name: 'Bulk Owner');
      final png = p.join(ctx.storage.charactersDir.path, 'Bulk_Owner_1.png');
      await V2CardService().saveCardAsPng(card, png, portrait.path);
      card.imagePath = png;
      await ctx.repo.addCharacter(card);
      final ids = <String>[];
      for (final (i, label) in ['joy', 'sadness', 'anger'].indexed) {
        ids.add(
          await ctx.repo.addAvatar(
            card.dbId!,
            card.name,
            _realPng(seed: i),
            label,
          ),
        );
      }
      return (card, ids);
    }

    test('rows go in one batch, files wait in the hold, and a later add '
        'never repeats an order', () async {
      final ctx = await _freshRepo();
      final (card, ids) = await seeded(ctx);
      final hold = Directory(p.join(ctx.storage.rootPath!, 'hold'));

      final removed = await ctx.repo.batchMedia.removeAvatars(card.dbId!, [
        ids[0],
      ], hold);
      expect(removed.single.id, ids[0]);
      expect(
        File(
          p.join(hold.path, 'avatars', removed.single.filename),
        ).existsSync(),
        isTrue,
        reason: 'held for an Undo, not deleted',
      );

      final added = await ctx.repo.addAvatar(
        card.dbId!,
        card.name,
        _realPng(seed: 7),
        'joy',
      );
      final orders = {
        for (final a in await ctx.repo.getAvatarImages(card.dbId!))
          a.id: a.displayOrder,
      };
      expect(
        orders[added],
        3,
        reason: 'after the last order, not the row count',
      );
      expect(orders.values.toSet().length, orders.length);
      await ctx.db.close();
    });

    test(
      'every new picture gets a file name no other add can repeat',
      () async {
        final ctx = await _freshRepo();
        final (card, ids) = await seeded(ctx);
        final rows = await ctx.repo.getAvatarImages(card.dbId!);
        for (final id in ids) {
          final row = rows.firstWhere((a) => a.id == id);
          expect(
            row.filename,
            contains(id.replaceAll('-', '').substring(0, 8)),
          );
        }
        expect(rows.map((a) => a.filename).toSet().length, rows.length);
        await ctx.db.close();
      },
    );

    test(
      'removing the default and the starred picture fixes both once; '
      'Undo puts back ids, labels, order, the star and the default',
      () async {
        final ctx = await _freshRepo();
        final (card, ids) = await seeded(ctx);
        (card.frontPorchExtensions ??= FrontPorchExtensions())
                .favoriteAvatarId =
            ids[1];
        await ctx.repo.updateCharacter(card, notify: false);
        await ctx.repo.setPrimeAvatar(card.dbId!, 2);
        card.primeAvatarIndex = 2;
        final before = await ctx.repo.getAvatarImages(card.dbId!);

        final removal = await removeGalleryImages(
          repo: ctx.repo,
          storage: ctx.storage,
          card: card,
          ids: [ids[0], ids[1]],
        );
        expect(removal!.count, 2);
        expect(card.frontPorchExtensions!.favoriteAvatarId, isNull);
        expect(card.primeAvatarIndex, 3, reason: 'the first expression left');
        expect(card.avatarImages!.map((a) => a.id), [ids[2]]);
        final starOnDisk = await V2CardService().readCard(card.imagePath!);
        expect(starOnDisk!.frontPorchExtensions?.favoriteAvatarId, isNull);

        final undo = GalleryUndo(repo: ctx.repo, storage: ctx.storage)
          ..hold(removal);
        expect(await undo.restore(removal.batchId, card), isTrue);
        final after = await ctx.repo.getAvatarImages(card.dbId!);
        String key(AvatarImage a) =>
            '${a.id}|${a.label}|${a.displayOrder}|${a.filename}';
        expect(after.map(key).toSet(), before.map(key).toSet());
        for (final a in after) {
          expect(
            File(
              p.join(
                ctx.storage.characterBaseDir(card.name).path,
                'avatars',
                a.filename,
              ),
            ).existsSync(),
            isTrue,
          );
        }
        expect(card.frontPorchExtensions!.favoriteAvatarId, ids[1]);
        expect(card.primeAvatarIndex, 2);
        expect(galleryUndoRoot(ctx.storage).listSync(), isEmpty);
        await ctx.db.close();
      },
    );

    test(
      'an Undo window that closes deletes the held pictures for good',
      () async {
        final ctx = await _freshRepo();
        final (card, ids) = await seeded(ctx);
        final removal = await removeGalleryImages(
          repo: ctx.repo,
          storage: ctx.storage,
          card: card,
          ids: ids,
        );
        final undo = GalleryUndo(
          repo: ctx.repo,
          storage: ctx.storage,
          keep: const Duration(milliseconds: 50),
        )..hold(removal!);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          Directory(
            p.join(galleryUndoRoot(ctx.storage).path, removal.batchId),
          ).existsSync(),
          isFalse,
        );
        expect(await undo.restore(removal.batchId, card), isFalse);
        expect(await ctx.repo.getAvatarImages(card.dbId!), isEmpty);
        expect(card.primeAvatarIndex, 1);
        await ctx.db.close();
      },
    );
  });

  group('Scene pictures follow a rename', () {
    test(
      'a rename into a folder that already exists carries scenes/ too',
      () async {
        final ctx = await _freshRepo();
        final scenes = SceneLibrary(() => ctx.storage.charactersDir);
        await scenes.add('Old Name', _realPng(seed: 1), place: 'porch');
        await scenes.add('New Name', _realPng(seed: 2), place: 'kitchen');

        await ctx.repo.batchMedia.moveMediaFolder('Old Name', 'New Name');

        expect((await scenes.list('New Name')).map((s) => s.name), [
          'kitchen.png',
          'porch.png',
        ]);
        expect(await scenes.list('Old Name'), isEmpty);
        await ctx.db.close();
      },
    );
  });
}
