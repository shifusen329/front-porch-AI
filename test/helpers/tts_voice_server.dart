// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A real loopback HTTP server in the place of an OpenAI-compatible
/// text-to-speech server. It serves fixture files from disk at the paths a
/// test names, answers 404 elsewhere, and records every request so a test
/// can count what the app asked for. The fixture bodies keep the shape a real
/// server sent (`test/fixtures/tts/`).
class TtsVoiceServer {
  TtsVoiceServer._(this._server);

  final HttpServer _server;
  final Map<String, String> _files = {};
  final List<({String path, String? authorization})> requests = [];

  static Future<TtsVoiceServer> start() async {
    // flutter_test swaps in a client that answers 400 to everything.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final host = TtsVoiceServer._(server);
    server.listen(host._answer);
    addTearDown(() => server.close(force: true));
    return host;
  }

  /// What a user would type as the API base URL.
  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  /// Answers [path] with the fixture file at [fixture].
  void serveFile(String path, String fixture) => _files[path] = fixture;

  int hits(String path) => requests.where((r) => r.path == path).length;

  Future<void> _answer(HttpRequest request) async {
    requests.add((
      path: request.uri.path,
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
    ));
    final fixture = _files[request.uri.path];
    if (fixture == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = ContentType.json;
      await request.response.addStream(File(fixture).openRead());
    }
    await request.response.close();
  }
}
