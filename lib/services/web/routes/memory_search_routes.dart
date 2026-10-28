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

import 'package:front_porch_ai/services/web/facade/memory_search_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Memory search endpoints: the embedding model choice, the server's model
/// list, a connection check, and Clear and re-vectorize.
class WebMemorySearchRoutes {
  WebMemorySearchRoutes(this._facade, Router router) {
    router.get('/api/memory/embedding', _snapshot);
    router.post('/api/memory/embedding', _apply);
    router.post('/api/memory/embedding/models', _models);
    router.post('/api/memory/embedding/check', _check);
    router.post('/api/memory/embedding/rebuild', _rebuild);
    router.post('/api/memory/embedding/rebuild/stop', _stop);
  }

  final MemorySearchFacade _facade;

  Future<Map<String, dynamic>> _body(shelf.Request r) async {
    try {
      return await RequestBody.readJsonMap(r);
    } catch (_) {
      return const {};
    }
  }

  Future<shelf.Response> _run(
    Future<Map<String, dynamic>> Function() call,
  ) async {
    try {
      return JsonResponse.ok(await call());
    } on ArgumentError catch (e) {
      return JsonResponse.badRequest('${e.message}');
    } on StateError catch (e) {
      return JsonResponse.error(503, e.message);
    } catch (e) {
      // The model server's own failure (unreachable, HTTP error).
      return JsonResponse.error(502, '$e');
    }
  }

  Future<shelf.Response> _snapshot(shelf.Request r) => _run(_facade.snapshot);

  Future<shelf.Response> _apply(shelf.Request r) async {
    final body = await _body(r);
    return _run(() => _facade.apply(body));
  }

  Future<shelf.Response> _models(shelf.Request r) async {
    final body = await _body(r);
    return _run(() => _facade.listModels(body));
  }

  Future<shelf.Response> _check(shelf.Request r) => _run(_facade.check);

  Future<shelf.Response> _rebuild(shelf.Request r) async {
    final body = await _body(r);
    return _run(() => _facade.rebuild(body));
  }

  Future<shelf.Response> _stop(shelf.Request r) => _run(_facade.stop);
}
