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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'sync_place.dart';

/// A WebDAV folder (Nextcloud, ownCloud, a NAS's WebDAV service).
///
/// Only GET, HEAD, PUT, MKCOL and DELETE: the layout never needs a listing,
/// so there is no PROPFIND and no XML. `latest.json` is written with
/// `If-Match` / `If-None-Match`, which [probe] checks the server honours.
class WebDavPlace extends SyncPlace {
  WebDavPlace({
    required String serverUrl,
    required String username,
    required String password,
    required List<String> folder,
    http.Client? client,
  }) : _base = _baseUri(serverUrl, folder),
       _folderDepth = folder.length,
       _auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
       _client = client ?? http.Client();

  final Uri _base;

  /// How many of [_base]'s trailing segments the app owns (and may create).
  final int _folderDepth;
  final String _auth;
  final http.Client _client;
  final Set<String> _madeFolders = {};

  static Uri _baseUri(String serverUrl, List<String> folder) {
    final server = Uri.parse(serverUrl.trim());
    if (!server.hasScheme ||
        !(server.isScheme('http') || server.isScheme('https'))) {
      throw const SyncPlaceException(
        'The server address must start with https:// (or http:// on your '
        'own network).',
      );
    }
    final segments = [
      ...server.pathSegments.where((s) => s.isNotEmpty),
      ...folder,
      '',
    ];
    return server.replace(pathSegments: segments);
  }

  @override
  String get label => _base.host;

  Uri _uri(String path) => _base.replace(
    pathSegments: [
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
      if (path.isEmpty || path.endsWith('/')) '',
    ],
  );

  Map<String, String> get _headers => {
    'Authorization': _auth,
    'Accept-Encoding': 'identity',
  };

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(_headers)
      ..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on SocketException catch (e) {
      throw SyncPlaceException('Couldn\'t reach ${_base.host}: ${e.message}.');
    } on HandshakeException {
      throw SyncPlaceException(
        '${_base.host} has a certificate this device doesn\'t trust. On '
        'Android, install your server\'s certificate in the system settings, '
        'or use http:// on your own network.',
      );
    } on http.ClientException catch (e) {
      throw SyncPlaceException('Couldn\'t reach ${_base.host}: ${e.message}.');
    }
  }

  Never _fail(int status, String what) {
    switch (status) {
      case 401:
      case 403:
        throw const SyncPlaceException(
          'The server refused the username or password. For Nextcloud, use '
          'an app password (Settings → Security → Devices & sessions).',
        );
      case 413:
        throw SyncPlaceException(
          'The server refused $what as too large. Raise its upload limit, or '
          'use a folder instead.',
        );
      case 507:
        throw const SyncPlaceException('The server is out of space.');
      default:
        throw SyncPlaceException('The server answered $status to $what.');
    }
  }

  @override
  Future<HeadRead?> readHead() async {
    final res = await _send(
      'GET',
      'latest.json',
      headers: const {'Cache-Control': 'no-cache'},
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) _fail(res.statusCode, 'reading latest.json');
    final tag = res.headers['etag'];
    if (tag == null || tag.isEmpty) {
      throw const SyncPlaceException(
        'The server doesn\'t give files a version tag (ETag), so two devices '
        'could overwrite each other. Use a different server or a folder.',
      );
    }
    return HeadRead(res.bodyBytes, tag);
  }

  @override
  Future<void> writeHead(List<int> bytes, {required String? ifTag}) async {
    await _ensureFolders('latest.json');
    final res = await _send(
      'PUT',
      'latest.json',
      headers: {
        'Content-Type': 'application/json',
        if (ifTag != null) 'If-Match': ifTag else 'If-None-Match': '*',
      },
      body: bytes,
    );
    if (res.statusCode == 412) throw const HeadChangedException();
    if (res.statusCode >= 300) _fail(res.statusCode, 'writing latest.json');
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    final res = await _send('GET', path);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) _fail(res.statusCode, 'reading $path');
    return res.bodyBytes;
  }

  @override
  Future<bool> exists(String path) async {
    final res = await _send('HEAD', path);
    if (res.statusCode == 404) return false;
    if (res.statusCode >= 300) _fail(res.statusCode, 'checking $path');
    return true;
  }

  @override
  Future<void> download(
    String path,
    File dest, {
    void Function(int)? onBytes,
  }) async {
    final request = http.Request('GET', _uri(path))..headers.addAll(_headers);
    final http.StreamedResponse res;
    try {
      res = await _client.send(request);
    } on SocketException catch (e) {
      throw SyncPlaceException('Couldn\'t reach ${_base.host}: ${e.message}.');
    }
    if (res.statusCode == 404) {
      await res.stream.drain<void>();
      throw SyncPlaceException(
        '$path is missing on the server.',
        missing: true,
      );
    }
    if (res.statusCode != 200) {
      await res.stream.drain<void>();
      _fail(res.statusCode, 'downloading $path');
    }
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    final sink = part.openWrite();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        onBytes?.call(chunk.length);
      }
    } finally {
      await sink.close();
    }
    await part.rename(dest.path);
  }

  @override
  Future<void> upload(
    String path,
    Stream<List<int>> Function() open,
    int size, {
    void Function(int)? onBytes,
  }) async {
    await _ensureFolders(path);
    // A known length, not chunked transfer: nginx and php-fpm in front of
    // Nextcloud often refuse a chunked PUT.
    final request = http.StreamedRequest('PUT', _uri(path))
      ..headers.addAll(_headers)
      ..headers['Content-Type'] = 'application/octet-stream'
      ..contentLength = size;
    final sent = _client.send(request);
    try {
      await for (final chunk in open()) {
        request.sink.add(chunk);
        onBytes?.call(chunk.length);
      }
    } finally {
      unawaited(request.sink.close());
    }
    final http.StreamedResponse res;
    try {
      res = await sent;
    } on SocketException catch (e) {
      throw SyncPlaceException('Couldn\'t reach ${_base.host}: ${e.message}.');
    }
    await res.stream.drain<void>();
    if (res.statusCode >= 300) _fail(res.statusCode, 'uploading $path');
  }

  @override
  Future<void> delete(String path) async {
    final res = await _send('DELETE', path);
    if (res.statusCode == 404) return;
    if (res.statusCode >= 300) _fail(res.statusCode, 'deleting $path');
  }

  /// MKCOL every folder above [path], from the top. 405 means it exists.
  Future<void> _ensureFolders(String path) async {
    final segments = path.split('/')..removeLast();
    var folder = '';
    for (final segment in ['', ...segments]) {
      folder = segment.isEmpty ? folder : '$folder$segment/';
      if (!_madeFolders.add(folder)) continue;
      await _mkcolChain(folder);
    }
  }

  Future<void> _mkcolChain(String folder) async {
    if (folder.isEmpty) {
      // The sync folder and its channel folder, never the server's own path
      // (`remote.php/dav/files/<you>/` already exists and refuses MKCOL).
      final base = _base.pathSegments.where((s) => s.isNotEmpty).toList();
      for (var i = base.length - _folderDepth + 1; i <= base.length; i++) {
        final res = await _mkcol(
          _base.replace(pathSegments: [...base.take(i), '']),
        );
        if (res != 201 && res != 405) _fail(res, 'creating the sync folder');
      }
      return;
    }
    final res = await _mkcol(_uri(folder));
    if (res != 201 && res != 405) _fail(res, 'creating $folder');
  }

  Future<int> _mkcol(Uri uri) async {
    final request = http.Request('MKCOL', uri)..headers.addAll(_headers);
    try {
      final res = await _client.send(request);
      await res.stream.drain<void>();
      return res.statusCode;
    } on SocketException catch (e) {
      throw SyncPlaceException('Couldn\'t reach ${_base.host}: ${e.message}.');
    }
  }

  @override
  Future<void> probe() async {
    final name = 'probe-${Random().nextInt(1 << 32).toRadixString(16)}.txt';
    final body = utf8.encode('Front Porch AI connection test');
    await _ensureFolders(name);
    var res = await _send('PUT', name, body: body);
    if (res.statusCode >= 300) _fail(res.statusCode, 'writing a test file');
    try {
      res = await _send('GET', name);
      if (res.statusCode != 200 || res.body != utf8.decode(body)) {
        throw const SyncPlaceException(
          'The server didn\'t give back the test file it was sent.',
        );
      }
      res = await _send(
        'PUT',
        name,
        headers: const {'If-Match': '"front-porch-not-a-tag"'},
        body: body,
      );
      if (res.statusCode != 412) {
        throw const SyncPlaceException(
          'This server ignores version checks (If-Match), so two devices '
          'could overwrite each other\'s library. Use a different server or '
          'a folder.',
        );
      }
    } finally {
      await _send('DELETE', name);
    }
  }

  @override
  void close() => _client.close();
}
