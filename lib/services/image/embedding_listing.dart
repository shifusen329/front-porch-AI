// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/comfy_ui_service.dart';

/// Whether a generate on [backend] reads embeddings from its prompts.
/// ComfyUI's edit graphs run models that have none.
bool backendTakesEmbeddings(String backend, {bool edit = false}) =>
    backend == 'a1111' || (backend == 'comfyui' && !edit);

/// The embeddings an image server lists, read when the picker opens.
class EmbeddingListing {
  const EmbeddingListing({
    this.fits = const [],
    this.others = const [],
    this.problem,
  });

  /// Names the server can use with the model it has loaded.
  final List<String> fits;

  /// Names Automatic1111 skipped because they were made for another kind of
  /// model (an SD 1.5 embedding under an SDXL checkpoint).
  final List<String> others;

  /// Why nothing could be read, in words for the person.
  final String? problem;

  Map<String, Object?> toJson() => {
    'fits': fits,
    'others': others,
    'problem': problem,
  };
}

/// Automatic1111 (Forge, reForge) answers `GET /sdapi/v1/embeddings` with
/// `{loaded: {name: …}, skipped: {name: …}}`; ComfyUI answers
/// `GET /embeddings` with a list of names.
Future<EmbeddingListing> fetchEmbeddingListing({
  required String backend,
  required String a1111Url,
  required String comfyUrl,
}) async {
  if (!backendTakesEmbeddings(backend)) {
    return const EmbeddingListing(
      problem: 'This image backend does not take embeddings.',
    );
  }
  final comfy = backend == 'comfyui';
  final root = ComfyUiService.ensureHttpScheme(comfy ? comfyUrl : a1111Url);
  final uri = Uri.parse(
    comfy ? '$root/embeddings' : '$root/sdapi/v1/embeddings',
  );
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      return EmbeddingListing(
        problem: 'The image server answered ${r.statusCode}.',
      );
    }
    final body = jsonDecode(r.body);
    if (comfy) {
      return EmbeddingListing(
        fits: _sorted(body is List ? body.map((e) => '$e') : const []),
      );
    }
    List<String> names(Object? side) =>
        _sorted(side is Map ? side.keys.map((k) => '$k') : const []);
    return body is Map
        ? EmbeddingListing(
            fits: names(body['loaded']),
            others: names(body['skipped']),
          )
        : const EmbeddingListing();
  } catch (e) {
    debugPrint('ImageGen: reading embeddings from $uri failed: $e');
    return const EmbeddingListing(problem: 'The image server did not answer.');
  }
}

List<String> _sorted(Iterable<String> names) =>
    names.where((n) => n.trim().isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
