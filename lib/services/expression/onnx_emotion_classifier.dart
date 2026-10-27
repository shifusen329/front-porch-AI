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
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/services.dart';
import 'onnx_emotion_engine.dart';

/// ONNX expression classifier: in-process inference (phase 2 of
/// docs/design/sidecar-retirement.md — the Python sidecar is gone).
///
/// Runs the Hugging Face model in Settings (go-emotions DistilBERT unless
/// another is chosen). The model auto-downloads on first use (direct HTTPS,
/// no Python), same behavior the sidecar had; until it lands, classify
/// returns neutral. Its labels come from its own config.json, so a model
/// trained on more than the 28 go-emotions labels reports them all.
class OnnxEmotionClassifier implements ExpressionClassifier {
  final StorageService storage;
  final void Function(OnnxDownloadProgress)? onProgress;
  final void Function()? onModelReady;

  /// Called with the model's labels once its config.json is on disk.
  final void Function(String model, List<String> labels)? onLabels;

  /// Where models are fetched from; tests point it at a local server.
  final String hubBaseUrl;

  OnnxEmotionClassifier({
    required this.storage,
    this.onProgress,
    this.onModelReady,
    this.onLabels,
    this.hubBaseUrl = kHuggingFaceBase,
  });

  /// The model this classifier runs. A model change in Settings makes a new
  /// classifier, so this is read once.
  late final String model = storage.expressionSettings.expressionOnnxModel;

  late final ExpressionModelFiles _files = ExpressionModelFiles(
    storage.rootPath ?? '',
    model,
  );

  String get _hfBase => '$hubBaseUrl/$model/resolve/main';

  /// Locates `(model.onnx, vocab source, config.json?)` — the download
  /// folder first, then (default model only) the HuggingFace hub cache the
  /// retired sidecar built (reused as-is, no re-download). The hub cache may
  /// lack vocab.txt (the fast tokenizer only downloads tokenizer.json); the
  /// engine's vocab loader accepts either file.
  (String, String, String?)? _resolveModelFiles() {
    if (File(_files.model).existsSync() && File(_files.vocab).existsSync()) {
      final config = File(_files.config);
      return (
        _files.model,
        _files.vocab,
        config.existsSync() ? config.path : null,
      );
    }
    if (!_files.isDefault) return null;
    final root = Directory(_files.cacheDir);
    if (!root.existsSync()) return null;
    try {
      // followLinks matters: the hub cache the sidecar built stores every
      // snapshot file as a symlink into blobs/, so with followLinks:false
      // the scan saw only Link entities, returned null, and every classify
      // silently fell back to the Python sidecar. `.no_exist` holds
      // zero-byte hub placeholders — never model files.
      for (final e in root.listSync(recursive: true, followLinks: true)) {
        if (e is! File ||
            !e.path.endsWith('model.onnx') ||
            e.path.contains('.no_exist')) {
          continue;
        }
        // Hub layout: .../snapshots/<rev>/onnx/model.onnx with tokenizer
        // files in the snapshot root two levels up.
        final snapshot = e.parent.parent;
        for (final name in ['vocab.txt', 'tokenizer.json']) {
          final vocab = File('${snapshot.path}/$name');
          if (vocab.existsSync()) return (e.path, vocab.path, null);
        }
      }
    } catch (e) {
      debugPrint('[Expr-Native] hub cache scan failed: $e');
    }
    return null;
  }

  bool _downloadKicked = false;

  @override
  Future<EmotionResult> classify(String text) async {
    if (text.trim().isEmpty) {
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }
    final files = _resolveModelFiles();
    if (files == null) {
      // Model not on disk yet: start the download once (mirrors the
      // sidecar, which auto-downloaded on first use) and answer neutral
      // until it lands.
      if (!_downloadKicked) {
        _downloadKicked = true;
        debugPrint(
          '[Expr-Native] $model not found under ${_files.downloadDir} — '
          'starting download',
        );
        unawaited(
          downloadModel().catchError((Object e) {
            debugPrint('[Expr-Native] auto-download failed: $e');
          }),
        );
      }
      EngineHealth.instance.reportFailure(
        EngineHealth.expressions,
        'model not downloaded yet',
        expected: true,
      );
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }
    try {
      final scored = await OnnxEmotionEngine.classify(
        modelPath: files.$1,
        vocabPath: files.$2,
        configPath: files.$3,
        text: text,
      );
      EngineHealth.instance.reportNative(EngineHealth.expressions);
      return EmotionResult(
        emotion: scored.first.$1,
        confidence: scored.first.$2,
        topCandidates: [
          for (final (label, score) in scored.take(3))
            EmotionCandidate(emotion: label, confidence: score),
        ],
      );
    } catch (e) {
      debugPrint('[Expr-Native] in-process classify failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.expressions,
        'in-process classify failed: $e',
      );
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }
  }

  /// The direct HTTPS download needs nothing installed, so the classifier
  /// is always available — [classify] answers neutral until the model
  /// finishes downloading.
  @override
  Future<bool> isAvailable() async => true;

  /// Downloads vocab.txt, config.json and onnx/model.onnx directly over
  /// HTTPS. The weights come last, so a model is never on disk without the
  /// labels that name its outputs.
  Future<void> downloadModel() async {
    final dir = Directory(_files.downloadDir);
    await dir.create(recursive: true);
    await _fetchFirst(['vocab.txt', 'onnx/vocab.txt'], File(_files.vocab));
    await _fetchFirst(['config.json', 'onnx/config.json'], File(_files.config));
    await _fetch('$_hfBase/onnx/model.onnx', File(_files.model));
    await reportLabels();
    onModelReady?.call();
  }

  /// Reads the labels in the model's config.json and hands them to
  /// [onLabels]; nothing when the model has no readable config.json yet.
  Future<void> reportLabels() async {
    final config = File(_files.config);
    if (!await config.exists()) return;
    final labels = OnnxEmotionEngine.labelsFromConfig(
      await config.readAsString(),
    );
    if (labels != null) onLabels?.call(model, labels);
  }

  /// Fetches the first of [paths] the repo has, to [dest].
  Future<void> _fetchFirst(List<String> paths, File dest) async {
    for (final (i, path) in paths.indexed) {
      try {
        return await _fetch('$_hfBase/$path', dest);
      } catch (e) {
        if (i == paths.length - 1) rethrow;
        debugPrint('[Expr-Native] $model has no $path ($e), trying the next');
      }
    }
  }

  /// Fetches [url] to [dest] via the shared [ModelFetch] helper, mapping
  /// its per-file progress onto [onProgress].
  Future<void> _fetch(String url, File dest) {
    final name = url.split('/').last;
    return ModelFetch.fetch(
      url,
      dest,
      minBytes: name.endsWith('.onnx') ? 1024 * 1024 : 1,
      onProgress: (done, total) => onProgress?.call(
        OnnxDownloadProgress(file: name, downloaded: done, total: total),
      ),
    );
  }
}
