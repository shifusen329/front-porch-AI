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

import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'remote_embedding_client.dart';

/// Which embedding model memory search uses, read live from the settings,
/// and which model the stored vectors came from.
///
/// An install that never chose keeps the on-device model when it already
/// set it up (consented to the download, or has the files), and starts on
/// a model server otherwise.
class EmbeddingModelChoice {
  EmbeddingModelChoice(this._storage, {required bool Function() modelOnDisk})
    : _modelOnDisk = modelOnDisk;

  final StorageService _storage;
  final bool Function() _modelOnDisk;

  /// The on-device model, as named in [activeModelId].
  static const onDeviceModel = 'nomic-embed-text-v1.5';
  static const _onDeviceId = '$kEmbeddingOnDevice|$onDeviceModel';

  MemorySettings get _settings => _storage.memorySettings;

  bool get _setUpOnDevice => _settings.ragSetupConsented || _modelOnDisk();

  /// Whether vectors come from a model server rather than this device.
  bool get usesEndpoint {
    final chosen = _settings.embeddingProvider;
    if (chosen.isNotEmpty) return chosen == kEmbeddingEndpoint;
    return !_setUpOnDevice;
  }

  String get endpointUrl => _settings.embeddingEndpointUrl;
  String get endpointModel => _settings.embeddingEndpointModel;
  String get apiKey => _storage.backendSettings.remoteApiKeyFor(endpointUrl);

  /// `host:port` of the model server, for status lines.
  String get endpointHost {
    final uri = Uri.tryParse(RemoteEmbeddingClient.normalize(endpointUrl));
    if (uri == null || uri.host.isEmpty) return endpointUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// A server and a model to call, or the on-device model's files.
  bool get isConfigured => usesEndpoint
      ? endpointUrl.isNotEmpty && endpointModel.isNotEmpty
      : _modelOnDisk();

  /// The model new vectors come from, in `embedding_index_model` form.
  String get activeModelId =>
      usesEndpoint ? '$kEmbeddingEndpoint|$endpointModel' : _onDeviceId;

  /// The model the stored vectors came from ('' before the first one).
  /// Installs from before the setting existed only ever had on-device ones.
  String get indexModel {
    final stored = _settings.embeddingIndexModel;
    if (stored.isNotEmpty) return stored;
    return _setUpOnDevice ? _onDeviceId : '';
  }

  /// False when the stored vectors came from another model: searches then
  /// compare across models and match nothing (or the wrong things) until
  /// the vectors are rebuilt.
  bool get indexMatchesModel {
    final index = indexModel;
    return index.isEmpty || index == activeModelId;
  }

  /// Changes whenever a different model or server would answer.
  String get signature => [
    _settings.embeddingProvider,
    endpointUrl,
    endpointModel,
    apiKey,
  ].join('\u0000');

  /// Every stored vector now comes from [activeModelId] (a rebuild cleared
  /// the rest).
  Future<void> markIndexBuilt() =>
      _settings.setEmbeddingIndexModel(activeModelId);

  /// The first vector ever stored names the model behind the index.
  Future<void> noteVectorStored() async {
    if (indexModel.isEmpty) await markIndexBuilt();
  }

  Future<void> useOnDevice() =>
      _settings.setEmbeddingProvider(kEmbeddingOnDevice);
}
