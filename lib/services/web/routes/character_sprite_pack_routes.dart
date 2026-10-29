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

/// `POST /api/characters/<id>/avatars/zip`: an emotion-named ZIP sprite pack,
/// the desktop gallery's "Import ZIP sprite pack". Replies with the counts
/// and the character's avatars.
class WebCharacterSpritePackRoutes {
  WebCharacterSpritePackRoutes(this._authoring, Router router) {
    router.post('/api/characters/<id>/avatars/zip', _import);
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
      result = await _authoring.importSpritePack(id, bytes);
    } on FormatException catch (e) {
      return JsonResponse.badRequest("That file isn't a ZIP sprite pack ($e).");
    }
    if (result == null) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok(result);
  }
}
