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

import 'package:front_porch_ai/services/character_store/character_row_codec.dart'
    show mediaFolderName;
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

/// Web adapter for visual novel mode and the scene background: whether the
/// open chat shows as a visual novel, who stands on its stage, each figure's
/// picture, and the scene picture behind them. The same [stageSpritesFor]
/// and [SceneBackdrop] the desktop draws, so the phone shows the same.
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

  /// The scene picture behind the chat once the newest change is read, or
  /// null for the chat's own background. `who` and `v` name the file for
  /// [sceneImage], so the page can cache each picture.
  Future<Map<String, dynamic>?> scene() async {
    final backdrop = SceneBackdrop.of(_chat, _storage);
    await backdrop.settled;
    final shot = backdrop.current;
    if (shot == null) return null;
    return {
      'who': shot.who,
      'v': shot.scene.name,
      'place': shot.scene.place,
      'time': shot.time.name,
    };
  }

  /// A scene picture of someone in this chat, by [scene]'s `who` and `v`;
  /// null for anyone or anything else.
  Future<File?> sceneImage(String who, String name) async {
    for (final member in _chat.cast) {
      final owner = _chat.originLibraryCardFor(member.card) ?? member.card;
      if (mediaFolderName(owner.name) != who) continue;
      final library = SceneLibrary(() => _storage.charactersDir);
      return (await library.find(owner.name, name))?.file;
    }
    return null;
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
