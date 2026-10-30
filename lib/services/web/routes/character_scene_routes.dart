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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/scenes/scenes.dart';
import 'package:front_porch_ai/services/web/facade/character_scene_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// A character's Scenes, the desktop Scenes dialog's twin. A scene is
/// `{name, place, time, alt}`; every change replies with `scenes`.
/// - `GET /api/characters/<id>/scenes`
/// - `POST /api/characters/<id>/scenes?place=&time=`: the picture's bytes.
/// - `POST /api/characters/<id>/scenes/zip`: pictures named by place.
/// - `POST /api/characters/<id>/scenes/rename` with `{name, place, time}`.
/// - `POST /api/characters/<id>/scenes/delete` with `{name}` or
///   `{clear: true}`.
/// - `GET /api/characters/<id>/scenes/<name>/image[?w=]`
class WebCharacterSceneRoutes {
  WebCharacterSceneRoutes(
    this._scenes,
    Router router, {
    required ThumbnailCache thumbnails,
  }) : _thumbs = thumbnails {
    router.get('/api/characters/<id>/scenes', _list);
    router.post('/api/characters/<id>/scenes', _add);
    router.post('/api/characters/<id>/scenes/zip', _import);
    router.post('/api/characters/<id>/scenes/rename', _rename);
    router.post('/api/characters/<id>/scenes/delete', _delete);
    router.get('/api/characters/<id>/scenes/<name>/image', _image);
  }

  final CharacterSceneFacade _scenes;
  final ThumbnailCache _thumbs;

  /// The same cap as a sprite pack: a pack of wide pictures runs large.
  static const _maxZipBytes = 256 * 1024 * 1024;

  static shelf.Response _reply(Map<String, Object?>? result) => result == null
      ? JsonResponse.error(404, 'Character not found')
      : JsonResponse.ok(result);

  Future<Uint8List?> _bytes(shelf.Request request, int max) async {
    try {
      return Uint8List.fromList(
        await RequestBody.readBytes(request, maxBytes: max),
      );
    } catch (_) {
      return null;
    }
  }

  Future<shelf.Response> _list(shelf.Request request, String id) async =>
      _reply(await _scenes.list(id));

  Future<shelf.Response> _add(shelf.Request request, String id) async {
    final q = request.url.queryParameters;
    final bytes = await _bytes(request, RequestBody.uploadMaxBytes);
    if (bytes == null) return JsonResponse.error(413, 'File too large');
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    try {
      return _reply(
        await _scenes.add(
          id,
          bytes,
          place: q['place'] ?? '',
          time: SceneTime.fromName(q['time']),
        ),
      );
    } on FormatException catch (e) {
      return JsonResponse.badRequest(e.message);
    }
  }

  Future<shelf.Response> _import(shelf.Request request, String id) async {
    final bytes = await _bytes(request, _maxZipBytes);
    if (bytes == null) return JsonResponse.error(413, 'File too large');
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    try {
      return _reply(await _scenes.importZip(id, bytes));
    } on FormatException catch (e) {
      return JsonResponse.badRequest(e.message);
    }
  }

  Future<Map<String, dynamic>?> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } on FormatException {
      return null;
    }
  }

  Future<shelf.Response> _rename(shelf.Request request, String id) async {
    final body = await _json(request);
    final name = body?['name'];
    final place = body?['place'];
    if (name is! String || place is! String) {
      return JsonResponse.badRequest('Send name and place.');
    }
    try {
      final result = await _scenes.rename(
        id,
        name,
        place: place,
        time: SceneTime.fromName('${body?['time']}'),
      );
      if (result == null) return JsonResponse.error(404, 'No such scene');
      return JsonResponse.ok(result);
    } on FormatException catch (e) {
      return JsonResponse.badRequest(e.message);
    } on FileSystemException {
      return JsonResponse.error(409, 'That picture is in use. Try again.');
    }
  }

  Future<shelf.Response> _delete(shelf.Request request, String id) async {
    final body = await _json(request);
    final name = body?['name'];
    final clear = body?['clear'] == true;
    if (!clear && name is! String) {
      return JsonResponse.badRequest('Send name, or clear: true.');
    }
    try {
      return _reply(
        await _scenes.delete(id, scene: name as String?, clear: clear),
      );
    } on FileSystemException {
      return JsonResponse.error(409, 'That picture is in use. Try again.');
    }
  }

  Future<shelf.Response> _image(
    shelf.Request request,
    String id,
    String name,
  ) async => _thumbs.serve(
    request,
    await _scenes.image(id, Uri.decodeComponent(name)),
  );
}
