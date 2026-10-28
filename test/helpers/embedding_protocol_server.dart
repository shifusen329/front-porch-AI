// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A real listening embedding server on loopback that speaks Ollama's API
// (`/api/tags`, `/api/embed`) or the OpenAI one (`/v1/models`,
// `/v1/embeddings`). Nothing is canned: each vector is computed from the
// text the app sent ([vectorFor]), and every request is recorded, so a
// wrong path, prefix, order or row shows up in what the test reads back.
// The live twin is the `live`-tagged test in
// test/services/embedding/remote_embedding_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class EmbeddingProtocolServer {
  EmbeddingProtocolServer._(
    this._server, {
    required this.ollama,
    required this.dims,
  });

  final HttpServer _server;
  final bool ollama;

  /// Length of every vector this server makes.
  int dims;

  /// When set, every request gets a 500.
  bool failing = false;

  /// How long each embed request waits before it is answered.
  Duration answerDelay = Duration.zero;

  /// Called with each embed request's inputs before it is answered.
  void Function(List<String> inputs)? onEmbed;

  /// Every embed request's `input` list, in arrival order.
  final List<List<String>> embedInputs = [];

  /// The `model` of every embed request.
  final List<String> embedModels = [];

  /// The Authorization header of every request, null when absent.
  final List<String?> authorizations = [];

  static const ollamaModels = [
    {
      'name': 'snowflake-arctic-embed-l-v2.0:latest',
      'capabilities': ['embedding'],
    },
    {
      'name': 'qwen3:8b',
      'capabilities': ['completion', 'tools'],
    },
    {
      'name': 'nomic-embed-text-v1.5-F16:latest',
      'capabilities': ['embedding'],
    },
  ];

  static const openAiModels = [
    'gpt-4o-mini',
    'text-embedding-3-small',
    'BAAI/bge-m3',
  ];

  static Future<EmbeddingProtocolServer> start({
    required bool ollama,
    int dims = 6,
  }) async {
    allowRealHttp();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = EmbeddingProtocolServer._(server, ollama: ollama, dims: dims);
    server.listen(s._handle);
    addTearDown(s.close);
    return s;
  }

  /// flutter_test swaps in a client that answers 400 to everything; this
  /// test's requests go out for real, until it ends.
  static void allowRealHttp() {
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
  }

  /// Ollama's root, or the OpenAI-style base with its `/v1`.
  String get url => ollama
      ? 'http://127.0.0.1:${_server.port}'
      : 'http://127.0.0.1:${_server.port}/v1';

  /// The vector this server makes for [text]: per slot, one plus how many
  /// of its code units fall in that slot.
  static List<double> vectorFor(String text, int dims) => [
    for (var i = 0; i < dims; i++)
      1.0 + text.codeUnits.where((c) => c % dims == i).length,
  ];

  Future<void> _handle(HttpRequest req) async {
    final res = req.response..headers.contentType = ContentType.json;
    final path = req.uri.path;
    authorizations.add(req.headers.value(HttpHeaders.authorizationHeader));
    final body = await utf8.decoder.bind(req).join();
    if (path.endsWith('embed') || path.endsWith('embeddings')) {
      await Future<void>.delayed(answerDelay);
    }
    if (failing) {
      res.statusCode = 500;
      res.write(jsonEncode({'error': 'model crashed'}));
      return res.close();
    }
    if (ollama && path == '/api/tags' && req.method == 'GET') {
      res.write(jsonEncode({'models': ollamaModels}));
    } else if (ollama && path == '/api/embed' && req.method == 'POST') {
      final inputs = _inputs(body);
      res.write(
        jsonEncode({
          'model': embedModels.last,
          'embeddings': [for (final t in inputs) vectorFor(t, dims)],
        }),
      );
    } else if (!ollama && path == '/v1/models' && req.method == 'GET') {
      res.write(
        jsonEncode({
          'data': [
            for (final id in openAiModels) {'id': id},
          ],
        }),
      );
    } else if (!ollama && path == '/v1/embeddings' && req.method == 'POST') {
      final inputs = _inputs(body);
      // Sent last-first: the client must order by `index`.
      res.write(
        jsonEncode({
          'data': [
            for (var i = inputs.length - 1; i >= 0; i--)
              {'index': i, 'embedding': vectorFor(inputs[i], dims)},
          ],
        }),
      );
    } else {
      res.statusCode = 404;
      res.write(jsonEncode({'error': 'no route $path'}));
    }
    await res.close();
  }

  List<String> _inputs(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final input = json['input'];
    final inputs = input is List ? input.map((e) => '$e').toList() : ['$input'];
    embedModels.add('${json['model']}');
    embedInputs.add(inputs);
    onEmbed?.call(inputs);
    return inputs;
  }

  Future<void> close() => _server.close(force: true);
}
