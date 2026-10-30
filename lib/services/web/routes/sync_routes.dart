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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// `/api/sync/*`: Settings → Sync for the phone web app, driving the
/// desktop's library sync. Every route is behind the login check; saving a
/// new sync password also needs the web password again (step-up).
class WebSyncRoutes {
  WebSyncRoutes(this._facade, this._auth, Router router) {
    router.get('/api/sync', _status);
    router.post('/api/sync/settings', _settings);
    router.post('/api/sync/test', _test);
    router.post('/api/sync/refresh', _refresh);
    router.post('/api/sync/send', _send);
    router.post('/api/sync/get', _get);
    router.post('/api/sync/get/apply', _apply);
    router.post('/api/sync/get/discard', _discard);
    router.post('/api/sync/undo', _undo);
    router.post('/api/sync/cancel', _cancel);
  }

  final SyncFacade _facade;
  final AuthService _auth;

  Future<Map<String, dynamic>?> _body(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } on FormatException {
      return null;
    }
  }

  Future<shelf.Response> _status(shelf.Request request) async =>
      JsonResponse.ok(await _facade.status());

  Future<shelf.Response> _settings(shelf.Request request) async {
    final body = await _body(request);
    if (body == null) return JsonResponse.error(400, 'Expected a JSON object');
    if ((body['password']?.toString() ?? '').isNotEmpty) {
      final denied = await denyUnlessSteppedUp(
        auth: _auth,
        body: body,
        request: request,
      );
      if (denied != null) return denied;
    }
    try {
      await _facade.saveSettings(body);
    } on SyncPasswordStoreException catch (e) {
      return JsonResponse.error(503, e.message);
    }
    return JsonResponse.ok(await _facade.status());
  }

  Future<shelf.Response> _test(shelf.Request request) async {
    final error = await _facade.testConnection();
    return JsonResponse.ok({
      'ok': error == null,
      'message': error ?? 'Connected. This place can hold your library.',
    });
  }

  Future<shelf.Response> _refresh(shelf.Request request) async {
    await _facade.refresh();
    return JsonResponse.ok(await _facade.status());
  }

  shelf.Response _started(bool started) => started
      ? JsonResponse.ok({'started': true})
      : JsonResponse.error(409, 'Sync is already busy.');

  Future<shelf.Response> _send(shelf.Request request) async {
    final body = await _body(request) ?? const {};
    return _started(_facade.send(overwriteTheirs: body['overwrite'] == true));
  }

  Future<shelf.Response> _get(shelf.Request request) async {
    final body = await _body(request) ?? const {};
    return _started(
      _facade.prepareGet(snapshotId: body['snapshot']?.toString()),
    );
  }

  Future<shelf.Response> _apply(shelf.Request request) async =>
      _started(_facade.applyGet());

  Future<shelf.Response> _discard(shelf.Request request) async {
    await _facade.discardGet();
    return JsonResponse.ok(await _facade.status());
  }

  Future<shelf.Response> _undo(shelf.Request request) async =>
      _started(_facade.undo());

  shelf.Response _cancel(shelf.Request request) {
    _facade.cancel();
    return JsonResponse.ok({'cancelled': true});
  }
}

/// While a library swap has the database closed, every API call but Sync's
/// own answers 503, so the phone gets a clear "try again" instead of a
/// half-written change or a closed-database error.
shelf.Middleware librarySyncGate(LibrarySyncService sync) =>
    (inner) => (request) {
      final path = request.url.path;
      if (sync.replacing &&
          path.startsWith('api/') &&
          !path.startsWith('api/sync') &&
          !path.startsWith('api/auth')) {
        return JsonResponse.error(
          503,
          'This device\'s library is being replaced. Try again in a moment.',
        );
      }
      return inner(request);
    };
