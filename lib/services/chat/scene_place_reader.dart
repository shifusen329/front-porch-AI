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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/scenes/scenes.dart';
import 'package:front_porch_ai/utils/utils.dart' show stripThinkBlocks;

import 'eval_json_merge.dart' show parseEvalJsonObject;
import 'lorebook_matcher.dart' show fnv1a32;

/// Names the place a reply leaves a character in, with the model: from the
/// Realism Engine's position and the reply itself, whatever place the story
/// reaches. A place that already has a picture is answered with that
/// picture's name, so the picture is reused.
///
/// Each answer is kept by the text it was read from, in memory and in
/// [cacheFile], so the same reply reads the same place after a reload, and
/// a regenerate, swipe or edit (new text) is read again.
class ScenePlaceReader {
  ScenePlaceReader({
    required this.ask,
    required File Function() cacheFile,
    DateTime Function()? clock,
  }) : _cacheFile = cacheFile,
       _clock = clock ?? DateTime.now;

  /// Asks the side lane; null when it has no answer.
  final Future<String?> Function(String instruction) ask;
  final File Function() _cacheFile;
  final DateTime Function() _clock;

  /// How long a text the model gave no place for is left before it is
  /// asked again.
  static const retryAfter = Duration(minutes: 2);

  /// Answers kept in the cache file; the oldest go first.
  static const keep = 500;

  /// How much of the reply the model reads: its end, where they are now.
  static const storyChars = 2000;

  final Map<String, String> _places = {};
  final _unreadable = <String, DateTime>{};
  final _asking = <String, Future<String?>>{};
  Future<void>? _loading;
  Future<void> _saving = Future<void>.value();

  /// The place read before from this text, without asking: a place name,
  /// '' when it shows none, null when it was never read.
  Future<String?> remembered(String stance, String story) async {
    await _load();
    return _places[_key(stance, story)];
  }

  /// The place [who] is in: a place name, '' when the text shows none, or
  /// null when the model gave no usable answer (the caller falls back to
  /// the word list). [pictured] are the places with pictures; [previous] is
  /// the place shown now.
  Future<String?> read({
    required String who,
    required String stance,
    required String story,
    required List<String> pictured,
    String? previous,
  }) async {
    await _load();
    final key = _key(stance, story);
    final known = _places[key];
    if (known != null) return known;
    final failed = _unreadable[key];
    if (failed != null && _clock().difference(failed) < retryAfter) {
      return null;
    }
    // whenComplete's callback is a block, not `=>`: whenComplete waits for a
    // returned future, and the one removed is this very future.
    return _asking[key] ??=
        _ask(
          key,
          scenePlaceInstruction(
            who: who,
            stance: stance,
            story: _tail(story),
            pictured: {for (final p in pictured) p}.toList(),
            previous: previous,
          ),
        ).whenComplete(() {
          _asking.remove(key);
        });
  }

  Future<String?> _ask(String key, String instruction) async {
    String? answer;
    try {
      answer = await ask(instruction);
    } catch (e) {
      debugPrint('[ScenePlace] The model could not be asked: $e');
    }
    final place = answer == null ? null : scenePlaceFromReply(answer);
    if (place == null) {
      _unreadable[key] = _clock();
      if (answer != null) {
        debugPrint('[ScenePlace] Not a place: "${answer.trim()}"');
      }
      return null;
    }
    _places.remove(key);
    _places[key] = place;
    debugPrint('[ScenePlace] ${place.isEmpty ? 'no place' : place}');
    _saving = _saving.then((_) => _save());
    return place;
  }

  static String _key(String stance, String story) {
    final s = stance.trim(), t = _tail(story);
    return '${fnv1a32(s)}-${fnv1a32(t)}-${s.length}-${t.length}';
  }

  static String _tail(String story) {
    final t = story.trim();
    return t.length <= storyChars ? t : t.substring(t.length - storyChars);
  }

  Future<void> _load() => _loading ??= () async {
    final read = await _readFile();
    // Answers given while the file was read are newer.
    _places.addAll({...read, ..._places});
  }();

  Future<Map<String, String>> _readFile() async {
    try {
      final file = _cacheFile();
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      final places = json is Map ? json['places'] : null;
      if (places is! Map) return {};
      return {
        for (final e in places.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (e) {
      debugPrint('[ScenePlace] The place cache could not be read: $e');
      return {};
    }
  }

  /// Writes what this reader knows over what the file has, so another chat's
  /// answers saved meanwhile are kept.
  Future<void> _save() async {
    try {
      final merged = {...await _readFile(), ..._places};
      final kept = merged.entries.skip(
        merged.length > keep ? merged.length - keep : 0,
      );
      final file = _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'places': {for (final e in kept) e.key: e.value},
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('[ScenePlace] The place cache could not be saved: $e');
    }
  }
}

/// The question the side lane answers: where [who] is now, in a few words a
/// picture can be named for.
String scenePlaceInstruction({
  required String who,
  required String stance,
  required String story,
  required List<String> pictured,
  String? previous,
}) => [
  'Where is $who at the end of this reply?',
  'Answer with JSON only: {"place": "<the place>"}. The place is one to '
      'three lowercase words a picture of it could be named for, such as '
      '"stairwell", "school rooftop" or "tavern". Name the place itself, not '
      'a spot in it: "kitchen", not "kitchen counter".',
  if (pictured.isNotEmpty)
    'If it is one of these places, answer with its name exactly: '
        '${pictured.join(', ')}.',
  if (previous != null && previous.isNotEmpty)
    '$who was last in the $previous. If they have not left it, answer '
        '"$previous".',
  'If neither the position nor the reply shows where they are, the place '
      'is "none".',
  '',
  'Position: $stance',
  'Reply: $story',
  '',
  'Place:',
].join('\n');

const _leading = {
  'the', 'a', 'an', 'her', 'his', 'their', 'my', 'our', 'your', 'in', //
  'at', 'on', 'inside', 'place', 'answer',
};
const _trailing = {'at', 'in', 'during', 'by'};
const _noPlace = {'none', 'unknown', 'unclear', 'nowhere', 'n a', 'na'};

/// The place in the model's reply, `{"place": "stairwell"}`, as
/// [scenePlaceFromAnswer] reads it; null when the reply is not that (a chat
/// model talking in character is not a place).
String? scenePlaceFromReply(String reply) {
  final value = parseEvalJsonObject(stripThinkBlocks(reply))?['place'];
  return value is String ? scenePlaceFromAnswer(value) : null;
}

/// The model's answer as a place name: '' when it says there is none, null
/// when the answer is not a place (too long, or no name a file can take).
String? scenePlaceFromAnswer(String answer) {
  final line = answer
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  var words = placeWords(line);
  while (words.isNotEmpty && _leading.contains(words.first)) {
    words = words.sublist(1);
  }
  // "the rooftop at night": the time comes from the story clock.
  while (words.length > 1 &&
      (SceneTime.fromName(words.last) != null ||
          _trailing.contains(words.last))) {
    words = words.sublist(0, words.length - 1);
  }
  if (words.isEmpty) return null;
  final place = words.join(' ');
  if (_noPlace.contains(place)) return '';
  if (words.length > 4 || scenePlaceProblem(place) != null) return null;
  return place;
}
