// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The side panel's Narration section and the strip above the message box,
// driving a real TtsService against a loopback speech server. The script
// is the real narrationLines over the chat's messages; only the wait for a
// long chat's older messages (ChatService.narrationScript) is left out,
// since the chat here is a fake.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/double_tap.dart';
import '../../helpers/tts_test_rig.dart';

Future<(TtsTestRig, FakeChatService)> _pump(
  WidgetTester tester, {
  bool ttsOn = true,
}) async {
  late TtsTestRig rig;
  await tester.runAsync(() async {
    rig = await TtsTestRig.start(gated: true);
    if (!ttsOn) await rig.settings.setTtsEnabled(false);
  });
  final chat = FakeChatService(
    activeCharacter: CharacterCard(name: 'Riley', ttsVoice: kRigCharacterVoice),
    messages: [
      ChatMessage(text: 'Mind if I sit?', sender: 'Wanderer', isUser: true),
      ChatMessage(text: '"Pull up a chair."', sender: 'Riley', isUser: false),
      ChatMessage(
        text: 'The porch light flickers.',
        sender: 'Narrator',
        isUser: true,
        characterId: kDirectorCharacterId,
      ),
    ],
  );
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: rig.storage),
            ChangeNotifierProvider<TtsService>.value(value: rig.tts),
          ],
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: NarrationGroup(
                    chatService: chat,
                    initiallyExpanded: true,
                    onExpansionChanged: (_) {},
                    loadScript: (from) async => narrationLines(
                      chat.messages,
                      base: chat.historyBasePosition,
                      voiceOf: (m) => chat.voiceOf(m, rig.settings),
                      tts: rig.settings,
                      from: from,
                    ),
                  ),
                ),
              ),
              const NarrationStatusBar(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (rig, chat);
}

/// Lets the real speech request and the gated line start.
Future<void> _lineStarts(WidgetTester tester, TtsTestRig rig) =>
    pumpUntilTrue(tester, () => rig.player.playing, 'a line');

Future<void> _endNarration(WidgetTester tester, TtsTestRig rig) async {
  await rig.tts.stop();
  await pumpUntilTrue(
    tester,
    () => !rig.tts.narration.isRunning,
    'the narration to end',
  );
}

final _narrate = find.byKey(const Key('narration-narrate'));
final _strip = find.byKey(const Key('narration-status'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(mockAudioChannels);

  testWidgets('there is no Narration section or strip while text-to-speech '
      'is off', (tester) async {
    await _pump(tester, ttsOn: false);
    expect(find.text('Narration'), findsNothing);
    expect(_narrate, findsNothing);
    expect(_strip, findsNothing);
  });

  testWidgets('Starting at turns the message picker on', (tester) async {
    await _pump(tester);
    DropdownMenu<int> picker() =>
        tester.widget(find.byKey(const Key('narration-from')));
    expect(picker().enabled, isFalse);

    await tester.tap(find.byKey(const Key('narration-start-at')));
    await tester.pump();
    expect(picker().enabled, isTrue);
  });

  testWidgets('Narrate shows the progress in the section and the strip, '
      'and the strip\'s Stop ends it', (tester) async {
    final (rig, _) = await _pump(tester);

    await tester.tap(_narrate);
    await tester.pump();
    await _lineStarts(tester, rig);

    expect(rig.tts.narration.isRunning, isTrue);
    expect(_strip, findsOneWidget);
    expect(
      find.descendant(of: _strip, matching: find.textContaining('of 3')),
      findsOneWidget,
    );
    expect(find.textContaining('Narrating 1 of 3 · #1 Wanderer'), findsWidgets);
    expect(rig.voicesAsked, [kRigUserVoice]);

    await tester.tap(find.descendant(of: _strip, matching: find.text('Stop')));
    await tester.pump();
    expect(rig.tts.narration.isRunning, isFalse);
    expect(_strip, findsNothing);
    expect(_narrate, findsOneWidget);
    await _endNarration(tester, rig);
  });

  testWidgets('a double-tapped Narrate starts one narration', (tester) async {
    final (rig, _) = await _pump(tester);

    await doubleTapNoFrame(tester, _narrate);
    await tester.pump();
    await _lineStarts(tester, rig);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }

    expect(rig.server.requests, hasLength(1), reason: 'one first line asked');
    expect(rig.tts.narration.total, 3);
    await _endNarration(tester, rig);
  });

  testWidgets('Starting at a number reads from that message', (tester) async {
    final (rig, _) = await _pump(tester);

    await tester.tap(find.byKey(const Key('narration-start-at')));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('narration-from')),
        matching: find.byType(TextField),
      ),
      '3',
    );
    await tester.pump();
    // The typed number filters the menu open over the button; close it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tap(_narrate);
    await tester.pump();
    await _lineStarts(tester, rig);

    expect(rig.voicesAsked, [kRigNarratorVoice]);
    expect(rig.tts.narration.total, 1);
    await _endNarration(tester, rig);
  });
}
