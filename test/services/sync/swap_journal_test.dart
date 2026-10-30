// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A library swap cut short at every possible move (a crash, or Android
// ending the app) is finished by the startup replay, on real folders.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String root;
  late SharedPreferences prefs;

  File at(String rel) => File(p.joinAll([root, ...rel.split('/')]));

  void write(String rel, String text) => at(rel)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  Future<SwapJournal> plan() async {
    write('KoboldManager/front_porch.db', 'OLD DB');
    write('KoboldManager/front_porch.db-journal', 'OLD JOURNAL');
    write('KoboldManager/Characters/Maple.png', 'OLD MAPLE');
    write('KoboldManager/Characters/Juniper.png', 'JUNIPER');
    write('KoboldManager/sync/in/s1/library.db', 'NEW DB');
    write(
      'KoboldManager/sync/in/s1/files/KoboldManager/Characters/Maple.png',
      'NEW MAPLE',
    );
    write(
      'KoboldManager/sync/in/s1/files/KoboldManager/Characters/Rowan.png',
      'ROWAN',
    );
    final planned = await planLibrarySwap(
      root: root,
      dbPath: at('KoboldManager/front_porch.db').path,
      incomingDb: at('KoboldManager/sync/in/s1/library.db'),
      incomingFiles: {
        'KoboldManager/Characters/Maple.png': at(
          'KoboldManager/sync/in/s1/files/KoboldManager/Characters/Maple.png',
        ),
        'KoboldManager/Characters/Rowan.png': at(
          'KoboldManager/sync/in/s1/files/KoboldManager/Characters/Rowan.png',
        ),
      },
      removePaths: {'KoboldManager/Characters/Juniper.png'},
      finish: (aside) => SwapFinish(
        deviceId: 'device-1',
        prefs: const {'saved_prompts': '["from the other device"]'},
        sourceRoot: root,
        undo: UndoRecord(
          folder: aside,
          at: DateTime(2026, 10, 29),
          device: 'Phone',
        ),
      ),
    );
    return planned.journal;
  }

  void expectSwapped() {
    expect(at('KoboldManager/front_porch.db').readAsStringSync(), 'NEW DB');
    expect(
      at('KoboldManager/front_porch.db-journal').existsSync(),
      isFalse,
      reason: 'an old hot journal beside the new database would roll it back',
    );
    expect(
      at('KoboldManager/Characters/Maple.png').readAsStringSync(),
      'NEW MAPLE',
    );
    expect(
      at('KoboldManager/Characters/Rowan.png').readAsStringSync(),
      'ROWAN',
    );
    expect(at('KoboldManager/Characters/Juniper.png').existsSync(), isFalse);
    expect(
      at('$kAsideFolder/1/db/front_porch.db').readAsStringSync(),
      'OLD DB',
    );
    expect(
      at(
        '$kAsideFolder/1/files/KoboldManager/Characters/Maple.png',
      ).readAsStringSync(),
      'OLD MAPLE',
    );
    expect(
      at(
        '$kAsideFolder/1/files/KoboldManager/Characters/Juniper.png',
      ).readAsStringSync(),
      'JUNIPER',
    );
    expect(SwapJournal.fileIn(root).existsSync(), isFalse);
    expect(prefs.getString('saved_prompts'), '["from the other device"]');
    expect(SyncStateStore(prefs).undo?.folder, '$kAsideFolder/1');
  }

  setUp(() async {
    root = (await Directory.systemTemp.createTemp('fpai_swap_')).path;
    addTearDown(() => Directory(root).delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('an uninterrupted swap moves everything and finishes', () async {
    final journal = await plan();
    await journal.write(root);
    await journal.runMoves(root);
    await journal.complete(root, prefs);
    expectSwapped();
  });

  test(
    'a swap stopped after any move is finished by the startup replay',
    () async {
      final moves = (await plan()).moves.length;
      expect(moves, 7);
      for (var stop = 1; stop <= moves; stop++) {
        await Directory(root).delete(recursive: true);
        await Directory(root).create();
        final journal = await plan();
        await journal.write(root);
        await expectLater(
          journal.runMoves(root, crashAfter: stop),
          throwsA(isA<SwapInterrupted>()),
        );
        expect(
          await replayPendingSwap(root, prefs),
          isTrue,
          reason: 'stopped after move $stop',
        );
        expectSwapped();
      }
    },
  );

  test(
    'a journal torn before the swap started is dropped, moving nothing',
    () async {
      await plan();
      SwapJournal.fileIn(root)
        ..createSync(recursive: true)
        ..writeAsStringSync('{"moves": [["KoboldManager/front');
      expect(await replayPendingSwap(root, prefs), isFalse);
      expect(at('KoboldManager/front_porch.db').readAsStringSync(), 'OLD DB');
      expect(SwapJournal.fileIn(root).existsSync(), isFalse);
    },
  );
}
