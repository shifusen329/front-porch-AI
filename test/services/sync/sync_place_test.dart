// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/webdav_folder_server.dart';

WebDavPlace _place(WebDavFolderServer server, {String? password}) =>
    WebDavPlace(
      serverUrl: server.url,
      username: server.username,
      password: password ?? server.password,
      folder: const ['Front Porch AI Sync', 'FrontPorchAI'],
    );

/// The head-writing contract every place keeps: a first write only when
/// nothing is there, later writes only with the tag that was read.
Future<void> _headContract(SyncPlace place) async {
  expect(await place.readHead(), isNull);
  await place.writeHead(utf8.encode('{"n":1}'), ifTag: null);
  await expectLater(
    place.writeHead(utf8.encode('{"n":2}'), ifTag: null),
    throwsA(isA<HeadChangedException>()),
    reason: 'a first send must not overwrite another device\'s',
  );
  final first = (await place.readHead())!;
  expect(utf8.decode(first.bytes), '{"n":1}');
  await place.writeHead(utf8.encode('{"n":3}'), ifTag: first.tag);
  await expectLater(
    place.writeHead(utf8.encode('{"n":4}'), ifTag: first.tag),
    throwsA(isA<HeadChangedException>()),
    reason: 'a stale tag means another device sent meanwhile',
  );
  expect(utf8.decode((await place.readHead())!.bytes), '{"n":3}');
}

Future<void> _fileContract(SyncPlace place, Directory scratch) async {
  final bytes = List<int>.generate(3 * 1024 * 1024 + 17, (i) => i % 251);
  var sent = 0;
  await place.upload(
    'blobs/ab/abcdef',
    () => Stream.value(bytes),
    bytes.length,
    onBytes: (n) => sent += n,
  );
  expect(sent, bytes.length);
  expect(await place.exists('blobs/ab/abcdef'), isTrue);
  expect(await place.exists('blobs/ab/nothing'), isFalse);
  final dest = File('${scratch.path}/copy.bin');
  var got = 0;
  await place.download('blobs/ab/abcdef', dest, onBytes: (n) => got += n);
  expect(await dest.readAsBytes(), bytes);
  expect(got, bytes.length);
  await expectLater(
    place.download('blobs/ab/nothing', File('${scratch.path}/x')),
    throwsA(
      isA<SyncPlaceException>().having((e) => e.missing, 'missing', isTrue),
    ),
  );
  await place.delete('blobs/ab/abcdef');
  expect(await place.exists('blobs/ab/abcdef'), isFalse);
}

void main() {
  late Directory scratch;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('fpai_sync_place_');
    addTearDown(() => scratch.delete(recursive: true));
  });

  group('WebDAV place', () {
    test('keeps the head contract and round-trips files', () async {
      final server = await WebDavFolderServer.start();
      final place = _place(server);
      addTearDown(place.close);
      await _headContract(place);
      await _fileContract(place, scratch);
      expect(
        server
            .fileAt('Front Porch AI Sync/FrontPorchAI/latest.json')
            .existsSync(),
        isTrue,
        reason:
            'the sync folder and channel folder are created under the user root',
      );
    });

    test('uploads with a Content-Length, never chunked', () async {
      final server = await WebDavFolderServer.start();
      final place = _place(server);
      addTearDown(place.close);
      final bytes = List<int>.filled(70000, 7);
      await place.upload(
        'blobs/cd/cdef',
        () => Stream.value(bytes),
        bytes.length,
      );
      final put = server.requests.lastWhere((r) => r.method == 'PUT');
      expect(put.headers['content-length'], '${bytes.length}');
      expect(put.headers['transfer-encoding'], isNull);
    });

    test('the connection test passes a server that honours If-Match', () async {
      final server = await WebDavFolderServer.start();
      final place = _place(server);
      addTearDown(place.close);
      await place.probe();
      final left = server.root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('probe-'));
      expect(left, isEmpty, reason: 'the probe file is cleaned up');
    });

    test(
      'the connection test refuses a server that ignores If-Match',
      () async {
        final server = await WebDavFolderServer.start();
        server.ignoreConditions = true;
        final place = _place(server);
        addTearDown(place.close);
        await expectLater(
          place.probe(),
          throwsA(
            isA<SyncPlaceException>().having(
              (e) => e.message,
              'message',
              contains('ignores version checks'),
            ),
          ),
        );
      },
    );

    test('a wrong password says so in words', () async {
      final server = await WebDavFolderServer.start();
      final place = _place(server, password: 'wrong');
      addTearDown(place.close);
      await expectLater(
        place.readHead(),
        throwsA(
          isA<SyncPlaceException>().having(
            (e) => e.message,
            'message',
            contains('app password'),
          ),
        ),
      );
    });
  });

  group('Folder place', () {
    test('keeps the head contract and round-trips files', () async {
      final place = FolderPlace(scratch.path, const ['Sync', 'FrontPorchAI']);
      await _headContract(place);
      final work = await Directory('${scratch.path}/work').create();
      await _fileContract(place, work);
    });

    test('a conflict copy left by a sync tool stops the read', () async {
      final place = FolderPlace(scratch.path, const ['Sync', 'FrontPorchAI']);
      await place.writeHead(utf8.encode('{}'), ifTag: null);
      await File(
        '${scratch.path}/Sync/FrontPorchAI/latest (conflicted copy 2026-10-29).json',
      ).writeAsString('{}');
      await expectLater(
        place.readHead(),
        throwsA(
          isA<SyncPlaceException>().having(
            (e) => e.message,
            'message',
            contains('second copy of latest.json'),
          ),
        ),
      );
    });

    test('a blob that has not arrived yet reads as still receiving', () async {
      final place = FolderPlace(scratch.path, const ['Sync', 'FrontPorchAI']);
      await expectLater(
        place.download('blobs/aa/aa', File('${scratch.path}/x')),
        throwsA(
          isA<SyncPlaceException>()
              .having((e) => e.missing, 'missing', isTrue)
              .having((e) => e.message, 'message', contains('still receiving')),
        ),
      );
    });
  });

  final env = Platform.environment;
  final liveUrl = env['SYNC_WEBDAV_URL'];
  test(
    'a real WebDAV server keeps the head contract and round-trips files',
    () async {
      final folder = 'fpai-live-${Random().nextInt(1 << 32).toRadixString(16)}';
      final place = WebDavPlace(
        serverUrl: liveUrl!,
        username: env['SYNC_WEBDAV_USER']!,
        password: env['SYNC_WEBDAV_PASSWORD']!,
        folder: [folder, 'FrontPorchAI'],
      );
      final cleanup = WebDavPlace(
        serverUrl: liveUrl,
        username: env['SYNC_WEBDAV_USER']!,
        password: env['SYNC_WEBDAV_PASSWORD']!,
        folder: const [],
      );
      addTearDown(() async {
        await cleanup.delete('$folder/');
        cleanup.close();
        place.close();
      });
      await place.probe();
      await _headContract(place);
      await _fileContract(place, scratch);
    },
    tags: ['live'],
    skip: liveUrl == null
        ? 'set SYNC_WEBDAV_URL, SYNC_WEBDAV_USER and SYNC_WEBDAV_PASSWORD'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
