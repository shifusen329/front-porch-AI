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

import 'package:front_porch_ai/services/embedding/embedding_model_choice.dart';
import 'package:front_porch_ai/services/embedding/embedding_status.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';

/// Web adapter for Settings → Backend → Memory search: the embedding model
/// choice (model server URL, key, model; or on-device), the server's model
/// list, the engine status, and Clear and re-vectorize. The desktop twin is
/// MemorySearchSection. API keys are written, never read back.
class MemorySearchFacade {
  MemorySearchFacade(this._chat, this._storage);

  final ChatService _chat;
  final StorageService _storage;

  MemoryService get _memory {
    final memory = _chat.memoryService;
    if (memory == null) throw StateError('memory is not wired yet');
    return memory;
  }

  MemorySettings get _settings => _storage.memorySettings;

  Future<Map<String, dynamic>> snapshot() async {
    final memory = _memory;
    final emb = memory.embeddingService;
    final rebuilder = memory.vectorRebuilder;
    if (!rebuilder.running) await rebuilder.refreshCounts();
    return {
      'provider': emb.usesEndpoint ? kEmbeddingEndpoint : kEmbeddingOnDevice,
      'endpointUrl': emb.endpointUrl,
      'endpointModel': emb.endpointModel,
      'hasApiKey': emb.choice.apiKey.isNotEmpty,
      'onDeviceModel': EmbeddingModelChoice.onDeviceModel,
      'activeModel': emb.choice.activeModelId,
      'indexModel': emb.choice.indexModel,
      'status': emb.statusSnapshot,
      'rebuild': rebuilder.snapshot,
    };
  }

  /// Applies `provider`, `endpointUrl`, `endpointModel` and `apiKey` (each
  /// optional), then checks the model in the background.
  Future<Map<String, dynamic>> apply(Map<String, dynamic> body) async {
    final provider = body['provider'];
    if (provider != null) {
      if (provider != kEmbeddingEndpoint && provider != kEmbeddingOnDevice) {
        throw ArgumentError('provider must be endpoint or onDevice');
      }
      await _settings.setEmbeddingProvider(provider as String);
    }
    final url = body['endpointUrl'];
    if (url is String) await _settings.setEmbeddingEndpointUrl(url);
    final model = body['endpointModel'];
    if (model is String) await _settings.setEmbeddingEndpointModel(model);
    final key = body['apiKey'];
    if (key is String && key.trim().isNotEmpty) {
      final target = _settings.embeddingEndpointUrl;
      if (target.isEmpty) throw ArgumentError('set endpointUrl first');
      await _storage.backendSettings.setRemoteApiKeyFor(target, key.trim());
    }
    final emb = _memory.embeddingService;
    if (emb.usesEndpoint && emb.choice.isConfigured) {
      unawaited(emb.checkAvailability());
    }
    return snapshot();
  }

  /// The embedding models of the server at `url` (default: the saved one).
  Future<Map<String, dynamic>> listModels(Map<String, dynamic> body) async {
    final url = (body['url'] as String?)?.trim();
    final target = (url == null || url.isEmpty)
        ? _settings.embeddingEndpointUrl
        : url;
    if (target.isEmpty) throw ArgumentError('url is required');
    final key = (body['apiKey'] as String?)?.trim();
    final models = await _memory.embeddingService.listEndpointModels(
      target,
      apiKey: (key == null || key.isEmpty) ? null : key,
    );
    return {'url': target, 'models': models};
  }

  /// Reaches the model (or loads the on-device one) and reports back.
  Future<Map<String, dynamic>> check() async {
    final emb = _memory.embeddingService;
    emb.clearSetupError();
    await emb.checkAvailability();
    return snapshot();
  }

  /// Starts a rebuild: `mode` `all` clears every vector first, `missing`
  /// only fills the ones without. Progress is read from [snapshot].
  Future<Map<String, dynamic>> rebuild(Map<String, dynamic> body) async {
    final rebuilder = _memory.vectorRebuilder;
    final all = (body['mode'] ?? 'all') == 'all';
    unawaited(all ? rebuilder.rebuild() : rebuilder.vectorizeMissing());
    return snapshot();
  }

  Future<Map<String, dynamic>> stop() async {
    _memory.vectorRebuilder.cancel();
    return snapshot();
  }
}
