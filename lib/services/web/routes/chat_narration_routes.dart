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

import 'package:front_porch_ai/services/web/facade/chat_narration_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Narrate All: `GET /api/chat/narration?from=N` gives the open chat's
/// lines from `#N` (1 when absent), each with its voice.
class WebChatNarrationRoutes {
  WebChatNarrationRoutes(this._facade, Router router) {
    router.get('/api/chat/narration', _script);
  }

  final ChatNarrationFacade _facade;

  Future<shelf.Response> _script(shelf.Request r) async {
    final from = int.tryParse(r.url.queryParameters['from'] ?? '') ?? 1;
    return JsonResponse.ok(await _facade.script(from: from < 1 ? 1 : from));
  }
}
