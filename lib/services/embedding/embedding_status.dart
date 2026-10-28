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

import 'package:front_porch_ai/services/embedding_service.dart';

import 'embedding_model_choice.dart';

/// The memory engine's state for remote surfaces (the web tools panel,
/// Settings → Backend → Memory search on the phone), from its public
/// getters only.
extension EmbeddingStatus on EmbeddingService {
  /// Additive fields only — never remove keys from an old reader.
  Map<String, dynamic> get statusSnapshot => {
    'available': isAvailable,
    'modelOnDisk': modelOnDisk,
    'settingUp': isSettingUp,
    'setupProgress': setupProgress,
    'setupStatus': setupStatus,
    'setupError': setupError,
    'lastEngineError': lastEngineError,
    // Additive (2026-10-28): where vectors come from.
    'provider': usesEndpoint ? 'endpoint' : 'onDevice',
    'model': usesEndpoint ? endpointModel : EmbeddingModelChoice.onDeviceModel,
    'endpointHost': usesEndpoint ? endpointHost : null,
    'configured': isConfigured,
    'dimensions': dimensions,
    'indexMatches': choice.indexMatchesModel,
  };
}
