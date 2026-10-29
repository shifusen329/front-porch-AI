// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings → Voice & Media → Configure: Speak my messages, Your voice and
// Narrator voice sit under Auto-Play and save what is picked. The voices
// are the real Kokoro catalog the active engine offers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings/tts_settings.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _KokoroStorage extends FakeStorageService {
  _KokoroStorage() {
    ttsSettings
      ..setTtsEngine('kokoro')
      ..setTtsVoiceModel('af_heart');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_KokoroStorage> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _KokoroStorage();
    final tts = TtsService(storage, FakeVoiceManager());
    final vm = FakeVoiceManager();
    addTearDown(() {
      tts.dispose();
      vm.dispose();
      storage.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<VoiceManager>.value(value: vm),
        ],
        child: MaterialApp(home: Material(child: child)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return storage;
  }

  Future<void> choose(WidgetTester tester, Key picker, String voice) async {
    await tester.ensureVisible(find.byKey(picker));
    await tester.tap(find.byKey(picker));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.textContaining(voice).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the TTS settings show them under Auto-Play', (tester) async {
    await pump(tester, const TtsSettingsDialog());
    expect(find.text('Auto-Play'), findsOneWidget);
    expect(find.text('Speak my messages'), findsOneWidget);
    expect(find.text('Your voice'), findsOneWidget);
    expect(find.text('Narrator voice'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Speak my messages')).dy,
      greaterThan(tester.getTopLeft(find.text('Auto-Play')).dy),
    );
  });

  testWidgets('Speak my messages and both voices save what is picked', (
    tester,
  ) async {
    late final _KokoroStorage storage;
    storage = await pump(
      tester,
      SingleChildScrollView(
        child: Builder(
          builder: (context) => UserVoiceSettings(
            settings: Provider.of<StorageService>(context).ttsSettings,
          ),
        ),
      ),
    );
    final s = storage.ttsSettings;
    expect(s.ttsAutoPlayUser, isFalse);
    expect(find.textContaining('Use the global voice'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('tts-speak-my-messages')));
    await tester.pump();
    expect(s.ttsAutoPlayUser, isTrue);

    await choose(tester, const Key('tts-user-voice'), 'Adam');
    expect(s.ttsUserVoice, 'am_adam');

    await choose(tester, const Key('tts-narrator-voice'), 'Bella');
    expect(s.ttsNarratorVoice, 'af_bella');
    expect(s.ttsUserVoice, 'am_adam', reason: 'each picker keeps its own');
  });
}
