// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Two real libraries on disk sync through a real WebDAV server on loopback:
// A sends, B gets. B's database is the app's singleton, as on a device, so
// the swap closes, moves and reopens a real file.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/sync_test_host.dart';
import '../../helpers/webdav_folder_server.dart';
import '../porch/porch_test_library.dart';

final _passwords = <String, String>{};

SyncPasswordStore _memoryPasswords() => SyncPasswordStore(
  read: (k) async => _passwords[k],
  write: (k, v) async => _passwords[k] = v,
  delete: (k) async => _passwords.remove(k),
);

/// One device: its own prefs instance, library root and sync service.
class _Device {
  _Device(
    this.root,
    this.prefs,
    this.db, {
    ChatService? chat,
    CharacterRepository? repo,
    bool detach = true,
  }) : host = SyncTestHost(db, chat: chat, repo: repo, detach: detach) {
    sync = LibrarySyncService(
      root: () => root,
      prefs: prefs,
      host: host,
      passwords: _memoryPasswords(),
    );
  }

  final String root;
  final SharedPreferences prefs;
  final AppDatabase db;
  final SyncTestHost host;
  late final LibrarySyncService sync;

  Future<void> useServer(WebDavFolderServer server) async {
    await sync.settings.setPlace(
      kind: SyncPlaceKind.webdav,
      serverUrl: server.url,
      username: server.username,
    );
    await sync.passwords.save(server.password);
  }
}

Future<String> _tempRoot(String name) async {
  final dir = await Directory.systemTemp.createTemp('fpai_sync_${name}_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir.path;
}

/// B: an empty library at [root], opened the way the app opens it.
Future<AppDatabase> _openSingletonAt(String root) async {
  SharedPreferences.setMockInitialValues({
    'root_path': root,
    'realism_default': false,
  });
  await AppDatabase.closeAndReset();
  final db = await AppDatabase.instance();
  addTearDown(AppDatabase.closeAndReset);
  return db;
}

/// B as a device: its database opened first, then its own prefs (opening
/// resets the mock prefs, so the order matters).
Future<_Device> _receiver(String root) async {
  final db = await _openSingletonAt(root);
  return _Device(root, await SharedPreferences.getInstance(), db);
}

Future<void> _addChat(
  AppDatabase db, {
  required String sessionId,
  required String characterId,
  required String text,
  String? imagePath,
}) async {
  await db
      .into(db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: sessionId,
          characterId: Value(characterId),
          name: Value('Chat $sessionId'),
        ),
      );
  await db
      .into(db.messages)
      .insert(
        MessagesCompanion.insert(
          id: '$sessionId-m0',
          sessionId: sessionId,
          position: 0,
          sender: 'Maple',
          isUser: false,
          swipes: Value(jsonEncode([text])),
          metadata: Value(
            imagePath == null
                ? null
                : jsonEncode({'is_user_image': true, 'image_path': imagePath}),
          ),
        ),
      );
}

void main() {
  setUpPorchTestPlatform();
  tearDown(BackupService.stopAutoBackup);

  late WebDavFolderServer server;
  late PorchTestLibrary a;
  late _Device sender;

  /// A: Maple with her card, a chat with a photo, a persona whose avatar
  /// lives outside the library, a Data Bank entry, a preset and a background.
  Future<void> seedSender() async {
    server = await WebDavFolderServer.start();
    SharedPreferences.setMockInitialValues({'realism_default': false});
    final prefsA = await SharedPreferences.getInstance();
    final rootA = await _tempRoot('a');
    a = PorchTestLibrary(rootA);
    addTearDown(a.close);
    final maple = await a.seed('Maple', 1);
    final photo = File(p.join(rootA, 'KoboldManager', 'images', 'porch.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(porchTestPicture(2));
    await _addChat(
      a.db,
      sessionId: '1700000000001',
      characterId: maple.dbId!,
      text: 'Evening.',
      imagePath: photo.path,
    );
    final outside = File(p.join(await _tempRoot('outside'), 'me.png'))
      ..writeAsBytesSync(porchTestPicture(3));
    await a.db
        .into(a.db.personas)
        .insert(
          PersonasCompanion.insert(
            id: 'p1',
            name: const Value('Wren'),
            avatarPath: Value(outside.path),
          ),
        );
    await a.db
        .into(a.db.dataBankEntries)
        .insert(
          DataBankEntriesCompanion.insert(
            id: 'd1',
            characterId: 'Maple',
            title: 'Gate',
            content: 'The gate sticks.',
          ),
        );
    await a.db
        .into(a.db.webAuthCredentials)
        .insert(
          WebAuthCredentialsCompanion.insert(
            id: 'local',
            username: 'a-user',
            passwordHash: 'a-hash',
          ),
        );
    final bg = File(p.join(rootA, 'custom_backgrounds', 'bg.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(porchTestPicture(4));
    await prefsA.setString(
      'saved_prompts',
      jsonEncode([
        {'name': 'Porch', 'content': 'Slow and warm.'},
      ]),
    );
    await prefsA.setString(
      'custom_backgrounds',
      jsonEncode([
        {'id': 'b1', 'name': 'Dusk', 'filePath': bg.path},
      ]),
    );
    sender = _Device(rootA, prefsA, a.db);
    await sender.useServer(server);
  }

  group('Send and Get', () {
    test(
      'B gets A\'s whole library, with paths, prefs and files moved onto B',
      () async {
        await seedSender();
        expect(await sender.sync.send(), isA<SyncDone>());

        final rootB = await _tempRoot('b');
        final dbB = await _openSingletonAt(rootB);
        await dbB
            .into(dbB.webAuthCredentials)
            .insert(
              WebAuthCredentialsCompanion.insert(
                id: 'local',
                username: 'b-user',
                passwordHash: 'b-hash',
              ),
            );
        final b = _Device(rootB, await SharedPreferences.getInstance(), dbB);
        await b.useServer(server);

        final ready = await b.sync.prepareGet();
        expect(ready, isA<GetReady>());
        expect(
          (ready as GetReady).conflicts,
          isFalse,
          reason: 'B has no library of its own yet',
        );
        expect(await b.sync.applyGet(), isA<SyncDone>());

        final live = AppDatabase.current!;
        final cards = await live
            .customSelect('SELECT name, image_path FROM characters')
            .get();
        expect(cards.single.read<String>('name'), 'Maple');
        final card = File(
          p.join(
            rootB,
            'KoboldManager',
            'Characters',
            cards.single.read<String>('image_path'),
          ),
        );
        expect(
          card.existsSync(),
          isTrue,
          reason: 'the card PNG carries its settings, so it must arrive',
        );

        final md = await live
            .customSelect('SELECT metadata FROM messages')
            .getSingle();
        final photo =
            (jsonDecode(md.read<String>('metadata')) as Map)['image_path']
                as String;
        expect(photo, p.join(rootB, 'KoboldManager', 'images', 'porch.png'));
        expect(File(photo).readAsBytesSync(), porchTestPicture(2));

        final persona = await live
            .customSelect("SELECT avatar_path FROM personas WHERE id = 'p1'")
            .getSingle();
        final avatar = persona.read<String>('avatar_path');
        expect(p.isWithin(p.join(rootB, 'persona_avatars'), avatar), isTrue);
        expect(File(avatar).readAsBytesSync(), porchTestPicture(3));

        final bank = await live
            .customSelect('SELECT content FROM data_bank_entries')
            .getSingle();
        expect(bank.read<String>('content'), 'The gate sticks.');

        final auth = await live
            .customSelect('SELECT username FROM web_auth_credentials')
            .get();
        expect(auth.map((r) => r.read<String>('username')), [
          'b-user',
        ], reason: 'web logins are this device\'s own and never travel');

        expect(b.prefs.getString('saved_prompts'), contains('Slow and warm.'));
        final bgs =
            jsonDecode(b.prefs.getString('custom_backgrounds')!) as List;
        expect(
          (bgs.single as Map)['filePath'],
          p.join(rootB, 'custom_backgrounds', 'bg.png'),
        );
        expect(
          File(p.join(rootB, 'custom_backgrounds', 'bg.png')).existsSync(),
          isTrue,
        );

        final again = await b.sync.prepareGet();
        expect(again, isA<SyncDone>());
        expect(
          (again as SyncDone).message,
          'Up to date.',
          reason: 'right after a Get, nothing changed here',
        );
      },
    );

    test(
      'a later Get asks Keep mine / Take theirs and names the chat that changed',
      () async {
        await seedSender();
        await sender.sync.send();
        final rootB = await _tempRoot('b');
        final b = await _receiver(rootB);
        await b.useServer(server);
        await b.sync.prepareGet();
        await b.sync.applyGet();

        final live = AppDatabase.current!;
        await live.customUpdate(
          "UPDATE messages SET swipes = ? WHERE session_id = '1700000000001'",
          variables: [
            Variable(jsonEncode(['Edited on B.'])),
          ],
        );
        await a.db.customUpdate(
          "UPDATE data_bank_entries SET content = 'Oiled.'",
        );
        expect(await sender.sync.send(), isA<SyncDone>());

        final ready = await b.sync.prepareGet() as GetReady;
        expect(ready.conflicts, isTrue);
        expect(ready.changes!.sessionIds, ['1700000000001']);
        expect(ready.changedChats, ['1700000000001']);

        await b.sync.discardGet();
        final still = await AppDatabase.current!
            .customSelect('SELECT swipes FROM messages')
            .getSingle();
        expect(
          still.read<String>('swipes'),
          contains('Edited on B.'),
          reason: 'Keep mine changes nothing',
        );
      },
    );

    test('opening a chat and re-saving it unchanged is not a change', () async {
      await seedSender();
      await sender.sync.send();
      final rootB = await _tempRoot('b');
      final b = await _receiver(rootB);
      await b.useServer(server);
      await b.sync.prepareGet();
      await b.sync.applyGet();
      final live = AppDatabase.current!;

      // What opening a chat writes, and a save that rewrites the same
      // messages under fresh ids.
      await live.customUpdate(
        "UPDATE sessions SET updated_at = updated_at + 999",
      );
      await live.customUpdate(
        "UPDATE messages SET id = id || '-again', updated_at = updated_at + 5",
      );
      final quiet = await checkLocalChanges(
        state: b.sync.state,
        root: rootB,
        host: b.host,
        hashes: FileHashCache(rootB),
      );
      expect(quiet.any, isFalse);

      await live
          .into(live.objectives)
          .insert(
            ObjectivesCompanion.insert(
              id: 'q1',
              characterId: 'Maple',
              objective: 'Fix the gate',
            ),
          );
      final changed = await checkLocalChanges(
        state: b.sync.state,
        root: rootB,
        host: b.host,
        hashes: FileHashCache(rootB),
      );
      expect(changed.changes!.areas, contains('quests'));
    });

    test('Undo puts B\'s own library back', () async {
      await seedSender();
      await sender.sync.send();
      final rootB = await _tempRoot('b');
      final dbB = await _openSingletonAt(rootB);
      final b = _Device(rootB, await SharedPreferences.getInstance(), dbB);
      await b.useServer(server);
      await dbB
          .into(dbB.characters)
          .insert(CharactersCompanion.insert(id: 'b1', name: 'Juniper'));
      final own =
          File(p.join(rootB, 'KoboldManager', 'Characters', 'Juniper_1.png'))
            ..createSync(recursive: true)
            ..writeAsBytesSync(porchTestPicture(5));
      await b.prefs.setString('saved_prompts', '[]');

      final ready = await b.sync.prepareGet() as GetReady;
      expect(ready.neverSynced, isTrue, reason: 'B has a library of its own');
      await b.sync.applyGet();
      expect(own.existsSync(), isFalse, reason: 'set aside, not deleted');
      expect(b.sync.undoRecord, isNotNull);

      expect(await b.sync.undo(), isA<SyncDone>());
      final names = await AppDatabase.current!
          .customSelect('SELECT name FROM characters')
          .get();
      expect(names.map((r) => r.read<String>('name')), ['Juniper']);
      expect(own.readAsBytesSync(), porchTestPicture(5));
      expect(b.prefs.getString('saved_prompts'), '[]');
      expect(b.sync.undoRecord, isNull);
      expect(
        Directory(
          p.join(rootB, 'KoboldManager', 'Characters'),
        ).listSync().whereType<File>().map((f) => p.basename(f.path)),
        ['Juniper_1.png'],
        reason: 'what the Get brought in is taken back out',
      );
    });

    test(
      'a chat open on B is closed, not written into the incoming library',
      () async {
        await seedSender();
        await sender.sync.send();
        final rootB = await _tempRoot('b');
        final dbB = await _openSingletonAt(rootB);
        final storageB = StorageService.sandbox(rootB);
        final repoB = CharacterRepository(dbB, storageB);
        final chatB =
            ChatService(
                KoboldService(storageB),
                UserPersonaService(dbB),
                storageB,
                WorldRepository(storageB, dbB),
              )
              ..setDatabase(dbB)
              ..setCharacterRepository(repoB);
        addTearDown(chatB.dispose);
        final willow = CharacterCard(
          name: 'Willow',
          firstMessage: 'Rain on the tin roof.',
        );
        await repoB.addCharacter(willow);
        await chatB.setActiveCharacter(repoB.characters.single);
        await chatB.flushPendingSaves();
        final openSession = chatB.currentSessionId!;

        final b = _Device(
          rootB,
          await SharedPreferences.getInstance(),
          dbB,
          chat: chatB,
          repo: repoB,
        );
        await b.useServer(server);
        await b.sync.prepareGet();
        expect(await b.sync.applyGet(), isA<SyncDone>());
        await chatB.flushPendingSaves();

        final rows = await AppDatabase.current!
            .customSelect(
              'SELECT id FROM sessions WHERE id = ?',
              variables: [Variable(openSession)],
            )
            .get();
        expect(
          rows,
          isEmpty,
          reason: 'B\'s open chat would come back into A\'s library',
        );
      },
    );
  });

  group('Send asks first', () {
    test('when another device sent a library this one has not got', () async {
      await seedSender();
      expect(await sender.sync.send(), isA<SyncDone>());
      final rootB = await _tempRoot('b');
      final b = await _receiver(rootB);
      await b.useServer(server);

      final asked = await b.sync.send();
      expect(asked, isA<SendNeedsChoice>());
      expect(
        (asked as SendNeedsChoice).conflict.kind,
        SendConflictKind.newerHead,
      );

      expect(await b.sync.send(overwriteTheirs: true), isA<SyncDone>());
      final head =
          jsonDecode(
                server
                    .fileAt('Front Porch AI Sync/FrontPorchAI/latest.json')
                    .readAsStringSync(),
              )
              as Map;
      final kept = (head['snapshots'] as List).cast<Map>();
      expect(kept.length, 2);
      expect(
        kept.last['pinned'],
        isTrue,
        reason: 'A\'s library stays, pinned, under Earlier versions',
      );
    });

    test(
      'its own send that crashed before recording is not a conflict',
      () async {
        await seedSender();
        await sender.sync.send();
        final head =
            jsonDecode(
                  server
                      .fileAt('Front Porch AI Sync/FrontPorchAI/latest.json')
                      .readAsStringSync(),
                )
                as Map;
        // As if the app died after the head write, before the record.
        await sender.sync.state.setLastSync(
          LastSync(
            snapshotId: 'older',
            libraryId: head['libraryId'] as String,
            at: DateTime(2026),
            sent: true,
            device: 'A',
          ),
        );
        await sender.sync.state.setPendingSend(head['head'] as String);
        expect(await sender.sync.send(), isA<SyncDone>());
      },
    );
  });

  group('Get refuses', () {
    test('a part missing on the place, leaving B as it was', () async {
      await seedSender();
      await sender.sync.send();
      final blobs = Directory(
        p.join(
          server.root.path,
          'Front Porch AI Sync',
          'FrontPorchAI',
          'blobs',
        ),
      );
      final victim = blobs.listSync(recursive: true).whereType<File>().last;
      victim.deleteSync();

      final rootB = await _tempRoot('b');
      final dbB = await _openSingletonAt(rootB);
      await dbB
          .into(dbB.characters)
          .insert(CharactersCompanion.insert(id: 'b1', name: 'Juniper'));
      final b = _Device(rootB, await SharedPreferences.getInstance(), dbB);
      await b.useServer(server);
      final outcome = await b.sync.prepareGet();
      expect(outcome, isA<SyncFailed>());
      expect(
        (outcome as SyncFailed).message,
        contains('missing on the sync place'),
      );
      final names = await AppDatabase.current!
          .customSelect('SELECT name FROM characters')
          .get();
      expect(names.single.read<String>('name'), 'Juniper');
    });

    test('a snapshot from a newer app', () async {
      await seedSender();
      await sender.sync.send();
      final dir = Directory(
        p.join(
          server.root.path,
          'Front Porch AI Sync',
          'FrontPorchAI',
          'snapshots',
        ),
      );
      final manifest = dir.listSync().whereType<File>().single;
      final json = jsonDecode(manifest.readAsStringSync()) as Map;
      json['schemaVersion'] = 999;
      json['appVersion'] = '9.0.0';
      manifest.writeAsStringSync(jsonEncode(json));

      final rootB = await _tempRoot('b');
      final b = await _receiver(rootB);
      await b.useServer(server);
      final outcome = await b.sync.prepareGet() as SyncFailed;
      expect(outcome.message, contains('Update Front Porch AI here first'));
    });
  });

  group('incoming paths', () {
    test('only library folders, and only names this device can create', () {
      expect(
        incomingPathProblems(['KoboldManager/Characters/Maple_1.png']),
        isEmpty,
      );
      expect(incomingPathProblems(['KoboldManager/../evil.png']), isNotEmpty);
      expect(incomingPathProblems(['models/big.gguf']), isNotEmpty);
      expect(
        incomingPathProblems([
          'KoboldManager/Characters/CON/avatars/a.png',
        ], windowsNames: true),
        [contains('"CON"')],
      );
      expect(
        incomingPathProblems([
          'KoboldManager/Characters/Alice/a.png',
          'KoboldManager/Characters/alice/a.png',
        ], caseInsensitive: true),
        [contains('capital letters')],
      );
    });
  });

  group('path rebase', () {
    test('a Windows library opened on Android, and back', () {
      final toAndroid = PathRebase(
        sourceRoot: r'C:\Users\me\Documents\FrontPorchAI',
        targetRoot:
            '/data/user/0/app.sidepatio.android/app_flutter/FrontPorchAI',
        target: p.posix,
      );
      expect(
        toAndroid.rebase(
          r'c:\users\me\documents\frontporchai\KoboldManager\images\a.png',
        ),
        '/data/user/0/app.sidepatio.android/app_flutter/FrontPorchAI/KoboldManager/images/a.png',
      );
      final toWindows = PathRebase(
        sourceRoot: '/data/data/app.sidepatio.android/app_flutter/FrontPorchAI',
        targetRoot: r'D:\Porch',
        target: p.windows,
      );
      expect(
        toWindows.rebase(
          '/data/user/0/app.sidepatio.android/app_flutter/FrontPorchAI/persona_avatars/me.png',
        ),
        r'D:\Porch\persona_avatars\me.png',
      );
      expect(
        toWindows.rebase(
          '/somewhere/else/FrontPorchAI/KoboldManager/images/b.png',
        ),
        r'D:\Porch\KoboldManager\images\b.png',
        reason:
            'a root the manifest does not name is found by its library folder',
      );
      expect(toWindows.rebase('/etc/hosts'), '/etc/hosts');
      expect(toWindows.rebase('relative.png'), 'relative.png');
    });
  });
  group('Change Data Directory', () {
    test(
      'chat photos and persona avatars follow the library to its new folder',
      () async {
        final oldRoot = await _tempRoot('old');
        final newRoot = await _tempRoot('new');
        SharedPreferences.setMockInitialValues({'root_path': newRoot});
        final file = File(p.join(newRoot, 'KoboldManager', 'front_porch.db'))
          ..parent.createSync(recursive: true);
        var db = AppDatabase.forReunification(file);
        await _addChat(
          db,
          sessionId: 's1',
          characterId: 'c1',
          text: 'Hi.',
          imagePath: p.join(oldRoot, 'KoboldManager', 'images', 'a.png'),
        );
        await db
            .into(db.personas)
            .insert(
              PersonasCompanion.insert(
                id: 'p1',
                avatarPath: Value(p.join(oldRoot, 'persona_avatars', 'me.png')),
              ),
            );
        await db.close();

        await rebaseLibraryAfterMove(oldRoot: oldRoot, newRoot: newRoot);

        db = AppDatabase.forReunification(file);
        addTearDown(db.close);
        final md = await db
            .customSelect('SELECT metadata FROM messages')
            .getSingle();
        expect(
          (jsonDecode(md.read<String>('metadata')) as Map)['image_path'],
          p.join(newRoot, 'KoboldManager', 'images', 'a.png'),
        );
        final persona = await db
            .customSelect("SELECT avatar_path FROM personas WHERE id = 'p1'")
            .getSingle();
        expect(
          persona.read<String>('avatar_path'),
          p.join(newRoot, 'persona_avatars', 'me.png'),
        );
      },
    );
  });
}
