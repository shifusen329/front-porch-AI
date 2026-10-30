// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone web app's /api/sync routes over real HTTP on loopback, sending to
// a real WebDAV server on loopback. Web twin: SyncSettings.test.tsx.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';

import '../../helpers/sync_test_host.dart';
import '../../helpers/webdav_folder_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        channel,
        (_) async => Directory.systemTemp.createTempSync('fpai_pp_').path,
      );

  late AppDatabase db;
  late LibrarySyncService sync;
  late WebDavFolderServer dav;
  late Uri base;
  final passwords = <String, String>{};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    dav = await WebDavFolderServer.start();
    final root = (await Directory.systemTemp.createTemp('fpai_sync_web_')).path;
    addTearDown(() => Directory(root).delete(recursive: true));
    db = AppDatabase.forTesting();
    addTearDown(db.close);
    final auth = AuthService(db);
    expect(
      await auth.setupAccount(
        'admin',
        'password123',
        isDirectLoopbackClient: true,
      ),
      SetupStatus.success,
    );
    sync = LibrarySyncService(
      root: () => root,
      prefs: prefs,
      host: SyncTestHost(db),
      passwords: SyncPasswordStore(
        read: (k) async => passwords[k],
        write: (k, v) async => passwords[k] = v,
        delete: (k) async => passwords.remove(k),
      ),
    );
    final router = Router();
    WebSyncRoutes(SyncFacade(sync), auth, router);
    router.get('/api/characters', (shelf.Request _) => shelf.Response.ok('[]'));
    final handler = const shelf.Pipeline()
        .addMiddleware(librarySyncGate(sync))
        .addHandler(router.call);
    final server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, base.resolve(path));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (
        response.statusCode,
        text.startsWith('{')
            ? jsonDecode(text) as Map<String, dynamic>
            : <String, dynamic>{},
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> idle() async {
    for (var i = 0; i < 200; i++) {
      final (_, status) = await call('GET', '/api/sync');
      if (status['phase'] == 'idle') return status;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('the job never finished');
  }

  test(
    'a new sync password needs the web password; then Send runs as a job',
    () async {
      final place = {
        'kind': 'webdav',
        'serverUrl': dav.url,
        'username': dav.username,
        'password': dav.password,
      };
      final (refused, _) = await call('POST', '/api/sync/settings', place);
      expect(
        refused,
        401,
        reason: 'a sync password is a credential: step-up first',
      );
      expect(passwords, isEmpty);

      final (saved, status) = await call('POST', '/api/sync/settings', {
        ...place,
        'currentPassword': 'password123',
      });
      expect(saved, 200);
      expect(status['configured'], isTrue);
      expect((status['place'] as Map)['passwordSaved'], isTrue);
      expect(
        jsonEncode(status),
        isNot(contains(dav.password)),
        reason: 'the status never carries the password back',
      );

      final (tested, test) = await call('POST', '/api/sync/test', {});
      expect(tested, 200);
      expect(test['ok'], isTrue, reason: '${test['message']}');

      final (started, job) = await call('POST', '/api/sync/send', {});
      expect(started, 200);
      expect(job['started'], isTrue);
      final done = await idle();
      expect((done['outcome'] as Map)['kind'], 'done');
      expect(
        dav.fileAt('Front Porch AI Sync/FrontPorchAI/latest.json').existsSync(),
        isTrue,
      );
    },
  );

  test(
    'while a swap has the database closed, every API call but Sync\'s answers 503',
    () async {
      sync.phase = SyncPhase.replacing;
      addTearDown(() => sync.phase = SyncPhase.idle);
      final (blocked, error) = await call('GET', '/api/characters');
      expect(blocked, 503);
      expect('${error['error']}', contains('being replaced'));
      final (allowed, status) = await call('GET', '/api/sync');
      expect(allowed, 200, reason: 'the phone polls Sync through the swap');
      expect(status['phase'], 'replacing');

      sync.phase = SyncPhase.idle;
      final (open, _) = await call('GET', '/api/characters');
      expect(open, 200);
    },
  );
}
