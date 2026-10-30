// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A real WebDAV server on loopback, storing files in a real temp folder.
///
/// It speaks the part of WebDAV a sync place uses: GET, HEAD, PUT (with
/// `If-Match` / `If-None-Match` on strong ETags), MKCOL and DELETE, behind
/// Basic auth. Every request is recorded so a test can say what the client
/// sent. [ignoreConditions] plays a server that answers every PUT, the kind
/// the connection test must refuse.
class WebDavFolderServer {
  WebDavFolderServer._(this._server, this.root, this.username, this.password);

  final HttpServer _server;

  /// Where the stored files live; a test may look inside.
  final Directory root;
  final String username;
  final String password;

  bool ignoreConditions = false;

  final List<({String method, String path, Map<String, String> headers})>
  requests = [];

  static Future<WebDavFolderServer> start({
    String username = 'porch',
    String password = 'app-password',
  }) async {
    // flutter_test swaps in a client that answers 400 to everything.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final dir = await Directory.systemTemp.createTemp('fpai_webdav_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final host = WebDavFolderServer._(server, dir, username, password);
    server.listen((request) async {
      try {
        await host._handle(request);
      } catch (_) {
        // The client hung up mid-request; nothing to answer.
      }
    });
    addTearDown(() => server.close(force: true));
    return host;
  }

  /// The address a client is configured with, like a Nextcloud user root.
  String get url => 'http://127.0.0.1:${_server.port}/dav/files/$username/';

  File fileAt(String davPath) => File(
    p.joinAll([root.path, ...davPath.split('/').where((s) => s.isNotEmpty)]),
  );

  static String _tag(List<int> bytes) => '"${sha256.convert(bytes)}"';

  Future<void> _handle(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    final segments = request.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    final prefix = ['dav', 'files', username];
    requests.add((
      method: request.method,
      path: segments.skip(prefix.length).join('/'),
      headers: headers,
    ));
    final res = request.response;
    final auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    if (headers['authorization'] != auth) {
      res.statusCode = 401;
      await request.drain<void>();
      return res.close();
    }
    if (segments.length < prefix.length ||
        !List.generate(
          prefix.length,
          (i) => segments[i] == prefix[i],
        ).every((b) => b)) {
      res.statusCode = 404;
      await request.drain<void>();
      return res.close();
    }
    final relative = segments.skip(prefix.length).join('/');
    final file = fileAt(relative);
    final dir = Directory(file.path);
    switch (request.method) {
      case 'MKCOL':
        await request.drain<void>();
        if (await dir.exists() || await file.exists()) {
          res.statusCode = 405;
        } else if (!await dir.parent.exists()) {
          res.statusCode = 409;
        } else {
          await dir.create();
          res.statusCode = 201;
        }
      case 'PUT':
        final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        if (!await file.parent.exists()) {
          res.statusCode = 409;
          break;
        }
        final exists = await file.exists();
        final current = exists ? _tag(await file.readAsBytes()) : null;
        final ifMatch = headers['if-match'];
        final ifNone = headers['if-none-match'];
        if (!ignoreConditions &&
            ((ifMatch != null && ifMatch != current) ||
                (ifNone == '*' && exists))) {
          res.statusCode = 412;
          break;
        }
        await file.writeAsBytes(body, flush: true);
        res.statusCode = exists ? 204 : 201;
        res.headers.set('etag', _tag(body));
      case 'GET':
      case 'HEAD':
        await request.drain<void>();
        if (!await file.exists()) {
          res.statusCode = 404;
          break;
        }
        final bytes = await file.readAsBytes();
        res.statusCode = 200;
        res.headers.set('etag', _tag(bytes));
        res.contentLength = bytes.length;
        if (request.method == 'GET') res.add(bytes);
      case 'DELETE':
        await request.drain<void>();
        if (await file.exists()) {
          await file.delete();
          res.statusCode = 204;
        } else if (await dir.exists()) {
          await dir.delete(recursive: true);
          res.statusCode = 204;
        } else {
          res.statusCode = 404;
        }
      default:
        await request.drain<void>();
        res.statusCode = 405;
    }
    await res.close();
  }
}
