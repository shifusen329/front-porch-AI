// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Scene backgrounds, end to end in the real app: a character with a porch
// picture in their Scenes, a chat with the Realism Engine on, and the
// background following where the posture pass says they are. Out on the
// porch, the porch picture fades in; into the kitchen (no picture), the
// chat's own background returns; delete that reply and the porch is back.
// The fake backend only gives the posture (fake_backend.dart
// scenePostureFor); the app reads it, picks the picture and draws it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show SceneBackdrop;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'The lemonade is cold and the evening is long.';
const _kReplyPieces = ['Mm, ', 'this way.'];

/// Keep in sync with fake_backend.dart scenePostureFor.
const _kPorch = 'out on the porch';
const _kKitchen = 'into the kitchen';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the background follows the character to the porch, lets go '
      'in the kitchen, and comes back when that reply is deleted', (
    tester,
  ) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail('Something is listening on 127.0.0.1:5001 — close it first.');
    } on SocketException {
      // Safe.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_scenes_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    addTearDown(() async => backend.close());
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

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
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final storage = Provider.of<StorageService>(ctx, listen: false);

    final character = CharacterCard(
      name: 'Mabel',
      description: 'Exists only inside the scene backgrounds E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    final porch = img.Image(width: 64, height: 40);
    img.fill(porch, color: img.ColorRgb8(200, 150, 90));
    await SceneLibrary(
      () => storage.charactersDir,
    ).add('Mabel', img.encodePng(porch), place: 'porch');
    await chatService.setActiveCharacter(character);

    // ignore: use_build_context_synchronously — ctx is the root element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(d.input);
    final porchShown = find.byKey(const ValueKey('scene:Mabel/porch.png'));
    final backdrop = SceneBackdrop.of(chatService, storage);

    // ── Out on the porch: the porch picture fades in ─────────────────────
    await d.sendMessage('Let us sit $_kPorch where it is cooler.');
    await d.waitSendable();
    await d.waitForWidget(porchShown, timeout: const Duration(seconds: 30));
    expect(backdrop.current?.scene.place, 'porch');

    // ── Into the kitchen: no picture, so the chat's own background ───────
    await d.sendMessage('Come $_kKitchen, I will pour you another glass.');
    await d.waitSendable();
    await d.waitFor(
      () => porchShown.evaluate().isEmpty,
      () => 'the porch to fade out (scene=${backdrop.current?.key})',
      timeout: const Duration(seconds: 30),
    );
    expect(backdrop.current, isNull);

    // ── Delete the kitchen reply: the stance rewinds, the porch returns ──
    final reply = chatService.messages.last;
    expect(reply.isUser, isFalse);
    final count = chatService.messages.length;
    for (
      var attempt = 0;
      attempt < 6 && find.text('Delete Message').evaluate().isEmpty;
      attempt++
    ) {
      final bubble = await d.revealBubbleFor(reply);
      final delete = find.descendant(
        of: bubble,
        matching: find.byIcon(Icons.delete_outline),
      );
      if (delete.evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 250));
        continue;
      }
      await tester.ensureVisible(delete.first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(delete.first, warnIfMissed: false);
      for (
        var i = 0;
        i < 6 && find.text('Delete Message').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    await d.waitForWidget(find.text('Delete Message'));
    await tester.tap(find.text('Delete'));
    await d.waitFor(
      () => chatService.messages.length == count - 1,
      () => 'the delete to land (messages=${chatService.messages.length})',
      timeout: const Duration(seconds: 15),
    );
    await d.waitForWidget(porchShown, timeout: const Duration(seconds: 30));
    expect(backdrop.current?.scene.place, 'porch');
  });
}
