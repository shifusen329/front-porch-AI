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

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// The time of day a scene picture shows. A picture without one fits any.
enum SceneTime {
  morning,
  day,
  evening,
  night;

  static SceneTime? fromName(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// The story clock's period (`StoryClock.periodForHour`) as a picture time.
  static SceneTime fromPeriod(String period) => switch (period) {
    'dawn' || 'morning' => morning,
    'evening' => evening,
    'night' => night,
    _ => day,
  };

  /// Evening and night: the dark half of the day. A picture of one stands
  /// in for the other.
  bool get isDark => index >= evening.index;
}

/// Image types a scene picture can be.
const kSceneImageExts = {'png', 'jpg', 'jpeg', 'webp', 'gif'};

/// The file extension the bytes really are, or null when they are not a
/// picture. The pickers hand over bytes without a name.
String? sniffImageExt(Uint8List bytes) {
  bool at(int i, List<int> sig) {
    if (bytes.length < i + sig.length) return false;
    for (var j = 0; j < sig.length; j++) {
      if (bytes[i + j] != sig[j]) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
      at(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }
  return null;
}

final _wordSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _digits = RegExp(r'^\d+$');

/// Names Windows will not create a file under, whatever the extension.
const _reserved = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// The longest place name a scene takes.
const kMaxScenePlaceLength = 60;

/// A place's words, lowercased, with anything that isn't a letter or digit
/// as the gap between them.
List<String> placeWords(String text) => [
  for (final w in text.toLowerCase().split(_wordSplit))
    if (w.isNotEmpty) w,
];

/// Why [place] can't name a scene, or null when it can. A name is read back
/// from the file (`porch-night-2.png`), so a place may not end in a word that
/// would read as the time or the alternate number.
String? scenePlaceProblem(String place) {
  final words = placeWords(place);
  if (words.isEmpty) return 'Name the place, for example "porch".';
  final joined = words.join(' ');
  if (joined.length > kMaxScenePlaceLength) {
    return 'Keep the place under $kMaxScenePlaceLength characters.';
  }
  if (words.length > 1 &&
      (_digits.hasMatch(words.last) ||
          SceneTime.fromName(words.last) != null)) {
    return 'End the place with a word that is not a number or a time of day.';
  }
  if (_reserved.contains(words.join('-'))) {
    return '"$joined" cannot be a file name. Try another word.';
  }
  return null;
}

/// One picture in a character's Scenes library. The file name is the tag:
/// `<place-words>[-<time>][-<n>].<ext>`.
class SceneImage {
  const SceneImage({
    required this.file,
    required this.place,
    this.time,
    this.alt = 0,
  });

  final File file;

  /// The place, lowercase words joined by spaces ("living room").
  final String place;
  final SceneTime? time;

  /// The alternate number (`porch-2.png` is 2); 0 for the first picture.
  final int alt;

  String get name => p.basename(file.path);

  /// Reads a scene from its file name, or null when the name isn't one.
  static SceneImage? parse(File file) {
    final base = p.basename(file.path);
    final dot = base.lastIndexOf('.');
    if (dot <= 0) return null;
    if (!kSceneImageExts.contains(base.substring(dot + 1).toLowerCase())) {
      return null;
    }
    final words = placeWords(base.substring(0, dot));
    var alt = 0;
    if (words.length > 1 && _digits.hasMatch(words.last)) {
      alt = int.parse(words.removeLast());
    }
    SceneTime? time;
    if (words.length > 1) {
      time = SceneTime.fromName(words.last);
      if (time != null) words.removeLast();
    }
    if (words.isEmpty) return null;
    return SceneImage(file: file, place: words.join(' '), time: time, alt: alt);
  }

  /// The file name for a scene. [place] must pass [scenePlaceProblem].
  static String fileName(
    String place, {
    SceneTime? time,
    int alt = 0,
    String ext = 'png',
  }) {
    final parts = [
      ...placeWords(place),
      if (time != null) time.name,
      if (alt > 0) '$alt',
    ];
    return '${parts.join('-')}.$ext';
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'place': place,
    'time': time?.name,
    'alt': alt,
  };
}
