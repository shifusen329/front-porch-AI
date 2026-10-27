// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The TTS settings dialog's interaction net — required by the god-file
// campaign's provability rule BEFORE tts_settings_dialog.dart is split. Its
// only prior coverage was a golden pumping engine='disabled', in which state
// ~925 of the file's 1,474 lines (all four engine sections) never render at
// all. This net drives the REAL segmented engine selector through all four
// engines and pins a landmark inside each section — the exact code the split
// moves into per-engine part files.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/double_tap.dart';
import '../../helpers/tts_voice_server.dart';

/// The shared fake pins ttsEngine to 'disabled'; the net needs the selector
/// to actually switch sections, so make it mutable + notify like the real
/// StorageService would.
/// The shared fake throws on unknown members; the Kokoro section genuinely
/// asks whether the model is on disk — answer "no" so its Download card
/// renders (the deepest branch the golden never reached).
class _TtsWithModelProbe extends FakeTtsService {
  @override
  Future<bool> isModelDownloaded() async => false;
}

class _StorageWithEngine extends FakeStorageService {
  _StorageWithEngine() {
    ttsSettings.setTtsEngine('kokoro');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the engine selector walks all four engine sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _StorageWithEngine();
    final tts = _TtsWithModelProbe();
    final vm = FakeVoiceManager();
    addTearDown(() {
      storage.dispose();
      tts.dispose();
      vm.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<VoiceManager>.value(value: vm),
        ],
        child: const MaterialApp(home: Material(child: TtsSettingsDialog())),
      ),
    );
    // Bounded pumps, not settle: async voice loads run in initState.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    Future<void> pick(String tab) async {
      await tester.tap(find.textContaining(tab), warnIfMissed: true);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Kokoro is the starting engine — its section renders voices/model card.
    expect(
      find.textContaining('Kokoro'),
      findsWidgets,
      reason: 'Kokoro tab must exist',
    );

    await pick('OpenAI');
    expect(
      find.text('API Key'),
      findsWidgets,
      reason:
          'OpenAI section (its future part file) did not render after '
          'tapping its REAL engine tab',
    );

    await pick('ElevenLabs');
    expect(
      find.text('API Key'),
      findsWidgets,
      reason: 'ElevenLabs section did not render',
    );

    await pick('Piper');
    expect(
      find.text('Browse'),
      findsWidgets,
      reason: 'Piper section (Browse voices button) did not render',
    );

    await pick('Kokoro');
    expect(
      find.text('Browse'),
      findsNothing,
      reason: 'switching back must swap the section out again',
    );
  });

  // The OpenAI section pointed at a custom OpenAI-compatible server offers
  // that server's own voices, read over real HTTP from a loopback server
  // (test/helpers/tts_voice_server.dart). Engine-level pins and the web
  // relay: test/services/tts/openai_voice_list_test.dart.
  testWidgets('a custom OpenAI-compatible server fills the voice picker with '
      'its own voices; Refresh asks it once per double tap; a typed voice id '
      'becomes the voice', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // A real TtsService builds audio players. Headless, their channels
    // answer nothing; each player opens its own event channel once created.
    final messenger = tester.binding.defaultBinaryMessenger;
    void quietEvents(String name) => messenger.setMockStreamHandler(
      EventChannel(name),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    quietEvents('xyz.luan/audioplayers.global/events');
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          quietEvents('xyz.luan/audioplayers/events/$id');
        }
        return null;
      },
    );
    const listPath = '/v1/audio/voices';
    final server = (await tester.runAsync(TtsVoiceServer.start))!;
    server.serveFile(listPath, 'test/fixtures/tts/voices_data_list.json');

    final storage = FakeStorageService();
    storage.ttsSettings
      ..setTtsEngine('openai')
      ..setOpenaiTtsApiKey('sk-test')
      ..setOpenaiTtsBaseUrl(server.baseUrl);
    final vm = FakeVoiceManager();
    final tts = TtsService(storage, vm);
    addTearDown(() {
      tts.dispose();
      storage.dispose();
      vm.dispose();
    });

    // The read runs on real sockets: let them move, then build what came in.
    Future<void> settleUntil(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'the server read never finished');
      await tester.pump();
    }

    // The dialog scrolls; bring each control into view before touching it.
    Future<void> reveal(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<VoiceManager>.value(value: vm),
        ],
        // A page Scaffold under the dialog, as in the app: the Refresh
        // result is a SnackBar.
        child: const MaterialApp(home: Scaffold(body: TtsSettingsDialog())),
      ),
    );
    await settleUntil(
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          tts.activeVoices.isNotEmpty,
    );
    expect(server.hits(listPath), 1, reason: 'opening reads the list');

    final voicePicker = find.ancestor(
      of: find.text('Select a voice'),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await reveal(voicePicker);
    await tester.tap(voicePicker);
    await tester.pumpAndSettle();
    expect(find.text('Willa'), findsWidgets);
    expect(find.text('Orrin'), findsWidgets);
    expect(
      find.text('Coral'),
      findsNothing,
      reason: 'OpenAI names are not offered for another server',
    );
    await tester.tap(find.text('Orrin').last);
    await tester.pumpAndSettle();
    expect(storage.ttsSettings.ttsVoiceModel, 'orrin');

    await reveal(find.text('Refresh'));
    await doubleTapNoFrame(tester, find.text('Refresh'));
    await settleUntil(
      () => find.text('Found 4 voices on the server.').evaluate().isNotEmpty,
    );
    expect(server.hits(listPath), 2, reason: 'a double tap asks once');

    final voiceIdField = find.widgetWithText(
      TextField,
      'Not listed? Type the voice id the server uses',
    );
    await reveal(voiceIdField);
    await tester.enterText(voiceIdField, 'narrator_2');
    await tester.pump();
    expect(storage.ttsSettings.ttsVoiceModel, 'narrator_2');
    expect(find.text('narrator_2 — not in this list'), findsOneWidget);

    // Past the startup read's settle delay, which finds nothing left to ask.
    await tester.pump(const Duration(seconds: 1));
    expect(server.hits(listPath), 2);
  });
}
