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

import 'package:front_porch_ai/services/chat/chat.dart' show SceneBackdrop;
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Tells every browser to read the chat again when its scene changes on its
/// own: a painting starts, lands or fails long after the reply that asked
/// for it, when no other event is coming.
class WebSceneRelay {
  WebSceneRelay(this._backdrop, this._hub) : _cue = _backdrop.cue {
    _backdrop.addListener(_onChange);
  }

  final SceneBackdrop _backdrop;
  final StreamHub _hub;
  String _cue;

  void _onChange() {
    final cue = _backdrop.cue;
    if (cue == _cue) return;
    _cue = cue;
    _hub.broadcastChatUpdate();
  }

  void detach() => _backdrop.removeListener(_onChange);
}
