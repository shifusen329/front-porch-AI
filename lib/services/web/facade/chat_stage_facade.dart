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

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

/// Web adapter for visual novel mode: whether the open chat shows as one,
/// who stands on its stage, and each figure's picture. The same
/// [stageSpritesFor] the desktop stage draws, so the phone shows the same
/// cast in the same pictures.
class ChatStageFacade {
  ChatStageFacade(this._chat, this._storage);

  final ChatService _chat;
  final StorageService _storage;

  /// `v` is the picture's file name: it changes when the picture does, so
  /// the page can cache each one.
  Map<String, dynamic> snapshot() {
    final on = visualNovelOn(_chat, _storage);
    return {
      'visualNovel': on,
      'stage': on
          ? [
              for (final s in stageSpritesFor(_chat, _storage))
                {
                  'id': s.id,
                  'name': s.name,
                  'speaking': s.speaking,
                  'v': p.basename(s.image.path),
                },
            ]
          : const [],
    };
  }

  /// The picture the figure [id] stands in now, or null.
  File? image(String id) {
    final sprite = stageSpritesFor(
      _chat,
      _storage,
    ).where((s) => s.id == id).firstOrNull;
    final file = sprite?.image;
    return file != null && file.existsSync() ? file : null;
  }
}
