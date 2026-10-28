// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the phone shell, driven like a phone. Characters → a card's ⋮ →
// Start New Chat opens a full-screen chat; one tap-tap on Send writes one
// message; the side panel opens over the chat as a sheet and + holds the
// composer's other tools; back closes the chat; the Chats tab lists the
// conversation and tapping it reopens that same chat. All at 412 wide.
//
// On the desktop runner PlatformCaps flips to a phone after boot (the tree
// rebuilds the way a hot reload does); on an Android device or emulator the
// app boots as a phone.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/mobile/mobile.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../test/helpers/double_tap.dart';
import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kName = 'Porch Swing';
const _kGreeting = 'The swing creaks. Sit a spell.';
const _kUserMessage = 'Mind if I join you?';
const _kReplyPieces = ['Pull up the ', 'cushion, it is dry.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phone: start a chat from a card, send once, find it in Chats, '
      'reopen it — sandboxed', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('fpai_phone_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    addTearDown(backend.close);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'phone-model',
    });

    app.main(const []);
    await pumpUntilFound(
      tester,
      find.byWidgetPredicate((w) => w is MainLayout || w is MobileShell),
    );
    if (find.byType(MainLayout).evaluate().isNotEmpty) {
      PlatformCaps.debugOverride = const PlatformCaps(isDesktop: false);
      addTearDown(() => PlatformCaps.debugOverride = PlatformCaps.host());
      await tester.binding.reassembleApplication();
    }
    await pumpUntilFound(tester, find.byType(MobileShell));

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    // At phone width the rail gives way to the bottom bar.
    await tester.pump(const Duration(milliseconds: 800));

    final ctx = tester.element(find.byType(MobileShell));
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(CharacterCard(name: _kName, firstMessage: _kGreeting));
    final d = ChatDriver(tester, chatService, backend);

    // The app opens on Chats; the library is a tab away.
    final nav = find.byType(NavigationBar);
    await tester.tap(
      find.descendant(of: nav, matching: find.text('Characters')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions for $_kName').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start New Chat'));
    // A fresh chat picks its persona first: the seeded default, "User".
    await pumpUntilFound(tester, find.textContaining('Start a new chat with'));

    await tester.tap(
      find
          .descendant(of: find.byType(WarmDialog), matching: find.text('User'))
          .first,
    );
    await pumpUntilFound(tester, find.byType(ChatPage));
    // Full screen: the chat covers the shell's navigation.
    final shellNav = find.byWidgetPredicate(
      (w) => w is NavigationBar || w is NavigationRail,
    );
    expect(shellNav.hitTestable(), findsNothing);

    // The fresh chat is ready once its greeting is in (starting it clears
    // the composer, so typing earlier would be lost).
    await d.waitFor(
      () => chatService.messages.any((m) => m.text.contains('Sit a spell')),
      () => 'the greeting',
    );
    await d.waitSendable();
    // Wait until a tap on Send would land (nothing still covering it), then
    // type and send at once: the chat restores its saved draft as it
    // settles, which would empty a box typed into earlier.
    final send = find.byTooltip('Send message');
    await d.waitFor(() => d.hitReaches(send), () => 'Send to be tappable');
    await tester.enterText(d.input, _kUserMessage);
    await tester.pump();
    expect(tester.widget<TextField>(d.input).controller?.text, _kUserMessage);
    await doubleTapNoFrame(tester, send);
    await d.waitFor(
      () => chatService.messages.any(
        (m) => !m.isUser && m.text.contains('cushion'),
      ),
      () => 'the reply',
    );
    await d.waitSendable();
    expect(
      chatService.messages.where((m) => m.isUser && m.text == _kUserMessage),
      hasLength(1),
      reason: 'one double-tapped Send writes one message',
    );
    final sessionId = chatService.currentSessionId;
    expect(sessionId, isNotNull);
    // The message box keeps most of a phone's width: nothing sits beside it
    // but + and Send.
    expect(tester.getSize(d.input).width, greaterThan(250));

    // The side panel opens over the chat as a sheet, not as a column
    // squeezing it, and back closes it.
    expect(find.byType(ChatResizeSidebar), findsNothing);
    await tester.tap(find.byTooltip('Stats & story'));
    await settleSheet(tester);
    expect(find.byType(SidebarBody), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleSheet(tester);
    expect(find.byType(SidebarBody), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);

    // + holds what the desktop composer shows as buttons.
    await tester.tap(find.byTooltip('Attach and tools'));
    await settleSheet(tester);
    expect(find.text('Persona'), findsOneWidget);
    expect(find.text('Attach photo'), findsOneWidget);
    expect(find.text('Impersonate'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleSheet(tester);
    expect(find.text('Impersonate'), findsNothing);

    await tester.binding.handlePopRoute();
    // The page leaves with its exit transition.
    for (
      var i = 0;
      i < 20 && find.byType(ChatPage).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(ChatPage), findsNothing, reason: 'back closes the chat');

    await tester.tap(find.descendant(of: nav, matching: find.text('Chats')));
    await tester.pumpAndSettle();
    // The row for this chat shows the last thing said. (Starting fresh from
    // a never-opened card also leaves its greeting-only chat in the list.)
    final row = find.ancestor(
      of: find.textContaining('cushion'),
      matching: find.byType(RecentChatRow),
    );
    await pumpUntilFound(tester, row);
    expect(
      find.descendant(of: row, matching: find.text(_kName)),
      findsOneWidget,
      reason: 'the row names who the chat is with',
    );

    await tester.tap(row);
    await pumpUntilFound(tester, find.byType(ChatPage));
    await d.waitSendable();
    expect(chatService.currentSessionId, sessionId);
    expect(
      chatService.messages.where((m) => m.isUser && m.text == _kUserMessage),
      hasLength(1),
    );
  });
}

/// A sheet's open or close animation, without waiting for the chat to stop
/// animating (a streaming transcript never settles).
Future<void> settleSheet(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
