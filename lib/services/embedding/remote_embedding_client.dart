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

import 'package:http/http.dart' as http;

/// The wire protocol an embedding server speaks.
enum EmbeddingApi { ollama, openAi }

/// An embedding server answered, but not with vectors.
class EmbeddingServerException implements Exception {
  const EmbeddingServerException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Lists and calls embedding models on a model server: Ollama's own API
/// (`/api/tags`, `/api/embed`) or any OpenAI-compatible one (`/v1/models`,
/// `/v1/embeddings` — OpenAI, vLLM, LM Studio, llama.cpp, KoboldCpp).
///
/// The user types one URL. A server that answers Ollama's `/api/tags` is
/// spoken to as Ollama; anything else as OpenAI-compatible, with `/v1`
/// added unless the URL already ends in a version.
class RemoteEmbeddingClient {
  RemoteEmbeddingClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, EmbeddingApi> _apiByUrl = {};

  static const _listTimeout = Duration(seconds: 10);
  static const _embedTimeout = Duration(seconds: 60);

  /// Ids that look like embedding models, for OpenAI-style listings, which
  /// do not say what a model does.
  static final _embeddingName = RegExp(
    r'embed|bge|e5[-_]|gte[-_]|minilm|mpnet|arctic|jina|retriev|mxbai|nomic',
    caseSensitive: false,
  );

  /// [url] without trailing slashes or a pasted endpoint path.
  static String normalize(String url) {
    var u = url.trim().replaceFirst(RegExp(r'/+$'), '');
    for (final tail in const [
      '/embeddings',
      '/models',
      '/api/embed',
      '/api/embeddings',
      '/api/tags',
    ]) {
      if (u.endsWith(tail)) {
        u = u.substring(0, u.length - tail.length);
        break;
      }
    }
    return u;
  }

  static String openAiBase(String url) {
    final u = normalize(url);
    return RegExp(r'/v\d+$').hasMatch(u) ? u : '$u/v1';
  }

  static String ollamaRoot(String url) =>
      normalize(url).replaceFirst(RegExp(r'/v1$'), '');

  Map<String, String> _headers(String apiKey) => {
    'Content-Type': 'application/json',
    if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
  };

  /// Ollama's model listing, or null when the server is not Ollama. A
  /// server that cannot be reached throws instead, so a host that is down
  /// is never remembered as the wrong kind.
  Future<List<dynamic>?> _ollamaTags(String url, String apiKey) async {
    final res = await _client
        .get(
          Uri.parse('${ollamaRoot(url)}/api/tags'),
          headers: _headers(apiKey),
        )
        .timeout(_listTimeout);
    if (res.statusCode != 200) return null;
    try {
      final models = (jsonDecode(res.body) as Map)['models'];
      return models is List ? models : null;
    } catch (_) {
      return null;
    }
  }

  /// Which protocol the server at [url] speaks, asked once per URL.
  Future<EmbeddingApi> detect(String url, {String apiKey = ''}) async {
    final slot = normalize(url);
    final known = _apiByUrl[slot];
    if (known != null) return known;
    final api = await _ollamaTags(url, apiKey) != null
        ? EmbeddingApi.ollama
        : EmbeddingApi.openAi;
    return _apiByUrl[slot] = api;
  }

  /// The server's embedding models, sorted. Ollama marks them in
  /// `capabilities`; older Ollama and OpenAI-style servers do not, so their
  /// ids are filtered by name, falling back to every model when no name
  /// matches.
  Future<({EmbeddingApi api, List<String> models})> listModels(
    String url, {
    String apiKey = '',
  }) async {
    final tags = await _ollamaTags(url, apiKey);
    if (tags != null) {
      _apiByUrl[normalize(url)] = EmbeddingApi.ollama;
      final rows = tags.whereType<Map>().toList();
      final marked = rows.any((m) => m['capabilities'] is List);
      final names = <String>[
        for (final m in rows)
          if (!marked ||
              (m['capabilities'] as List?)?.contains('embedding') == true)
            '${m['name'] ?? m['model'] ?? ''}',
      ].where((n) => n.isNotEmpty).toList();
      return (
        api: EmbeddingApi.ollama,
        models: marked ? (names..sort()) : _byName(names),
      );
    }
    _apiByUrl[normalize(url)] = EmbeddingApi.openAi;
    final res = await _client
        .get(Uri.parse('${openAiBase(url)}/models'), headers: _headers(apiKey))
        .timeout(_listTimeout);
    if (res.statusCode != 200) {
      throw EmbeddingServerException(_httpError(res));
    }
    final data = (jsonDecode(res.body) as Map)['data'];
    final ids = <String>[
      if (data is List)
        for (final m in data.whereType<Map>()) '${m['id'] ?? ''}',
    ].where((n) => n.isNotEmpty).toList();
    return (api: EmbeddingApi.openAi, models: _byName(ids));
  }

  static List<String> _byName(List<String> ids) {
    final embedders = ids.where(_embeddingName.hasMatch).toList();
    return (embedders.isEmpty ? ids : embedders)..sort();
  }

  /// One vector per input, in input order.
  Future<List<List<double>>> embed(
    String url, {
    required String model,
    required List<String> inputs,
    String apiKey = '',
  }) async {
    if (inputs.isEmpty) return const [];
    final api = await detect(url, apiKey: apiKey);
    final ollama = api == EmbeddingApi.ollama;
    final res = await _client
        .post(
          Uri.parse(
            ollama
                ? '${ollamaRoot(url)}/api/embed'
                : '${openAiBase(url)}/embeddings',
          ),
          headers: _headers(apiKey),
          body: jsonEncode({
            'model': model,
            'input': inputs,
            if (!ollama) 'encoding_format': 'float',
          }),
        )
        .timeout(_embedTimeout);
    if (res.statusCode != 200) {
      throw EmbeddingServerException(_httpError(res));
    }
    final body = jsonDecode(res.body) as Map;
    final List<List<double>> vectors;
    if (ollama) {
      vectors = [
        for (final v in (body['embeddings'] as List? ?? const [])) _floats(v),
      ];
    } else {
      final rows = (body['data'] as List? ?? const []).whereType<Map>().toList()
        ..sort(
          (a, b) =>
              ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0),
        );
      vectors = [for (final r in rows) _floats(r['embedding'])];
    }
    if (vectors.length != inputs.length || vectors.any((v) => v.isEmpty)) {
      throw EmbeddingServerException(
        'the server sent ${vectors.length} vectors for ${inputs.length} texts',
      );
    }
    return vectors;
  }

  static List<double> _floats(Object? v) =>
      v is List ? [for (final x in v) (x as num).toDouble()] : const <double>[];

  static String _httpError(http.Response res) {
    var detail = res.body.trim();
    try {
      final err = (jsonDecode(detail) as Map)['error'];
      detail = err is Map ? '${err['message'] ?? err}' : '$err';
    } catch (_) {}
    if (detail.length > 200) detail = '${detail.substring(0, 197)}…';
    return 'HTTP ${res.statusCode}${detail.isEmpty ? '' : ': $detail'}';
  }

  void close() => _client.close();
}
