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

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/debug_log/debug_log.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// The phone web app's Settings → Advanced → Debug log: the host's switch,
/// how big the log is, a download of it, and Clear. Same log and the same
/// calls as the desktop card.
class WebDebugLogRoutes {
  WebDebugLogRoutes(this._log, Router router) {
    router.get('/api/debug-log', _status);
    router.post('/api/debug-log', _set);
    router.get('/api/debug-log/file', _file);
    router.post('/api/debug-log/clear', _clear);
  }

  final DebugLog _log;

  Future<Map<String, dynamic>> _snapshot() async => {
    'enabled': _log.enabled,
    'bytes': await _log.size(),
    'fileName': DebugLog.fileName,
    'problem': _log.problem,
  };

  Future<shelf.Response> _status(shelf.Request r) async =>
      JsonResponse.ok(await _snapshot());

  Future<shelf.Response> _set(shelf.Request r) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final on = body['enabled'];
    if (on is! bool) return JsonResponse.badRequest('enabled is true or false');
    await _log.setEnabled(on);
    return JsonResponse.ok(await _snapshot());
  }

  Future<shelf.Response> _file(shelf.Request r) async {
    final text = await _log.contents();
    if (text.isEmpty) return JsonResponse.error(404, 'There is no log yet');
    return shelf.Response.ok(
      utf8.encode(text),
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'Content-Disposition': 'attachment; filename="${DebugLog.fileName}"',
        'Cache-Control': 'no-store',
      },
    );
  }

  Future<shelf.Response> _clear(shelf.Request r) async {
    await _log.clear();
    return JsonResponse.ok(await _snapshot());
  }
}
