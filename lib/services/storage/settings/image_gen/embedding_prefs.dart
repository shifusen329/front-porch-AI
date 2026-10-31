// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../../../image/image_gen_embeddings.dart';
import '../settings_base.dart';

/// The embeddings on the Studio desk. Like the model and LoRA picks they
/// belong to one backend: a name one server lists means nothing to another.
mixin ImageGenEmbeddingPrefs on SettingsBase {
  List<ImageGenEmbedding> _embeddings = const [];

  /// In the order they were picked.
  List<ImageGenEmbedding> get imageGenEmbeddings =>
      List.unmodifiable(_embeddings);

  void loadEmbeddingPrefs() {
    _embeddings = ImageGenEmbedding.decode(
      prefs?.getString(k('image_gen_embeddings')),
    );
  }

  Future<void> setImageGenEmbeddings(List<ImageGenEmbedding> picks) async {
    _embeddings = ImageGenEmbedding.fromRows([
      for (final e in picks) e.toJson(),
    ]);
    await _writeEmbeddings();
    notify();
  }

  /// This backend's picks, parked when another backend is chosen.
  String get parkedEmbeddings => ImageGenEmbedding.encode(_embeddings);

  /// Brings back a backend's parked picks. The backend swap notifies.
  Future<void> unparkEmbeddings(String? parked) async {
    _embeddings = ImageGenEmbedding.decode(parked);
    await _writeEmbeddings();
  }

  Future<void> _writeEmbeddings() async {
    await prefs?.setString(
      k('image_gen_embeddings'),
      ImageGenEmbedding.encode(_embeddings),
    );
  }
}
