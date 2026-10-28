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
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/embedding/embedding_model_choice.dart';
import 'package:front_porch_ai/services/embedding/embedding_prefixes.dart';
import 'package:front_porch_ai/services/embedding/native_embedding_engine.dart';
import 'package:front_porch_ai/services/embedding/remote_embedding_client.dart';
import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:front_porch_ai/services/storage_service.dart';

export 'package:front_porch_ai/services/embedding/embedding_status.dart';

/// Unwinds [EmbeddingService.runSetup] when the user presses Cancel. Not an
/// error: the setup path treats it as a plain stop, never a failure.
class _SetupCancelled implements Exception {
  const _SetupCancelled();
}

/// Service that generates text embeddings (numerical vectors) for RAG memory retrieval.
///
/// Vectors come from a model server the user points at (Ollama or any
/// OpenAI-compatible host, [RemoteEmbeddingClient]) or from the on-device
/// model, as [EmbeddingModelChoice] reads the settings.
///
/// The on-device engine runs nomic-embed-text-v1.5 fully in-process via
/// onnxruntime (phase 5 of docs/design/sidecar-retirement.md — the app
/// spawns no helper processes at all). It is golden-pinned to the retired
/// Rust server's exact vectors, so embeddings already stored in users'
/// memory databases keep comparing correctly. Existing installs reuse the
/// fastembed model cache the server downloaded; fresh installs download
/// the model here ([runSetup]).
class EmbeddingService extends ChangeNotifier {
  final StorageService _storage;
  final NativeEmbeddingEngine _native = NativeEmbeddingEngine();
  final RemoteEmbeddingClient _remote;
  ({String model, String vocab})? _files;

  bool _available = false;
  int _dimensions = 0;
  String? _lastEngineError;

  static const String _hfBase =
      'https://huggingface.co/nomic-ai/nomic-embed-text-v1.5/resolve/main';

  bool get isAvailable => _available;
  int get dimensions => _dimensions;

  /// Last engine self-test / load failure (null when healthy). Surfaced in
  /// the Memory sidebar so "Model not downloaded" is never a dead end.
  String? get lastEngineError => _lastEngineError;

  /// Whether the model files exist on disk (fastembed cache or the
  /// app-managed download dir) — drives the sidebar status line.
  bool get modelOnDisk =>
      (_files ??= NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath)) !=
      null;

  /// Which model memory search uses, and which made the stored vectors.
  late final EmbeddingModelChoice choice = EmbeddingModelChoice(
    _storage,
    modelOnDisk: () => modelOnDisk,
  );

  bool get usesEndpoint => choice.usesEndpoint;
  String get endpointUrl => choice.endpointUrl;
  String get endpointModel => choice.endpointModel;
  String get endpointHost => choice.endpointHost;
  bool get isConfigured => choice.isConfigured;

  EmbeddingService(this._storage, {RemoteEmbeddingClient? remote})
    : _remote = remote ?? RemoteEmbeddingClient() {
    _signature = choice.signature;
    _storage.addListener(_onSettingsChanged);
  }

  // ---- Model choice ----

  String _signature = '';

  /// Bumped when the model choice changes, so a check still in flight for
  /// the old one cannot report the new one ready.
  int _configGen = 0;

  /// A new server, model or key starts over: the next search or the
  /// settings card checks the new one.
  void _onSettingsChanged() {
    final signature = choice.signature;
    if (signature == _signature) return;
    _signature = signature;
    _configGen++;
    _available = false;
    _dimensions = 0;
    _lastEngineError = null;
    _setupError = null;
    notifyListeners();
  }

  /// Switches memory search to the on-device model and sets it up.
  Future<bool> useOnDeviceModel() async {
    await choice.useOnDevice();
    return runSetup();
  }

  /// The embedding models the server at [url] offers.
  Future<List<String>> listEndpointModels(String url, {String? apiKey}) async {
    final key = apiKey ?? _storage.backendSettings.remoteApiKeyFor(url);
    return (await _remote.listModels(url, apiKey: key)).models;
  }

  // ---- Setup / download state (consumed by RagSetupDialog) ----

  bool _settingUp = false;
  bool _setupCancelled = false;
  String _setupStatus = '';
  double _setupProgress = -1; // -1 = indeterminate
  String? _setupError;

  bool get isSettingUp => _settingUp;
  String get setupStatus => _setupStatus;
  double get setupProgress => _setupProgress;
  String? get setupError => _setupError;

  void clearSetupError() {
    _setupError = null;
    notifyListeners();
  }

  /// Downloads the model if it isn't on disk, then loads + verifies the
  /// engine. Progress/status/error surface through the getters above.
  /// Returns true when embeddings are ready. On a model server there is
  /// nothing to download: it is reached and self-tested.
  Future<bool> runSetup() async {
    if (_settingUp) return false;
    if (usesEndpoint) {
      _setupError = null;
      await checkAvailability();
      return _available;
    }
    _settingUp = true;
    _setupCancelled = false;
    _setupError = null;
    _setupProgress = -1;
    _setupStatus = 'Checking for the embedding model...';
    notifyListeners();

    try {
      _files = NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath);
      if (_files == null) {
        final root = _storage.rootPath;
        if (root == null) {
          throw StateError('storage not initialized');
        }
        final dir = Directory(
          p.join(root, 'models', 'embeddings', 'nomic-v1_5'),
        );
        await dir.create(recursive: true);
        _setupStatus = 'Downloading embedding model (~550 MB, one time)...';
        _setupProgress = 0;
        notifyListeners();
        await ModelFetch.fetch(
          '$_hfBase/tokenizer.json',
          File(p.join(dir.path, 'tokenizer.json')),
        );
        if (_setupCancelled) throw const _SetupCancelled();
        await ModelFetch.fetch(
          '$_hfBase/onnx/model.onnx',
          File(p.join(dir.path, 'model.onnx')),
          onProgress: (done, total) {
            // The progress callback is the only lever ModelFetch gives us to
            // stop a 550 MB stream that is already flowing: throwing here
            // cancels the response subscription. ModelFetch still burns its
            // two retries (each aborts again at the next ~1% tick), which is
            // a few MB — against downloading the whole model after the user
            // pressed Cancel.
            if (_setupCancelled) throw const _SetupCancelled();
            if (total > 0) {
              _setupProgress = done / total;
              _setupStatus =
                  'Downloading embedding model... '
                  '${(done / (1024 * 1024)).round()} / '
                  '${(total / (1024 * 1024)).round()} MB';
              notifyListeners();
            }
          },
        );
        _files = NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath);
        if (_files == null) {
          throw StateError(
            'download finished but the model files failed '
            'verification',
          );
        }
      }

      if (_setupCancelled) throw const _SetupCancelled();
      _setupStatus = 'Loading the model (first run takes a moment)...';
      _setupProgress = -1;
      notifyListeners();
      await checkAvailability();
      if (_setupCancelled) throw const _SetupCancelled();
      if (!_available) {
        // Surface the engine's actual failure — a bare "self-test failed"
        // gives the user (and us) nothing to act on.
        throw StateError(
          'the engine failed its self-test'
          '${_lastEngineError == null ? '' : ' — $_lastEngineError'}',
        );
      }
      _setupStatus = 'Memory is ready.';
      return true;
    } on _SetupCancelled {
      // The user asked for this — no error banner, and no latched
      // `_setupError` (that would make ensureReady/Retry think the engine
      // is broken).
      _setupStatus = 'Setup cancelled.';
      _setupProgress = -1;
      _setupError = null;
      return false;
    } catch (e) {
      _setupError = '$e';
      _setupStatus = 'Setup failed.';
      EngineHealth.instance.reportFailure(
        EngineHealth.embeddings,
        'setup failed: $e',
      );
      return false;
    } finally {
      _settingUp = false;
      notifyListeners();
    }
  }

  /// Aborts setup from the dialog's Cancel: stops an in-flight download at
  /// its next progress tick, releases the (possibly half-warmed) session,
  /// and lets [runSetup] unwind so `isSettingUp` clears and a later Retry
  /// isn't refused by the re-entrancy guard. The partial `.part` file is
  /// discarded by the next attempt (ModelFetch has no resume) — the old doc
  /// here promised a resume that never existed.
  void cancelSetup() {
    _setupCancelled = true;
    _native.shutdown();
    notifyListeners();
  }

  /// True while [checkAvailability] is in flight — prevents parallel re-tests
  /// from every Memory-panel rebuild (audit P2.18).
  bool _checking = false;

  /// Kicks availability in the background if embeddings aren't live yet —
  /// the sidebar toggle calls this when RAG turns on with consent already
  /// given. If the model was never downloaded (or was deleted), starts
  /// [runSetup] so the user gets a progress bar instead of a silent "Model
  /// not downloaded" forever. After a failed setup OR self-test, wait for
  /// an explicit Retry (do not spin forever on open).
  void ensureReady() {
    // Latch on setup failure AND self-test failure (_setupError is set by
    // both paths) so we never spin forever on open. Explicit Retry clears it.
    if (_available || _settingUp || _checking || _setupError != null) return;
    if (usesEndpoint) {
      if (choice.isConfigured) unawaited(checkAvailability());
      return;
    }
    _files = NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath);
    if (_files == null) {
      unawaited(runSetup());
      return;
    }
    unawaited(checkAvailability());
  }

  /// Loads the engine (if the model is on disk) or reaches the model
  /// server, and verifies it end to end with a real embed, which also
  /// warms it so the first user-visible embed isn't the one paying the load.
  ///
  /// A call while a check runs waits for that one ("Check connection" just
  /// after saving a model must report the answer, not the moment before).
  Future<void> checkAvailability() async {
    final running = _inFlight;
    if (running != null) return running;
    final gen = _configGen;
    final run = _check(gen);
    _inFlight = run;
    try {
      await run;
    } finally {
      _inFlight = null;
    }
    // The choice moved mid-check: that answer was for the old one.
    if (gen != _configGen) await checkAvailability();
  }

  Future<void>? _inFlight;

  Future<void> _check(int gen) async {
    _checking = true;
    debugPrint('[RAG:Embed] ── Checking embedding availability ──');
    try {
      await (usesEndpoint ? _checkEndpoint(gen) : _checkOnDevice(gen));
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkEndpoint(int gen) async {
    if (!choice.isConfigured) {
      _available = false;
      notifyListeners();
      return;
    }
    try {
      final vectors = await _remoteEmbed([
        'test',
      ]).timeout(const Duration(seconds: 20));
      if (gen != _configGen) return;
      _dimensions = vectors.first.length;
      _available = true;
      _lastEngineError = null;
      _setupError = null;
      debugPrint(
        '[RAG:Embed] ✅ $endpointModel on $endpointHost '
        '(${_dimensions}d vectors)',
      );
    } catch (e) {
      if (gen != _configGen) return;
      _available = false;
      _lastEngineError = '$e';
      // Latched like the on-device self-test: ensureReady waits for Retry.
      _setupError = 'could not reach the memory model: $e';
      debugPrint('[RAG:Embed] ✗ $endpointModel on $endpointHost: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.embeddings,
        'model server check failed: $e',
      );
    }
    notifyListeners();
  }

  Future<void> _checkOnDevice(int gen) async {
    _files = NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath);
    if (_files == null) {
      _available = false;
      debugPrint(
        '[RAG:Embed] ⚠ No embedding model on disk — run RAG setup to '
        'download it',
      );
      notifyListeners();
      return;
    }

    try {
      final result = await _nativeEmbed('test');
      if (gen != _configGen) return;
      _dimensions = result.length;
      _available = true;
      _lastEngineError = null;
      // Clear a prior self-test latch so ensureReady can re-arm after Retry.
      if (_setupError != null &&
          _setupError!.startsWith('engine self-test failed')) {
        _setupError = null;
      }
      debugPrint(
        '[RAG:Embed] ✅ In-process embeddings available '
        '(${_dimensions}d vectors)',
      );
    } catch (e) {
      if (gen != _configGen) return;
      _available = false;
      _lastEngineError = '$e';
      // Latch for ensureReady (audit P2.18) — without this, every
      // dependency rebuild re-kicks self-test forever.
      _setupError = 'engine self-test failed: $e';
      debugPrint('[RAG:Embed] ✗ In-process engine failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.embeddings,
        'engine self-test failed: $e',
      );
    }
    notifyListeners();
  }

  /// Set by [embedQuery] for the [embed] call it makes, which reads and
  /// clears it before its first await.
  bool _queryRole = false;

  /// Generate an embedding vector for stored text (a memory, a card, a
  /// Data Bank entry). Returns null if embeddings are not available.
  Future<List<double>?> embed(String text) async {
    final asQuery = _queryRole;
    _queryRole = false;
    if (!_available || text.trim().isEmpty) return null;
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    final sw = Stopwatch()..start();

    try {
      final result = usesEndpoint
          ? (await _remoteEmbed([text], query: asQuery)).first
          : await _nativeEmbed(text);
      sw.stop();
      EngineHealth.instance.reportNative(EngineHealth.embeddings);
      debugPrint(
        '[RAG:Embed] ✅ ${result.length}d vector in ${sw.elapsedMilliseconds}ms ← "$preview"',
      );
      if (!asQuery) unawaited(choice.noteVectorStored());
      return result;
    } catch (e) {
      sw.stop();
      debugPrint(
        '[RAG:Embed] ✗ Embedding failed (${sw.elapsedMilliseconds}ms): $e',
      );
      EngineHealth.instance.reportFailure(
        EngineHealth.embeddings,
        'embed failed: $e',
      );
    }
    return null;
  }

  /// Embed a search query. Models trained with separate query and passage
  /// prefixes ([embeddingPrefixesFor]) get the query one. Goes through
  /// [embed], so a subclass that overrides it sees queries too.
  Future<List<double>?> embedQuery(String text) {
    _queryRole = true;
    try {
      return embed(text);
    } finally {
      _queryRole = false;
    }
  }

  /// Vectors for stored passages, in order. A model server takes them in
  /// one request, the on-device model one at a time. Throws when the
  /// engine is down or the call fails, for the caller to report.
  Future<List<List<double>>> embedDocuments(List<String> texts) async {
    if (!_available) throw StateError('the memory model is not ready');
    if (texts.isEmpty) return const [];
    final vectors = usesEndpoint
        ? await _remoteEmbed(texts)
        : [for (final t in texts) await _nativeEmbed(t)];
    unawaited(choice.noteVectorStored());
    return vectors;
  }

  Future<List<List<double>>> _remoteEmbed(
    List<String> texts, {
    bool query = false,
  }) {
    final prefixes = embeddingPrefixesFor(endpointModel);
    final prefix = query ? prefixes.query : prefixes.document;
    return _remote.embed(
      endpointUrl,
      model: endpointModel,
      apiKey: choice.apiKey,
      inputs: [for (final t in texts) '$prefix$t'],
    );
  }

  Future<List<double>> _nativeEmbed(String text) => _native.embed(
    modelPath: _files!.model,
    vocabPath: _files!.vocab,
    text: text,
  );

  @override
  void dispose() {
    _storage.removeListener(_onSettingsChanged);
    _native.shutdown();
    _remote.close();
    super.dispose();
  }
}
