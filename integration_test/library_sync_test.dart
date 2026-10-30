// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: library sync through the real Settings → Sync tab, with a folder as
// the sync place. The app sends its library; a second library (the "other
// device", in this process) sends over it; the app gets that library, which
// replaces its own and closes the open chat; Undo puts its own back.
//
// Run it with:
//   flutter test integration_test/library_sync_test.dart -d windows
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/settings_page.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

/// The other device's library: no chat to close, nothing busy.
class _OtherDevice implements SyncHost {
  _OtherDevice(this.database);

  @override
  final AppDatabase database;

  @override
  List<QuiesceCheck> get quiesceChecks => const [];

  @override
  Future<void> flushSaves() async {}

  @override
  Future<Object?> detachChat() async => null;

  @override
  Future<void> reattachChat(Object? token) async {}

  @override
  void popToRoot() {}

  @override
  Future<bool> rebind() async => true;

  @override
  Future<void> afterSwap() async {}

  @override
  Future<Map<String, String>> chatTitles(List<String> ids) async => const {};
}

/// Sends a library holding only Rowan from its own data folder, as another
/// device would. Prefs are one store per process here, so the app's are set
/// aside for the other device's turn and put back after.
Future<void> _otherDeviceSends(Directory sandbox, String place) async {
  final appPrefs = await SharedPreferences.getInstance();
  final saved = <String, Object>{
    for (final key in appPrefs.getKeys()) key: appPrefs.get(key)!,
  };
  final root = Directory(p.join(sandbox.path, 'other'))
    ..createSync(recursive: true);
  final db = AppDatabase.forReunification(File(p.join(root.path, 'other.db')));
  try {
    await db
        .into(db.characters)
        .insert(CharactersCompanion.insert(id: 'rowan', name: 'Rowan'));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final other = LibrarySyncService(
      root: () => root.path,
      prefs: prefs,
      host: _OtherDevice(db),
    );
    await other.settings.setPlace(
      kind: SyncPlaceKind.folder,
      folderPath: place,
    );
    await other.settings.setDeviceName('Other device');
    final outcome = await other.send(overwriteTheirs: true);
    expect(outcome, isA<SyncDone>(), reason: '$outcome');
    other.dispose();
  } finally {
    await db.close();
    SharedPreferences.setMockInitialValues(saved);
    await SharedPreferences.getInstance();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('send, get another device\'s library over this one, then Undo '
      '— sandboxed', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('fpai_sync_e2e_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: const ['Hi.']);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });
    final place = Directory(p.join(sandbox.path, 'nas'))..createSync();

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final repo = Provider.of<CharacterRepository>(ctx, listen: false);
    final chat = Provider.of<ChatService>(ctx, listen: false);
    final sync = Provider.of<LibrarySyncService>(ctx, listen: false);

    await repo.addCharacter(
      CharacterCard(name: 'Juniper', firstMessage: 'The kettle sings.'),
    );
    await pumpUntilTrue(
      tester,
      () => repo.characters.any((c) => c.name == 'Juniper'),
      describe: () => 'Juniper in the library',
    );
    await chat.setActiveCharacter(
      repo.characters.firstWhere((c) => c.name == 'Juniper'),
    );
    await chat.flushPendingSaves();

    // ── Settings → Sync: a folder as the place ───────────────────────────
    Future<void> openSyncTab() async {
      // ignore: use_build_context_synchronously — root MainLayout element.
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
      await pumpUntilFound(tester, find.text('Sync'));
      await tester.tap(find.text('Sync'));
      await tester.pump(const Duration(milliseconds: 400));
    }

    await openSyncTab();
    await tapWhenHittable(tester, find.text('A folder'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder'),
      place.path,
    );
    await tapWhenHittable(tester, find.text('Save and test connection'));
    await pumpUntilFound(
      tester,
      find.text('Connected. This place can hold your library.'),
    );

    Future<void> tapInTab(String label) async {
      final list = find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(find.text(label), 150, scrollable: list);
      await tester.ensureVisible(find.text(label));
      await tapWhenHittable(tester, find.text(label));
    }

    Future<void> idle(String what) => pumpUntilTrue(
      tester,
      () => !sync.busy,
      describe: () => '$what to finish (phase ${sync.phase.name})',
    );

    // ── Send ─────────────────────────────────────────────────────────────
    await tapInTab('Send my library');
    await idle('the send');
    expect(sync.lastOutcome, isA<SyncDone>(), reason: '${sync.lastOutcome}');

    // ── The other device sends over it ───────────────────────────────────
    await _otherDeviceSends(sandbox, place.path);

    // ── Get: replaces this library and closes the open chat ──────────────
    await tapInTab('Get the library');
    await pumpUntilFound(tester, find.text('Get the library?'));
    await tapWhenHittable(tester, find.text('Get it'));
    await idle('the get');
    expect(sync.lastOutcome, isA<SyncDone>(), reason: '${sync.lastOutcome}');
    await pumpUntilTrue(
      tester,
      () => repo.characters.map((c) => c.name).toList().join() == 'Rowan',
      describe: () =>
          'the library to be Rowan only, is '
          '${repo.characters.map((c) => c.name).toList()}',
    );
    expect(
      chat.activeCharacter?.name,
      isNot('Juniper'),
      reason: 'Juniper\'s chat is not in the library that arrived',
    );

    // The swap leaves every page for the main screen, so nothing open can
    // write into the library that just arrived.
    await pumpUntilTrue(
      tester,
      () => find.byType(SettingsPage).evaluate().isEmpty,
      describe: () => 'Settings to close for the swap',
    );
    expect(sync.undoRecord, isNotNull);

    // ── Undo: this device's own library comes back ───────────────────────
    await openSyncTab();
    await pumpUntilFound(tester, find.textContaining('Undo the Get from'));
    await tapInTab(
      tester.widget<Text>(find.textContaining('Undo the Get from')).data!,
    );
    await pumpUntilFound(tester, find.text('Undo the last Get?'));
    await tapWhenHittable(tester, find.text('Put it back'));
    await idle('the undo');
    await pumpUntilTrue(
      tester,
      () => repo.characters.map((c) => c.name).toList().join() == 'Juniper',
      describe: () =>
          'Juniper back, library is '
          '${repo.characters.map((c) => c.name).toList()}',
    );
    expect(sync.undoRecord, isNull);

    await backend.close();
  });
}
