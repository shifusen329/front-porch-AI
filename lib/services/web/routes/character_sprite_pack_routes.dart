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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/character_authoring_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// The gallery's batch routes, the desktop gallery's ZIP import, Delete N,
/// Clear and Undo:
/// - `POST /api/characters/<id>/avatars/zip[?replace=1]`: an emotion-named
///   ZIP sprite pack. Replies with the counts and the character's avatars.
/// - `POST /api/characters/<id>/avatars/delete` with `{ids: [...]}` or
///   `{clear: "expressions" | "looks"}`. Replies with the avatars and an
///   `undo` handle.
/// - `POST /api/characters/<id>/avatars/undo` with `{batch}`: 410 once the
///   window has closed.
class WebCharacterSpritePackRoutes {
  WebCharacterSpritePackRoutes(this._authoring, Router router) {
    router.post('/api/characters/<id>/avatars/zip', _import);
    router.post('/api/characters/<id>/avatars/delete', _delete);
    router.post('/api/characters/<id>/avatars/undo', _undo);
  }

  final CharacterAuthoringFacade _authoring;

  /// A pack with animated expressions runs far past a single upload's cap.
  static const _maxPackBytes = 256 * 1024 * 1024;

  Future<shelf.Response> _import(shelf.Request request, String id) async {
    final List<int> bytes;
    try {
      bytes = await RequestBody.readBytes(request, maxBytes: _maxPackBytes);
    } catch (_) {
      return JsonResponse.error(413, 'File too large');
    }
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    final Map<String, dynamic>? result;
    try {
      result = await _authoring.importSpritePack(
        id,
        bytes,
        replace: request.url.queryParameters['replace'] == '1',
      );
    } on FormatException catch (e) {
      return JsonResponse.badRequest("That file isn't a ZIP sprite pack ($e).");
    }
    if (result == null) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok(result);
  }

  Future<Map<String, dynamic>?> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } on FormatException {
      return null;
    }
  }

  Future<shelf.Response> _delete(shelf.Request request, String id) async {
    final body = await _json(request);
    final ids = body?['ids'];
    final clear = body?['clear'];
    final Map<String, dynamic>? result;
    if (ids is List && ids.isNotEmpty) {
      result = await _authoring.removeAvatars(id, [for (final i in ids) '$i']);
    } else if (clear == 'expressions' || clear == 'looks') {
      result = await _authoring.clearAvatars(id, looks: clear == 'looks');
    } else {
      return JsonResponse.badRequest(
        'Send ids, or clear: "expressions" or "looks".',
      );
    }
    if (result == null) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _undo(shelf.Request request, String id) async {
    final batch = (await _json(request))?['batch'];
    if (batch is! String || batch.isEmpty) {
      return JsonResponse.badRequest('batch is required');
    }
    final result = await _authoring.undoRemoval(id, batch);
    if (result == null) {
      return JsonResponse.error(410, 'It is too late to undo that delete.');
    }
    return JsonResponse.ok(result);
  }
}
