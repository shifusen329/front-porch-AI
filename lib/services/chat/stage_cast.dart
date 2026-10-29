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

// Visual novel mode: who stands on the stage and in which picture. One
// answer for the desktop and Android stage (visual_novel_stage.dart) and
// the phone web app's (/api/chat/stage), so the surfaces cannot disagree.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'group_speaker_resolution.dart';

/// One figure on the visual-novel stage.
class StageSprite {
  const StageSprite({
    required this.id,
    required this.name,
    required this.image,
    required this.speaking,
  });

  /// The participant's id: keeps each figure in its place and its cross-fade
  /// its own when the cast changes.
  final String id;
  final String name;
  final File image;

  /// The one who spoke last; the others stand back a little.
  final bool speaking;
}

/// Whether this chat shows as a visual novel: its own choice, otherwise
/// Settings → Appearance.
bool visualNovelOn(ChatService chat, StorageService storage) =>
    chat.sessionThemeOverrides.visualNovel ??
    storage.expressionSettings.visualNovelMode;

/// Who stands on the stage and in which picture. Each character shows the
/// expression image for their feeling when Expression Images are on and
/// they have them, and their portrait otherwise; one with neither is left
/// off. In a group each member wears their own feeling, and the last
/// speaker is marked.
List<StageSprite> stageSpritesFor(ChatService chat, StorageService storage) {
  final cast = chat.cast;
  if (cast.isEmpty) return const [];
  final expressionsOn = storage.expressionSettings.expressionEnabled;
  final speaker = _lastSpeaker(chat);
  final sprites = <StageSprite>[];
  for (final member in cast) {
    final card = member.card;
    final speaking =
        cast.length == 1 ||
        (speaker == null ? member.isHost : _same(card, speaker));
    File? image;
    if (expressionsOn && expressionsFrom(card.avatarImages).isNotEmpty) {
      final groupFeeling = chat.isGroupMode
          ? chat.getEmotionForGroupCharacter(card)
          : null;
      final followsChat = followsChatExpression(
        speaking: speaking,
        mode: storage.expressionSettings.expressionClassificationMode,
        manualLabel: chat.expressionService.manualExpressionLabel,
      );
      final avatar = groupFeeling != null && !followsChat
          ? expressionForLabel(
              card,
              standardExpressionLabel(
                groupFeeling,
                storage.expressionSettings.expressionLabels,
              ),
            )
          : (cast.length == 1 || speaking)
          ? chat.resolveExpressionAvatar(
              card,
              rerollIfSame: storage.expressionSettings.expressionRerollSame,
            )
          : expressionForLabel(card, 'neutral');
      if (avatar != null) {
        image = File(
          p.join(storage.characterAvatarDir(card.name).path, avatar.filename),
        );
      }
    }
    final portrait = card.imagePath;
    if (image == null && portrait != null && portrait.isNotEmpty) {
      image = storage.resolveCharacterImage(portrait);
    }
    if (image == null) continue;
    sprites.add(
      StageSprite(
        id: member.id,
        name: card.name,
        image: image,
        speaking: speaking,
      ),
    );
  }
  return sprites;
}

/// A feeling as one of the expression labels images are tagged with:
/// [labels] (the standard set plus any the classifier model adds) as they
/// are, any other feeling word through the nuanced table.
String standardExpressionLabel(
  String feeling, [
  List<String> labels = EmotionLabels.all,
]) {
  final lower = feeling.toLowerCase().trim();
  if (labels.contains(lower)) return lower;
  return EmotionLabels.nuancedToStandard[lower] ?? 'neutral';
}

/// Whether a group member's picture follows the chat's own expression (the
/// ONNX model's label, or `/expression`) instead of their Realism feeling.
/// Both read the last reply, which is the speaker's, so only the speaker
/// does; everyone else keeps their own feeling.
bool followsChatExpression({
  required bool speaking,
  required String mode,
  String? manualLabel,
}) => speaking && (mode == 'onnx' || (manualLabel ?? '').isNotEmpty);

/// The first expression image tagged [label], else neutral, else the
/// card's chosen one. The same answer every time, so a figure does not
/// flicker between variants while a reply streams.
AvatarImage? expressionForLabel(CharacterCard card, String label) {
  final faces = expressionsFrom(card.avatarImages);
  if (faces.isEmpty) return null;
  AvatarImage? tagged(String l) =>
      faces.where((a) => a.label?.toLowerCase() == l).firstOrNull;
  return tagged(label) ??
      tagged('neutral') ??
      faces
          .where((a) => a.displayOrder + 1 == card.primeAvatarIndex)
          .firstOrNull ??
      faces.first;
}

CharacterCard? _lastSpeaker(ChatService chat) {
  if (!chat.isGroupMode) return null;
  final last = chat.messages.reversed.where((m) => !m.isUser).firstOrNull;
  if (last == null) return null;
  return resolveGroupSpeakerForMessage(
    chat.groupCharacters,
    last,
    logOnMiss: false,
  );
}

bool _same(CharacterCard a, CharacterCard b) =>
    groupMemberStoreId(a) == groupMemberStoreId(b);
