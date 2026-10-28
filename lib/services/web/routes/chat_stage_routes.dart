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

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chat_stage_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Visual novel endpoints: the open chat's stage, and each figure's picture.
class WebChatStageRoutes {
  WebChatStageRoutes(this._facade, Router router) {
    router.get('/api/chat/stage', _snapshot);
    router.get('/api/chat/stage/<id>', _image);
  }

  final ChatStageFacade _facade;

  static const _types = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.gif': 'image/gif',
  };

  shelf.Response _snapshot(shelf.Request r) =>
      JsonResponse.ok(_facade.snapshot());

  Future<shelf.Response> _image(shelf.Request r, String id) async {
    final file = _facade.image(Uri.decodeComponent(id));
    if (file == null) return shelf.Response.notFound('No picture on stage');
    return shelf.Response.ok(
      await file.readAsBytes(),
      headers: {
        'Content-Type':
            _types[p.extension(file.path).toLowerCase()] ??
            'application/octet-stream',
        // The page asks with ?v=<file name>, which changes with the picture.
        'Cache-Control': 'private, max-age=3600',
      },
    );
  }
}
