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

import 'package:front_porch_ai/services/services.dart';

/// A character's Scenes for the phone web app: the same [SceneLibrary] the
/// desktop's Scenes dialog edits. Each reply carries the scenes after the
/// change; null means there is no such character (a 404).
class CharacterSceneFacade {
  CharacterSceneFacade(this._repo, this._storage);

  final CharacterRepository _repo;
  final StorageService _storage;

  late final SceneLibrary _library = SceneLibrary(() => _storage.charactersDir);

  Future<String?> _name(String id) async =>
      (await _repo.getCharacterCardById(id))?.name;

  Future<List<Map<String, Object?>>> _json(String name) async => [
    for (final s in await _library.list(name)) s.toJson(),
  ];

  Future<Map<String, Object?>?> list(String id) async {
    final name = await _name(id);
    return name == null ? null : {'scenes': await _json(name)};
  }

  /// Throws [FormatException] for bytes that aren't a picture or a place
  /// that can't name one.
  Future<Map<String, Object?>?> add(
    String id,
    Uint8List bytes, {
    required String place,
    SceneTime? time,
  }) async {
    final name = await _name(id);
    if (name == null) return null;
    final scene = await _library.add(name, bytes, place: place, time: time);
    return {'scenes': await _json(name), 'added': scene.toJson()};
  }

  /// Throws [FormatException] when the file isn't a ZIP.
  Future<Map<String, Object?>?> importZip(String id, Uint8List zip) async {
    final name = await _name(id);
    if (name == null) return null;
    final (:added, :skipped) = await _library.importZip(name, zip);
    return {'added': added, 'skipped': skipped, 'scenes': await _json(name)};
  }

  /// Null when there is no such character or scene.
  Future<Map<String, Object?>?> rename(
    String id,
    String scene, {
    required String place,
    SceneTime? time,
  }) async {
    final name = await _name(id);
    if (name == null) return null;
    final moved = await _library.rename(name, scene, place: place, time: time);
    if (moved == null) return null;
    return {'scenes': await _json(name), 'name': moved.name};
  }

  /// Deletes [scene], or every scene with [clear].
  Future<Map<String, Object?>?> delete(
    String id, {
    String? scene,
    bool clear = false,
  }) async {
    final name = await _name(id);
    if (name == null) return null;
    if (clear) {
      await _library.clear(name);
    } else if (scene != null) {
      await _library.remove(name, scene);
    }
    return {'scenes': await _json(name)};
  }

  Future<File?> image(String id, String scene) async {
    final name = await _name(id);
    if (name == null) return null;
    return (await _library.find(name, scene))?.file;
  }
}
