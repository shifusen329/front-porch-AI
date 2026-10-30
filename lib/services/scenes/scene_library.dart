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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/character_store/character_row_codec.dart'
    show mediaFolderName;
import 'package:front_porch_ai/services/zip_images.dart';

import 'scene_image.dart';

/// A character's Scenes library: pictures of places in
/// `Characters/<folder>/scenes/`, each tagged by its file name
/// (`porch.png`, `porch-night.png`, `living-room-2.jpg`). There is no
/// database row; the folder is the library, so Sync and a rename's folder
/// move carry it like the gallery's files.
class SceneLibrary {
  SceneLibrary(this._charactersDir);

  final Directory Function() _charactersDir;

  /// Bumped after every change to any character's scenes, so an open chat
  /// looks again.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  Directory folderFor(String characterName) => Directory(
    p.join(_charactersDir().path, mediaFolderName(characterName), 'scenes'),
  );

  /// The character's scene pictures, by name. Files whose name isn't a
  /// scene are left alone and not listed.
  Future<List<SceneImage>> list(String characterName) async {
    final dir = folderFor(characterName);
    if (!await dir.exists()) return const [];
    final found = <SceneImage>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final scene = SceneImage.parse(e);
      if (scene != null) found.add(scene);
    }
    found.sort((a, b) => a.name.compareTo(b.name));
    return found;
  }

  /// The scene called [name], or null. [name] must be a bare file name.
  Future<SceneImage?> find(String characterName, String name) async {
    if (name.isEmpty || p.basename(name) != name || name.startsWith('.')) {
      return null;
    }
    for (final s in await list(characterName)) {
      if (s.name.toLowerCase() == name.toLowerCase()) return s;
    }
    return null;
  }

  /// Saves [bytes] as a picture of [place] at [time]. A second picture of
  /// the same place and time becomes an alternate (`porch-2.png`). Throws
  /// [FormatException] when the bytes aren't a picture or the place can't
  /// name a file.
  Future<SceneImage> add(
    String characterName,
    Uint8List bytes, {
    required String place,
    SceneTime? time,
  }) async {
    final ext = sniffImageExt(bytes);
    if (ext == null) throw const FormatException('That file is not a picture.');
    final problem = scenePlaceProblem(place);
    if (problem != null) throw FormatException(problem);
    final dir = folderFor(characterName);
    await dir.create(recursive: true);
    final name = await _freeName(characterName, place, time, ext);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    _bump();
    return SceneImage.parse(file)!;
  }

  /// Gives [name] a new place and time. Returns the renamed scene, or null
  /// when there is no such scene. A [FileSystemException] (Windows keeps an
  /// open picture locked) reaches the caller to report.
  Future<SceneImage?> rename(
    String characterName,
    String name, {
    required String place,
    SceneTime? time,
  }) async {
    final scene = await find(characterName, name);
    if (scene == null) return null;
    final problem = scenePlaceProblem(place);
    if (problem != null) throw FormatException(problem);
    final words = placeWords(place).join(' ');
    if (words == scene.place && time == scene.time) return scene;
    final ext = p.extension(scene.name).substring(1).toLowerCase();
    final next = await _freeName(characterName, place, time, ext);
    final moved = await scene.file.rename(p.join(scene.file.parent.path, next));
    _bump();
    return SceneImage.parse(moved);
  }

  /// Deletes the scene called [name]. False when there is none.
  Future<bool> remove(String characterName, String name) async {
    final scene = await find(characterName, name);
    if (scene == null) return false;
    await scene.file.delete();
    _bump();
    return true;
  }

  /// Deletes every scene picture of the character. Returns how many.
  Future<int> clear(String characterName) async {
    var removed = 0;
    for (final s in await list(characterName)) {
      await s.file.delete();
      removed++;
    }
    if (removed > 0) _bump();
    return removed;
  }

  /// Adds every picture in a ZIP named for its place (`porch.png`,
  /// `porch-night.png`, folders allowed). Pictures whose name can't be a
  /// place, or whose bytes aren't a picture, are skipped. Throws
  /// [FormatException] when the file isn't a ZIP.
  Future<({int added, int skipped})> importZip(
    String characterName,
    Uint8List zip,
  ) async {
    // A ZIP starts "PK"; the decoder reads anything else as an empty one.
    if (zip.length < 4 || zip[0] != 0x50 || zip[1] != 0x4B) {
      throw const FormatException('That file is not a ZIP.');
    }
    final List<({String name, Uint8List bytes})> images;
    try {
      images = zipImages(zip).toList();
    } catch (e) {
      throw FormatException('That file is not a ZIP of pictures ($e).');
    }
    var added = 0;
    var skipped = 0;
    for (final image in images) {
      final parsed = SceneImage.parse(File(image.name));
      if (parsed == null || sniffImageExt(image.bytes) == null) {
        skipped++;
        continue;
      }
      try {
        await add(
          characterName,
          image.bytes,
          place: parsed.place,
          time: parsed.time,
        );
        added++;
      } on FormatException {
        skipped++;
      }
    }
    return (added: added, skipped: skipped);
  }

  /// The first name for [place] at [time] no picture has: the plain name,
  /// then `-2`, `-3`… Compared without case, since Windows does.
  Future<String> _freeName(
    String characterName,
    String place,
    SceneTime? time,
    String ext,
  ) async {
    final words = placeWords(place).join(' ');
    final taken = <int>{};
    for (final s in await list(characterName)) {
      if (s.place == words && s.time == time) taken.add(s.alt);
    }
    var alt = 0;
    if (taken.contains(0)) {
      alt = 2;
      while (taken.contains(alt)) {
        alt++;
      }
    }
    return SceneImage.fileName(place, time: time, alt: alt, ext: ext);
  }

  static void _bump() => revision.value++;
}
