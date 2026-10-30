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

import 'package:front_porch_ai/services/chat/lorebook_matcher.dart'
    show fnv1a32;

import 'scene_image.dart';
import 'scene_places.dart';

/// What one location phrase says about the scene.
sealed class PlaceReading {
  const PlaceReading();
}

/// The phrase puts the character in [place], which has a picture.
final class AtPicturedPlace extends PlaceReading {
  const AtPicturedPlace(this.place);
  final String place;
}

/// The phrase names a place there is no picture of.
final class AtOtherPlace extends PlaceReading {
  const AtOtherPlace();
}

/// The phrase names no place ("leaning back, eyes closed").
final class NoPlace extends PlaceReading {
  const NoPlace();
}

/// Reads a location phrase ("sitting on the porch swing") against the
/// places that have pictures. Words only: a place matches on whole words, a
/// plural counts ("porches" yes, "porchlight" no), and the place with the
/// most words wins ("living room" over "room").
abstract final class SceneMatcher {
  /// The pictured place [phrase] puts the character in. Ties go to the
  /// earlier place in [places], so callers list the speaker's own first.
  static PlaceReading read(String phrase, List<String> places) {
    final words = placeWords(phrase);
    if (words.isEmpty) return const NoPlace();
    String? best;
    var bestScore = 0;
    for (final place in places) {
      final score = _score(place, words);
      if (score > bestScore) {
        best = place;
        bestScore = score;
      }
    }
    if (best != null) return AtPicturedPlace(best);
    for (final known in [
      ...kKnownScenePlaces,
      for (final e in kScenePlaceSynonyms.entries) ...[e.key, ...e.value],
    ]) {
      if (_contains(words, placeWords(known))) return const AtOtherPlace();
    }
    return const NoPlace();
  }

  /// How well [place] matches: its own words count double, so a picture
  /// named for the place beats one that only matches through a synonym of
  /// the same length. 0 when it doesn't match.
  static int _score(String place, List<String> words) {
    final own = placeWords(place);
    if (_contains(words, own)) return own.length * 2 + 1;
    var best = 0;
    for (final term in _synonymsOf(place.toLowerCase())) {
      final t = placeWords(term);
      if (_contains(words, t) && t.length * 2 > best) best = t.length * 2;
    }
    return best;
  }

  static Iterable<String> _synonymsOf(String place) sync* {
    yield* kScenePlaceSynonyms[place] ?? const <String>[];
    for (final e in kScenePlaceSynonyms.entries) {
      if (!e.value.contains(place)) continue;
      yield e.key;
      for (final other in e.value) {
        if (other != place) yield other;
      }
    }
  }

  /// Whether [term] appears in [words] as a run, the last word allowed a
  /// plural ending.
  static bool _contains(List<String> words, List<String> term) {
    if (term.isEmpty || term.length > words.length) return false;
    for (var i = 0; i + term.length <= words.length; i++) {
      var ok = true;
      for (var j = 0; j < term.length && ok; j++) {
        final w = words[i + j];
        final t = term[j];
        ok =
            w == t ||
            (j == term.length - 1 &&
                (w == '${t}s' ||
                    w == '${t}es' ||
                    (t.endsWith('y') &&
                        w == '${t.substring(0, t.length - 1)}ies')));
      }
      if (ok) return true;
    }
    return false;
  }

  /// The picture of one place to show at [now]: the exact time, else one
  /// with no time, else the nearest time round the clock (a dark one at
  /// night). Among alternates the pick is stable for [seed], so a rebuild
  /// never shows a different one.
  static SceneImage? pick(
    List<SceneImage> pictures,
    SceneTime now,
    String seed,
  ) {
    if (pictures.isEmpty) return null;
    List<SceneImage> at(SceneTime? t) =>
        pictures.where((s) => s.time == t).toList();
    var choice = at(now);
    if (choice.isEmpty) choice = at(null);
    if (choice.isEmpty) {
      int cost(SceneTime t) {
        final d = (t.index - now.index).abs();
        final around = d > 2 ? 4 - d : d;
        final sameLight = (t.index >= 2) == (now.index >= 2);
        return around * 2 + (sameLight ? 0 : 1);
      }

      final times = {for (final s in pictures) s.time!}.toList()
        ..sort((a, b) => cost(a).compareTo(cost(b)));
      choice = at(times.first);
    }
    choice.sort((a, b) => a.name.compareTo(b.name));
    return choice[fnv1a32(seed) % choice.length];
  }
}
