// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Sync through the real sync service, sending to a real WebDAV
// server on loopback. Web twin: web_ui/src/components/SyncSettings.test.tsx.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Value, Variable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/settings_page/settings_page.dart';

import '../../helpers/double_tap.dart';
import '../../helpers/sync_test_host.dart';
import '../../helpers/webdav_folder_server.dart';

/// One device: a library in its own folder and database, set up to sync to
/// [dav].
class _Device {
  _Device._(this.db, this.sync);

  final AppDatabase db;
  final LibrarySyncService sync;

  static final _passwords = <String, String>{};

  static Future<_Device> start(WebDavFolderServer dav) async {
    final prefs = await SharedPreferences.getInstance();
    final root = (await Directory.systemTemp.createTemp('fpai_sync_tab_')).path;
    addTearDown(() => Directory(root).delete(recursive: true));
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final sync = LibrarySyncService(
      root: () => root,
      prefs: prefs,
      host: SyncTestHost(db),
      passwords: SyncPasswordStore(
        read: (k) async => _passwords[k],
        write: (k, v) async => _passwords[k] = v,
        delete: (k) async => _passwords.remove(k),
      ),
    );
    await sync.settings.setPlace(
      kind: SyncPlaceKind.webdav,
      serverUrl: dav.url,
      username: dav.username,
    );
    await sync.passwords.save(dav.password);
    return _Device._(db, sync);
  }

  Widget app() => ChangeNotifierProvider.value(
    value: sync,
    child: const MaterialApp(home: Scaffold(body: SyncTab())),
  );
}

Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'timed out waiting');
  await tester.pump();
}

/// Unmounts, closes the service's HTTP client (its keep-alive timer would
/// outlive the test) and lets the snackbars time out.
Future<void> _finish(WidgetTester tester, _Device device) async {
  await tester.pumpWidget(const SizedBox());
  device.sync.dispose();
  await tester.pump(const Duration(seconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        channel,
        (_) async => Directory.systemTemp.createTempSync('fpai_pp_').path,
      );

  late WebDavFolderServer dav;

  Future<_Device> boot(WidgetTester tester) async {
    late _Device device;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      dav = await WebDavFolderServer.start();
      device = await _Device.start(dav);
    });
    return device;
  }

  testWidgets('a double tap on Send my library sends one library', (
    tester,
  ) async {
    final device = await boot(tester);
    await tester.pumpWidget(device.app());
    await _settle(tester, () => !device.sync.busy);

    await tester.scrollUntilVisible(
      find.text('Send my library'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Send my library'));
    await tester.pump();
    await doubleTapNoFrame(tester, find.text('Send my library'));
    await tester.pump();
    await _settle(tester, () => !device.sync.busy);

    final heads = dav.requests.where(
      (r) => r.method == 'PUT' && r.path.endsWith('latest.json'),
    );
    final outcome = device.sync.lastOutcome;
    expect(
      heads,
      hasLength(1),
      reason: outcome is SyncFailed ? outcome.message : '$outcome',
    );
    expect(device.sync.lastOutcome, isA<SyncDone>());
    await _finish(tester, device);
  });

  testWidgets('a Get over changes here asks Keep mine / Take theirs and '
      'names the chat; Keep mine changes nothing', (tester) async {
    late _Device phone;
    late _Device desk;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      dav = await WebDavFolderServer.start();
      desk = await _Device.start(dav);
      await desk.db
          .into(desk.db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's1',
              name: const Value('Porch night'),
            ),
          );
      await desk.db
          .into(desk.db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'm1',
              sessionId: 's1',
              position: 0,
              sender: 'Maple',
              isUser: false,
              swipes: Value(jsonEncode(['Evening.'])),
            ),
          );
      expect(await desk.sync.send(), isA<SyncDone>());
      await desk.db.customUpdate(
        "UPDATE messages SET swipes = ? WHERE id = 'm1'",
        variables: [
          Variable(jsonEncode(['Edited on the desk.'])),
        ],
      );
      SharedPreferences.setMockInitialValues({});
      phone = await _Device.start(dav);
      expect(await phone.sync.send(overwriteTheirs: true), isA<SyncDone>());
    });

    await tester.pumpWidget(desk.app());
    await _settle(tester, () => !desk.sync.busy);
    await tester.scrollUntilVisible(
      find.text('Get the library'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Get the library'));
    await tester.pump();
    await tester.tap(find.text('Get the library'));
    await tester.pump();
    await _settle(
      tester,
      () => find.text('Keep mine or take theirs?').evaluate().isNotEmpty,
    );

    expect(find.textContaining('1 chat (s1)'), findsOneWidget);
    await tester.tap(find.text('Keep mine'));
    await tester.pump();
    await _settle(
      tester,
      () => !desk.sync.busy && desk.sync.pendingGet == null,
    );

    late List<QueryRow> rows;
    await tester.runAsync(() async {
      rows = await desk.db.customSelect('SELECT swipes FROM messages').get();
    });
    expect(rows.single.read<String>('swipes'), contains('Edited on the desk.'));
    await _finish(tester, desk);
    phone.sync.dispose();
  });

  for (final size in const [Size(400, 900), Size(1440, 900), Size(1440, 420)]) {
    testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} window', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final device = await boot(tester);
      await tester.runAsync(() => device.sync.send());
      await tester.pumpWidget(device.app());
      await _settle(tester, () => !device.sync.busy);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Check for a newer library when the app starts'),
        findsOneWidget,
      );
    });
  }
}
