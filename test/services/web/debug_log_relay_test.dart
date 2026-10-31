// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone web app's Settings → Advanced → Debug log, through the app's own
// web server: sign-in, the routes the server mounts and the app's own log,
// kept in a folder of this test's. Signed out it is refused; signed in, the
// switch, the download and Clear do what the desktop card does, and a switch
// that is not true or false changes nothing.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';

class _Reply {
  _Reply(this.status, this.text, this.headers);

  final int status;
  final String text;
  final HttpHeaders headers;

  Map<String, dynamic> get json => jsonDecode(text) as Map<String, dynamic>;
}

class _Client {
  _Client(this.port);

  final int port;
  final _http = HttpClient();
  String? cookie;

  Future<_Reply> send(String method, String path, [Object? body]) async {
    final req = await _http.open(method, '127.0.0.1', port, path);
    if (cookie case final c?) req.headers.set(HttpHeaders.cookieHeader, c);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(body is String ? body : jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    final set = res.headers[HttpHeaders.setCookieHeader];
    if (set != null && set.isNotEmpty) cookie = set.first.split(';').first;
    return _Reply(res.statusCode, text, res.headers);
  }

  void close() => _http.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late WebServerHost host;
  late _Client client;

  setUp(() async {
    // The test binding otherwise stubs every HttpClient to a canned 400.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(const {});
    root = Directory.systemTemp.createTempSync('fpai_debug_relay_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => switch (call.method) {
            'getApplicationDocumentsDirectory' => p.join(root.path, 'docs'),
            'getApplicationSupportDirectory' => p.join(root.path, 'support'),
            _ => null,
          },
        );
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    host = WebServerHost(storage)..setDatabase(db);
    expect(await host.startSafely(0), isTrue);
    client = _Client(host.port);
    addTearDown(() async {
      client.close();
      await host.stop();
      await db.close();
      // Windows will not delete a file the log still holds open.
      if (DebugLog.instance.enabled) await DebugLog.instance.setEnabled(false);
      await DebugLog.instance.clear();
      await root.delete(recursive: true);
    });
  });

  Future<void> signIn() async {
    final reply = await client.send('POST', '/api/auth/setup', {
      'username': 'porch',
      'password': 'porch-password',
    });
    expect(reply.status, 200);
  }

  test('signed out, the log is refused', () async {
    expect((await client.send('GET', '/api/debug-log')).status, 401);
    expect((await client.send('GET', '/api/debug-log/file')).status, 401);
    expect(
      (await client.send('POST', '/api/debug-log', {'enabled': true})).status,
      401,
    );
    expect(DebugLog.instance.enabled, isFalse);
  });

  test('signed in, the phone turns the host log on, downloads it and '
      'clears it', () async {
    await signIn();
    var reply = await client.send('GET', '/api/debug-log');
    expect(reply.status, 200);
    expect(reply.json, {
      'enabled': false,
      'bytes': 0,
      'fileName': DebugLog.fileName,
      'problem': null,
    });
    expect((await client.send('GET', '/api/debug-log/file')).status, 404);

    reply = await client.send('POST', '/api/debug-log', {'enabled': true});
    expect(reply.status, 200);
    expect(reply.json['enabled'], isTrue);
    expect(reply.json['bytes'], greaterThan(0));
    expect(DebugLog.instance.enabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DebugLog.prefKey), isTrue);

    DebugLog.instance.record('[Web] the phone asked for the log');
    reply = await client.send('GET', '/api/debug-log/file');
    expect(reply.status, 200);
    expect(reply.headers.contentType?.mimeType, 'text/plain');
    expect(
      reply.headers.value('content-disposition'),
      'attachment; filename="${DebugLog.fileName}"',
    );
    expect(reply.text, contains('[Web] the phone asked for the log'));

    reply = await client.send('POST', '/api/debug-log/clear');
    expect(reply.status, 200);
    expect(
      await DebugLog.instance.contents(),
      isNot(contains('[Web] the phone asked for the log')),
    );

    reply = await client.send('POST', '/api/debug-log', {'enabled': false});
    expect(reply.json['enabled'], isFalse);
    expect(prefs.getBool(DebugLog.prefKey), isFalse);
  });

  test('a switch that is not true or false changes nothing', () async {
    await signIn();
    for (final bad in <Object?>['yes', 1, null]) {
      final reply = await client.send('POST', '/api/debug-log', {
        'enabled': bad,
      });
      expect(reply.status, 400, reason: '$bad');
    }
    expect(
      (await client.send('POST', '/api/debug-log', '{not json')).status,
      400,
    );
    expect(DebugLog.instance.enabled, isFalse);
  });
}
