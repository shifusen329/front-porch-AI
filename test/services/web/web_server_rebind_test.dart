// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two teardown/rebind holes in WebServerHost that only bite AFTER something
// else went right or wrong:
//
//  1. A database SWAP (backup restore, storage-root move, beta stable-DB
//     import — all through reopenAndRebindDatabase) closes the old instance and
//     calls setDatabase(newDb). start() had already copied the handle into the
//     shelf handler, every facade and the memoized AuthService, so a running
//     server kept querying the CLOSED database and 500'd on every request.
//  2. start() attaches all its listeners, the 1s heartbeat timer, the StreamHub
//     and the TunnelManager BEFORE it binds, but stop() returned early when
//     `_server` was null — so the cleanup startSafely's catch relies on was a
//     no-op, and every failed bind (the stable+nightly port conflict) leaked a
//     fresh set of them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_webrebind_').path;
        }
        return null;
      });
}

/// A KoboldService that reports how many listeners are currently attached, so
/// the leak is measured rather than inferred.
class _CountingKobold extends KoboldService {
  _CountingKobold(super.storage);

  int attached = 0;

  @override
  void addListener(VoidCallback listener) {
    attached++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    attached--;
    super.removeListener(listener);
  }
}

/// GET the server's public health endpoint, which hits the database through
/// AuthService.isSetupRequired(). Returns the status code (500 when the host is
/// still holding a closed database).
Future<int> _healthStatus(int port) async {
  final client = HttpClient();
  try {
    final req = await client.get('127.0.0.1', port, '/api/health');
    final res = await req.close();
    await res.transform(utf8.decoder).drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The test binding otherwise stubs every HttpClient to a canned 400, which
    // would make the loopback health check meaningless.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(const {});
    _setupPathProviderMock();
  });

  test('a swapped database rebinds the running server instead of 500ing',
      () async {
    final oldDb = AppDatabase.forTesting();
    final storage = StorageService();
    final host = WebServerHost(storage);
    host.setDatabase(oldDb);
    await storage.initialized;

    final newDb = AppDatabase.forTesting();
    addTearDown(() async {
      await host.stop();
      await newDb.close();
    });

    expect(await host.startSafely(0), isTrue);
    final port = host.port;
    expect(await _healthStatus(port), 200);

    // Exactly what reopenAndRebindDatabase does: close the old instance, then
    // hand the host the new one.
    await oldDb.close();
    host.setDatabase(newDb);

    // The bounce is detached (the rebind callers are synchronous), so poll.
    var status = 0;
    for (var i = 0; i < 60 && status != 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        status = await _healthStatus(port);
      } catch (_) {
        status = 0; // Mid-bounce: the socket is briefly gone.
      }
    }

    expect(
      status,
      200,
      reason: 'after a backup restore the web server must serve from the new '
          'database — the old one is closed, so a stale handle 500s forever',
    );
    expect(host.isRunning, isTrue);
    expect(host.port, port, reason: 'the bounce must keep the same address');
  });

  test('a failed bind releases everything start() attached before it', () async {
    final squatter = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final kobold = _CountingKobold(storage);
    final chat = ChatService(
      kobold,
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);

    final host = WebServerHost(storage)
      ..setDatabase(db)
      ..setChatService(chat)
      ..setKoboldService(kobold);

    addTearDown(() async {
      await host.stop();
      chat.dispose();
      await squatter.close();
      await db.close();
    });

    final baseline = kobold.attached;

    for (var attempt = 1; attempt <= 3; attempt++) {
      expect(await host.startSafely(squatter.port), isFalse);
      expect(
        kobold.attached,
        baseline,
        reason: 'attempt $attempt left a generation-status listener attached; '
            'they are unremovable once start() overwrites the field',
      );
      expect(
        host.tunnels,
        isNull,
        reason: 'attempt $attempt left an undisposed TunnelManager, which is '
            'the same teardown block the StreamHub and 1s ticker sit in',
      );
    }
  });

  test(
    'a swapped database keeps the tunnels and the phone client lock',
    () async {
      // A library Get started from the phone swaps the database under the
      // page that asked for it: ngrok must not drop its URL and the desktop's
      // lock overlay must not lift mid-swap.
      final oldDb = AppDatabase.forTesting();
      final storage = StorageService();
      final host = WebServerHost(storage);
      host.setDatabase(oldDb);
      await storage.initialized;
      final newDb = AppDatabase.forTesting();
      addTearDown(() async {
        await host.stop();
        await newDb.close();
      });

      expect(await host.startSafely(0), isTrue);
      final port = host.port;
      final tunnels = host.tunnels;
      expect(tunnels, isNotNull);
      host.markClientActive('100.64.0.2', 'Phone');

      await oldDb.close();
      host.setDatabase(newDb);
      var status = 0;
      for (var i = 0; i < 60 && status != 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          status = await _healthStatus(port);
        } catch (_) {
          status = 0;
        }
      }

      expect(status, 200);
      expect(
        host.tunnels,
        same(tunnels),
        reason: 'the same tunnels, not new ones',
      );
      expect(host.hasActiveClient, isTrue, reason: 'the phone stays connected');
    },
  );
}
