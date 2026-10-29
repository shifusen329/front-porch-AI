// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Text-to-speech for the user's own lines and Narrate All, against a real
// loopback speech server (test/helpers/speech_server.dart) through the real
// TtsService and OpenAI-compatible engine. Only the audio device is stood
// in for: the player "finishes" a line when the test says so, as the real
// one does when the clip ends or Stop is pressed.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/tts_playback/tts_playback.dart';

import '../../helpers/tts_test_rig.dart';

const _global = kRigGlobalVoice;
const _user = kRigUserVoice;
const _riley = kRigCharacterVoice;
const _narrator = kRigNarratorVoice;

typedef _Rig = TtsTestRig;

Future<_Rig> _rig({bool gated = false}) => TtsTestRig.start(gated: gated);

final _rileyCard = CharacterCard(name: 'Riley', ttsVoice: _riley);

ChatMessage _mine(String text) =>
    ChatMessage(text: text, sender: 'Wanderer', isUser: true);

ChatMessage _hers(String text) =>
    ChatMessage(text: text, sender: 'Riley', isUser: false);

/// #1 a System notice, #2 the user, #3 Riley, #4 the narrator, #5 a status
/// banner, #6 a photo with no words.
List<ChatMessage> _chat() => [
  ChatMessage(text: 'Chat started.', sender: 'System', isUser: false),
  _mine('Mind if I sit a spell?'),
  _hers('"Pull up a chair," she says.'),
  ChatMessage(
    text: 'The porch light flickers.',
    sender: 'Narrator',
    isUser: true,
    characterId: kDirectorCharacterId,
  ),
  ChatMessage(
    text: 'The model server did not answer.',
    sender: 'Riley',
    isUser: false,
    metadata: {kStatusBannerMeta: true},
  ),
  ChatMessage(
    text: '',
    sender: 'Wanderer',
    isUser: true,
    metadata: {'is_user_image': true},
  ),
];

List<NarrationLine> _lines(_Rig rig, {int from = 1, CharacterCard? card}) =>
    narrationLines(
      _chat(),
      base: 0,
      voiceOf: (m) =>
          voiceFor(m, tts: rig.settings, activeCharacter: card ?? _rileyCard),
      tts: rig.settings,
      from: from,
    );

Future<void> _until(bool Function() done, String what) => untilTrue(done, what);

/// Long enough for a request that should not happen to have happened.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(mockAudioChannels);

  group('Narrate All', () {
    test('reads each line in its speaker\'s voice, in chat order, and skips '
        'what is not story', () async {
      final rig = await _rig();
      final lines = _lines(rig);
      expect([for (final l in lines) l.number], [2, 3, 4]);

      await rig.tts.narration.start(lines);

      expect(rig.voicesAsked, [_user, _riley, _narrator]);
      expect(rig.player.played, 3);
      expect(rig.tts.narration.isRunning, isFalse);
      expect(rig.tts.narration.done, 3);
    });

    test('unset voices fall back to the global voice', () async {
      final rig = await _rig();
      await rig.settings.setTtsUserVoice('');
      await rig.settings.setTtsNarratorVoice('');

      await rig.tts.narration.start(
        _lines(rig, card: CharacterCard(name: 'Riley')),
      );

      expect(rig.voicesAsked, [_global, _global, _global]);
    });

    test('Starting at skips earlier lines; quoted-only drops lines with no '
        'quotes from the count', () async {
      final rig = await _rig();
      expect([for (final l in _lines(rig, from: 3)) l.number], [3, 4]);

      await rig.settings.setTtsNarrateQuotedOnly(true);
      expect([for (final l in _lines(rig)) l.number], [3]);
    });

    test('a group reads each member in their own voice', () async {
      final rig = await _rig();
      final sam = CharacterCard(name: 'Sam', ttsVoice: 'sam');
      MessageVoice of(ChatMessage m) => voiceFor(
        m,
        tts: rig.settings,
        groupCharacters: [_rileyCard, sam],
        isGroup: true,
      );
      expect(of(_hers('Hi.')).voiceKey, _riley);
      expect(
        of(ChatMessage(text: 'Hey.', sender: 'Sam', isUser: false)).voiceKey,
        'sam',
      );
      expect(of(_mine('Hello both.')).voiceKey, _user);
    });

    test('Stop ends it', () async {
      final rig = await _rig(gated: true);
      unawaited(rig.tts.narration.start(_lines(rig)));
      await _until(() => rig.player.playing, 'the first line');

      await rig.tts.stop();
      await _settle();

      expect(rig.tts.narration.isRunning, isFalse);
      expect(rig.voicesAsked, [_user]);
    });

    test('a Speak button pressed meanwhile ends it', () async {
      final rig = await _rig(gated: true);
      unawaited(rig.tts.narration.start(_lines(rig)));
      await _until(() => rig.player.playing, 'the first line');

      unawaited(rig.tts.speak('Something else.', voiceKey: _global));
      await _until(() => rig.server.requests.length == 2, 'the other line');
      rig.player.finishLine();
      await _settle();

      expect(rig.tts.narration.isRunning, isFalse);
      expect(rig.voicesAsked, [_user, _global]);
    });

    test('leaving the chat ends it', () async {
      final rig = await _rig(gated: true);
      var open = true;
      unawaited(rig.tts.narration.start(_lines(rig), stillCurrent: () => open));
      await _until(() => rig.player.playing, 'the first line');

      open = false;
      rig.player.finishLine();
      await _until(() => !rig.tts.narration.isRunning, 'the narration to end');
      await _settle();

      expect(rig.voicesAsked, [_user]);
    });

    test('sending a message ends it', () async {
      final rig = await _rig(gated: true);
      unawaited(rig.tts.narration.start(_lines(rig)));
      await _until(() => rig.player.playing, 'the first line');

      final sent = _mine('Never mind that.');
      autoPlaySentLine(
        rig.tts,
        rig.settings,
        line: sent,
        index: 6,
        voice: voiceFor(sent, tts: rig.settings),
        inCall: false,
      );
      await _settle();

      expect(rig.tts.narration.isRunning, isFalse);
      expect(rig.voicesAsked, [_user]);
    });

    test('a line the speech server refuses ends it there', () async {
      final rig = await _rig();
      final lines = _lines(
        rig,
        card: CharacterCard(name: 'Riley', ttsVoice: 'nobody'),
      );

      await rig.tts.narration.start(lines);

      expect(rig.voicesAsked, [_user, 'nobody']);
      expect(rig.tts.lastError, contains('not found'));
      expect(rig.tts.narration.done, 1);
    });
  });

  group('Speak my messages', () {
    void send(_Rig rig, ChatMessage line, {bool inCall = false}) =>
        autoPlaySentLine(
          rig.tts,
          rig.settings,
          line: line,
          index: 1,
          voice: voiceFor(line, tts: rig.settings),
          inCall: inCall,
        );

    void finish(_Rig rig, ChatMessage line) => autoPlayFinishedLine(
      rig.tts,
      rig.settings,
      line: line,
      index: 2,
      voice: voiceFor(line, tts: rig.settings, activeCharacter: _rileyCard),
      inCall: false,
    );

    test('reads the sent line in the user\'s voice, only when on and never '
        'in a voice call', () async {
      final rig = await _rig();
      send(rig, _mine('Evening.'));
      await _settle();
      expect(rig.server.requests, isEmpty, reason: 'off by default');

      await rig.settings.setTtsAutoPlayUser(true);
      send(rig, _mine('Evening.'), inCall: true);
      await _settle();
      expect(rig.server.requests, isEmpty, reason: 'a call speaks itself');

      send(rig, _mine('Evening.'));
      await _until(() => rig.server.requests.isNotEmpty, 'the user line');
      expect(rig.voicesAsked, [_user]);
    });

    test('a finished reply waits for the user\'s own line instead of '
        'cutting it off', () async {
      final rig = await _rig(gated: true);
      await rig.settings.setTtsAutoPlayUser(true);
      await rig.settings.setTtsAutoPlay(true);

      send(rig, _mine('Evening.'));
      await _until(() => rig.player.playing, 'the user line');
      finish(rig, _hers('"Evening yourself."'));
      await _settle();
      expect(rig.voicesAsked, [_user], reason: 'the reply waits its turn');
      expect(rig.player.played, 1);

      rig.player.finishLine();
      await _until(() => rig.server.requests.length == 2, 'the reply');
      expect(rig.voicesAsked, [_user, _riley]);
    });

    test('Stop while a reply waits its turn: the reply is not read', () async {
      final rig = await _rig(gated: true);
      await rig.settings.setTtsAutoPlayUser(true);
      await rig.settings.setTtsAutoPlay(true);

      send(rig, _mine('Evening.'));
      await _until(() => rig.player.playing, 'the user line');
      finish(rig, _hers('"Evening yourself."'));
      await rig.tts.stop();
      await _settle();

      expect(rig.voicesAsked, [_user]);
    });

    test('a line written for the user follows Speak my messages; a narrator '
        'beat follows Auto-Play', () async {
      final rig = await _rig();
      await rig.settings.setTtsAutoPlay(true);

      finish(rig, _mine('I lean on the rail.'));
      await _settle();
      expect(rig.server.requests, isEmpty, reason: 'Speak my messages is off');

      finish(
        rig,
        ChatMessage(
          text: 'Crickets start up.',
          sender: 'Narrator',
          isUser: true,
          characterId: kDirectorCharacterId,
        ),
      );
      await _until(() => rig.server.requests.isNotEmpty, 'the narrator beat');
      expect(rig.voicesAsked, [_narrator]);
    });
  });
}
