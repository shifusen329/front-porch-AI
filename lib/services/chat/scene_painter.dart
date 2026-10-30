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

import 'package:front_porch_ai/services/image/image.dart'
    show ImageGenBackend, kAlreadyGeneratingMessage;
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart'
    show ImagePromptBuilder, cleanNarrativeForVisual;
import 'package:front_porch_ai/services/scenes/scenes.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// A place a chat wants a picture of: [place] at [time], for [owner]'s
/// Scenes, with what the story says about it.
class SceneWant {
  const SceneWant({
    required this.owner,
    required this.place,
    required this.time,
    this.stance = '',
    this.story = '',
    this.setting = '',
    this.names = const [],
  });

  /// The character whose Scenes get the picture, by name.
  final String owner;
  final String place;
  final SceneTime time;

  /// Where the Realism Engine says the character is.
  final String stance;

  /// The reply that put them there, as written.
  final String story;

  /// The owner's scenario: the world the place is in.
  final String setting;

  /// Names kept out of the prompt.
  final List<String> names;

  /// A place gets one picture for the light and one for the dark.
  String get key =>
      '${owner.toLowerCase()}|$place|${time.isDark ? 'dark' : 'light'}';
}

/// Paints the places a chat goes that have no picture, with the image
/// generator the person set up, into the owner's Scenes. One at a time: the
/// newest want waits for the one being painted, and a busy generator (a
/// Studio or `/image` run) is waited for. The library is read again before
/// each painting, so a want already met is never painted twice and a
/// deleted painting is painted again.
class ScenePainter extends ChangeNotifier {
  ScenePainter({
    required this.generator,
    required this.writePrompt,
    required StorageService storage,
    required SceneLibrary library,
    bool Function()? busy,
    DateTime Function()? clock,
  }) : _storage = storage,
       _library = library,
       _busy = busy ?? _never,
       _clock = clock ?? DateTime.now;

  static bool _never() => false;

  /// How long a place that failed is left before it is tried again.
  static const retryAfter = Duration(minutes: 10);

  final ImageGenService? Function() generator;

  /// Asks the side lane for the image prompt; null when it has no answer.
  final Future<String?> Function(String instruction) writePrompt;

  final StorageService _storage;
  final SceneLibrary _library;

  /// A reply is on: nothing starts until it settles and the chat asks again.
  final bool Function() _busy;
  final DateTime Function() _clock;

  SceneWant? _wanted;
  SceneWant? _painting;
  String? _problem;
  bool _running = false;
  Future<void>? _job;
  ImageGenService? _waitingOn;
  final _failedAt = <String, DateTime>{};

  /// The place being painted now.
  SceneWant? get painting => _painting;

  /// Why the last painting failed, until one succeeds.
  String? get problem => _problem;

  /// Completes when the painting under way is done.
  Future<void> get idle => _job ?? Future<void>.value();

  /// Whether a want is painted: Settings → Appearance, and a generator that
  /// is set up and on. Read live.
  bool get canPaint =>
      _storage.expressionSettings.scenePainting &&
      (generator()?.isConfigured ?? false);

  /// The place the chat wants now, or null for none. It replaces any want
  /// still waiting: the story moved on.
  void want(SceneWant? next) {
    _wanted = next;
    _pump();
  }

  void _pump() {
    if (_running || _busy()) return;
    final w = _wanted;
    if (w == null || !canPaint) return;
    final failed = _failedAt[w.key];
    if (failed != null && _clock().difference(failed) < retryAfter) return;
    final images = generator()!;
    if (images.isGenerating) {
      _waitFor(images);
      return;
    }
    _running = true;
    _job = _run(w, images);
  }

  Future<void> _run(SceneWant w, ImageGenService images) async {
    final problemBefore = _problem;
    try {
      final ofPlace = [
        for (final s in await _library.list(w.owner))
          if (s.place == w.place) s,
      ];
      if (!SceneMatcher.needsPainting(ofPlace, w.time)) return;
      _painting = w;
      notifyListeners();
      await _paint(w, images);
    } catch (e) {
      _fail(w, '$e');
    } finally {
      _running = false;
      _job = null;
      if (_painting != null || _problem != problemBefore) {
        _painting = null;
        notifyListeners();
      }
      if (_wanted != null && _wanted!.key != w.key) _pump();
    }
  }

  Future<void> _paint(SceneWant w, ImageGenService images) async {
    final settings = _storage.imageGenSettings;
    final paradigm = settings.imageGenPromptParadigm;
    final tags = paradigm == 'tags';
    final style = ImagePromptBuilder().getStyleSuffix(
      settings.imageGenStyle,
      paradigm,
    );
    var prompt = '';
    try {
      final written = await writePrompt(
        scenePromptInstruction(
          place: w.place,
          stance: w.stance,
          time: w.time,
          setting: w.setting,
          story: cleanNarrativeForVisual(w.story),
          tags: tags,
        ),
      );
      if (written != null) {
        prompt = tags
            ? cleanSceneTags(
                written,
                place: w.place,
                time: w.time,
                names: w.names,
                styleSuffix: style,
              )
            : cleanSceneSentences(written, names: w.names, styleSuffix: style);
      }
    } catch (e) {
      debugPrint('[ScenePainter] No description of the ${w.place}: $e');
    }
    if (prompt.trim().isEmpty) {
      prompt = staticScenePrompt(
        place: w.place,
        time: w.time,
        tags: tags,
        styleSuffix: style,
      );
    }
    final local =
        ImageGenBackend.fromKey(settings.imageGenBackend) !=
        ImageGenBackend.remote;
    debugPrint(
      '[ScenePainter] ${w.owner}: ${w.place} (${w.time.name}) $prompt',
    );
    final bytes = await images.generateImage(
      prompt: prompt,
      negativePrompt: sceneNegative(
        settings.imageGenNegativePrompt,
        tags: tags,
      ),
      size: sceneSize(settings.imageGenSize, local: local),
    );
    if (bytes == null || bytes.isEmpty) {
      // Someone else started first: paint once they are done.
      if (images.statusMessage == kAlreadyGeneratingMessage) {
        _waitFor(images);
        return;
      }
      _fail(w, images.statusMessage);
      return;
    }
    await _library.add(w.owner, bytes, place: w.place, time: w.time);
    _problem = null;
  }

  void _fail(SceneWant w, String reason) {
    _failedAt[w.key] = _clock();
    final why = reason.trim().isEmpty
        ? 'the image generator gave nothing'
        : reason.trim();
    _problem = "Couldn't paint the ${w.place}: $why";
    debugPrint('[ScenePainter] $_problem');
  }

  void _waitFor(ImageGenService images) {
    if (_waitingOn != null) return;
    _waitingOn = images..addListener(_onGenerator);
  }

  void _onGenerator() {
    final images = _waitingOn;
    if (images == null || images.isGenerating) return;
    images.removeListener(_onGenerator);
    _waitingOn = null;
    _pump();
  }

  @override
  void dispose() {
    _waitingOn?.removeListener(_onGenerator);
    _waitingOn = null;
    super.dispose();
  }
}
