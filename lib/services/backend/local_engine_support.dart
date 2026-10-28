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

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/utils/platform_caps.dart';

/// Said wherever the app would offer KoboldCpp on a host that cannot run
/// any local engine (a phone). A model server on another computer is still
/// reachable over REST through Custom.
const String kNoLocalEngineHere =
    'This device cannot run a local engine. Pick a REST host: OpenRouter, '
    'Nano-GPT, xAI, or Custom for a model server on another computer '
    '(for example http://192.168.1.20:5001/v1 for KoboldCpp).';

/// One question for every "can KoboldCpp run here" gate. It reads
/// [BackendManager.isIntelMac] through the instance, so a test double that
/// overrides it still decides.
extension LocalEngineSupport on BackendManager {
  /// KoboldCpp cannot run here: an Intel Mac, or a host with no local
  /// engine at all.
  bool get localUnsupported =>
      isIntelMac || !PlatformCaps.current.canRunLocalEngine;

  /// What to say in place of the KoboldCpp controls.
  String get localUnsupportedMessage =>
      isIntelMac ? kIntelMacLocalUnsupported : kNoLocalEngineHere;
}
