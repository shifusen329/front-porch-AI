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

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_store/character_row_codec.dart'
    show mediaFolderName;
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/scenes/scenes.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'group_speaker_resolution.dart';
import 'scene_painter.dart';
import 'stream_tick_notify.dart';

/// The scene picture a chat shows, and whose library it came from.
class SceneShot {
  const SceneShot(this.scene, this.who, this.time);

  final SceneImage scene;

  /// The owner's media folder name (`mediaFolderName`).
  final String who;

  /// The story's time of day when it was picked.
  final SceneTime time;

  /// Names the picture: changes exactly when a different one shows.
  String get key => '$who/${scene.name}';
}

final Expando<SceneBackdrop> _backdrops = Expando('scene backdrop');

/// The chat background that follows the scene. Nothing is stored: the shot
/// is read from where the Realism Engine says the character is (the live
/// stance, then the stance stamped on each reply, newest first), so
/// regenerate, swipe, delete, edit and Continue move it by rewinding or
/// restamping that stance. A phrase that names no place keeps looking back
/// (the scene holds); one that names a place with no picture ends the
/// search (the normal background returns), and that place is painted with
/// the image generator when one is set up ([ScenePainter]).
class SceneBackdrop extends ChangeNotifier {
  SceneBackdrop._(this._chat, this._storage)
    : _library = SceneLibrary(() => _storage.charactersDir) {
    _painter = ScenePainter(
      generator: _generator,
      writePrompt: (instruction) => _chat.writeScenePrompt(instruction),
      storage: _storage,
      library: _library,
      busy: () => _busy,
    )..addListener(notifyListeners);
    _chat.addListener(_onChange);
    _weakListen(this, _storage);
    _weakListen(this, SceneLibrary.revision);
    _onChange();
  }

  /// The one backdrop for [chat]. It lives as long as the chat does.
  static SceneBackdrop of(ChatService chat, StorageService storage) =>
      _backdrops[chat] ??= SceneBackdrop._(chat, storage);

  /// The backdrop [chat] already has, without making one.
  static SceneBackdrop? existing(ChatService chat) => _backdrops[chat];

  /// How far back the replies are read for a place.
  static const lookBack = 40;

  final ChatService _chat;
  final StorageService _storage;
  final SceneLibrary _library;
  late final ScenePainter _painter;

  SceneShot? _current;
  String? _cue;
  bool _reportedBroken = false;
  int _run = 0;
  Future<void>? _pending;

  /// The picture to show, or null for the chat's normal background.
  SceneShot? get current => _current;

  /// Completes once the newest change has been read.
  Future<void> get settled => _pending ?? Future<void>.value();

  /// The place being painted for this chat now.
  SceneWant? get painting => _painter.painting;

  /// Why the last painting failed, until one succeeds.
  String? get problem => _painter.problem;

  /// The painter, for tests to wait on.
  @visibleForTesting
  ScenePainter get painter => _painter;

  /// Changes whenever the shot might: what it is read from, what shows, and
  /// what is being painted. The phone re-reads the scene when it changes.
  String get cue =>
      '${_cue ?? ''}|${_current?.key ?? ''}|'
      '${_painter.painting?.key ?? ''}|${_painter.problem ?? ''}';

  /// A chat stand-in has no generator to paint with.
  ImageGenService? _generator() {
    try {
      return _chat.sceneImageGenerator;
    } catch (_) {
      return null;
    }
  }

  /// Whether this chat follows the scene: the Realism Engine (which reports
  /// where the character is) and the chat's choice, else Settings →
  /// Appearance. Read live, like every per-chat feature gate.
  bool get following =>
      _chat.realismEnabled &&
      (_chat.sessionThemeOverrides.followScene ??
          _storage.expressionSettings.sceneBackgrounds);

  /// A reply, its settle, an import or narration. A class member, so a
  /// chat stand-in answers it too.
  bool get _busy => _chat.isTurnBusy;

  /// Everything the shot depends on, cheap to build. A notification that
  /// leaves it unchanged (most of them) does no file work.
  String _cueNow() {
    final msgs = _chat.messages;
    final last = msgs.isEmpty ? null : msgs.last;
    return [
      _chat.currentSessionId,
      following,
      _painter.canPaint,
      _busy,
      msgs.length,
      // A reload or a restamp keeps the count but brings new messages.
      identityHashCode(last),
      last?.swipeIndex,
      last?.swipes.length,
      for (final m in msgs.reversed.where((m) => !m.isUser).take(1))
        _stampedStance(m),
      _liveStance().text,
      _chat.timeService.timeOfDay,
      for (final p in _chat.cast) p.card.name,
      SceneLibrary.revision.value,
    ].join('|');
  }

  void _onChange() {
    if (StreamTickNotify.active) return;
    final String cue;
    try {
      cue = _cueNow();
    } catch (e) {
      // A scene must never take the chat down with it: show none, say why.
      if (!_reportedBroken) debugPrint('[SceneBackdrop] No scene: $e');
      _reportedBroken = true;
      _publish(null);
      return;
    }
    if (cue == _cue) return;
    _cue = cue;
    if (!following) {
      _run++;
      _publish(null);
      _painter.want(null);
      return;
    }
    // While a reply streams or settles, the stance is the old one; the
    // settle changes the cue and reads again.
    if (_busy) return;
    final run = ++_run;
    final job = _read().then((read) {
      if (run != _run) return;
      _publish(read.shot);
      _painter.want(read.want);
    });
    _pending = job.catchError((Object e) {
      debugPrint('[SceneBackdrop] Could not read the scene: $e');
    });
  }

  void _publish(SceneShot? shot) {
    if (shot?.key == _current?.key) return;
    _current = shot;
    notifyListeners();
  }

  List<CharacterCard> get _castCards => [for (final p in _chat.cast) p.card];

  /// The speaker's live stance: in a group, the member who spoke last.
  ({String text, CharacterCard? who}) _liveStance() {
    final cast = _castCards;
    if (cast.isEmpty) return (text: '', who: null);
    if (!_chat.isGroupMode) {
      return (text: _chat.relationshipService.spatialStance, who: cast.first);
    }
    for (final m in _chat.messages.reversed) {
      if (m.isUser) continue;
      final who = resolveGroupSpeakerForMessage(cast, m, logOnMiss: false);
      if (who != null) {
        return (text: _chat.spatialStanceForGroupCharacter(who), who: who);
      }
    }
    return (text: '', who: null);
  }

  /// The shot to show, and the place to paint (when the painter can).
  Future<({SceneShot? shot, SceneWant? want})> _read() async {
    const none = (shot: null, want: null);
    final cast = _castCards;
    final owners = <CharacterCard, CharacterCard>{};
    final pictures = <String, List<SceneImage>>{};
    for (final c in cast) {
      final owner = _chat.originLibraryCardFor(c) ?? c;
      owners[c] = owner;
      pictures[owner.name] ??= await _library.list(owner.name);
    }
    final paints = _painter.canPaint;
    if (!paints && pictures.values.every((l) => l.isEmpty)) return none;

    final time = SceneTime.fromPeriod(_chat.timeService.timeOfDay);
    final live = _liveStance();
    final replies = _chat.messages.reversed
        .where((m) => !m.isUser)
        .take(lookBack)
        .toList();
    final phrases = [
      (
        text: live.text,
        who: live.who,
        story: replies.firstOrNull?.displayText ?? '',
      ),
      for (final m in replies)
        (text: _stampedStance(m), who: _speaker(cast, m), story: m.displayText),
    ];
    for (final (:text, :who, :story) in phrases) {
      if (text.trim().isEmpty) continue;
      final own = who == null ? null : owners[who]?.name;
      SceneWant? wantFor(String owner, String place) {
        if (!paints) return null;
        final card = owners.values.firstWhere((o) => o.name == owner);
        return SceneWant(
          owner: owner,
          place: place,
          time: time,
          stance: text,
          story: story,
          setting: card.scenario,
          names: [for (final c in cast) c.name],
        );
      }

      final order = [
        ?own,
        for (final f in pictures.keys)
          if (f != own) f,
      ];
      final places = <String>[
        for (final f in order)
          for (final s in pictures[f]!) s.place,
      ];
      switch (SceneMatcher.read(text, places)) {
        case AtPicturedPlace(:final place):
          for (final f in order) {
            final ofPlace = [
              for (final s in pictures[f]!)
                if (s.place == place) s,
            ];
            final seed = '${_chat.currentSessionId}|$place|${time.name}';
            final pick = SceneMatcher.pick(ofPlace, time, seed);
            if (pick != null && await pick.file.exists()) {
              return (
                shot: SceneShot(pick, mediaFolderName(f), time),
                want: SceneMatcher.needsPainting(ofPlace, time)
                    ? wantFor(f, place)
                    : null,
              );
            }
          }
          return none;
        case AtOtherPlace(:final place):
          final owner = own ?? owners.values.firstOrNull?.name;
          return (
            shot: null,
            want: owner == null ? null : wantFor(owner, place),
          );
        case NoPlace():
          continue;
      }
    }
    return none;
  }

  CharacterCard? _speaker(List<CharacterCard> cast, ChatMessage m) =>
      resolveGroupSpeakerForMessage(cast, m, logOnMiss: false) ??
      (cast.isEmpty ? null : cast.first);

  static String _stampedStance(ChatMessage m) {
    final state = m.activeMetadata?['realism_state'];
    if (state is! Map) return '';
    final stance = state['spatialStance'];
    return stance is String ? stance : '';
  }

  /// Listens without the notifier keeping this backdrop (and its chat)
  /// alive: storage and the library revision outlive a chat.
  static void _weakListen(SceneBackdrop backdrop, Listenable source) {
    final ref = WeakReference(backdrop);
    late final VoidCallback listener;
    listener = () {
      final target = ref.target;
      if (target == null) {
        source.removeListener(listener);
      } else {
        target._onChange();
      }
    };
    source.addListener(listener);
  }
}
