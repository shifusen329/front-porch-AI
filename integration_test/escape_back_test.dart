// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: Escape is the app's back key in the real app, as main.dart wires it.
// A sidebar page goes back to the page before it, and a chat goes back to
// the library (its composer lets go of the cursor first when it has it).
// The rules themselves are pinned in test/ui/layout/escape_back_test.dart.
//
// Run it with:
//   flutter test integration_test/escape_back_test.dart -d windows
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _greeting = 'Evening. Pull up a chair.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Escape goes back from a sidebar page and from a chat — '
      'sandboxed', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('fpai_escape_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(
      replyPieces: const ['Glad you came by.'],
    );
    addTearDown(backend.close);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'escape-model',
    });

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    await tester.pump(const Duration(seconds: 2));

    Future<void> escape() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 600));
    }

    final ctx = tester.element(find.byType(MainLayout));
    final appState = Provider.of<AppState>(ctx, listen: false);

    // Home → Manage Models → Settings, then back twice.
    appState
      ..setIndex(2)
      ..setIndex(3);
    await tester.pump(const Duration(milliseconds: 800));
    await escape();
    expect(
      appState.selectedIndex,
      2,
      reason:
          'back to Manage Models (focus: ${FocusManager.instance.primaryFocus})',
    );
    await escape();
    expect(appState.selectedIndex, 0, reason: 'back to Home');

    final character = CharacterCard(
      name: 'Escape Tester',
      description: 'Sits on the porch.',
      firstMessage: _greeting,
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    await Provider.of<ChatService>(
      ctx,
      listen: false,
    ).setActiveCharacter(character);
    // ignore: use_build_context_synchronously — ctx is the root MainLayout element, alive for the whole test.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await pumpUntilFound(
      tester,
      find.textContaining('Pull up a chair', findRichText: true),
    );

    for (var i = 0; i < 2 && find.byType(ChatPage).evaluate().isNotEmpty; i++) {
      await escape();
    }
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(ChatPage), findsNothing, reason: 'the chat went back');
    expect(find.byType(MainLayout), findsOneWidget);
    expect(appState.selectedIndex, 0);
  });
}
