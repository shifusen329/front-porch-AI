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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/chat_turn_builder.dart';

/// The visual-novel stage for the open chat, drawn over its background and
/// under the chat log. It follows turns, not streamed text, so a figure
/// changes when a feeling does and holds still while a reply is written.
class VisualNovelStageLayer extends StatelessWidget {
  const VisualNovelStageLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    return ChatTurnBuilder(
      builder: (context, chat) {
        final sprites = stageSpritesFor(chat, storage);
        if (sprites.isEmpty) return const SizedBox.shrink();
        return IgnorePointer(child: VisualNovelStage(sprites: sprites));
      },
    );
  }
}

/// Figures standing side by side, each drawn whole and feet-down in its
/// share of the width. A new picture (a changed feeling) cross-fades in;
/// with the system's reduce-motion on, it swaps at once. Animated GIF and
/// WebP expressions play.
class VisualNovelStage extends StatelessWidget {
  const VisualNovelStage({super.key, required this.sprites});

  final List<StageSprite> sprites;

  static const _fade = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final slot = box.maxWidth / sprites.length;
        return Row(
          key: const Key('vn-stage'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final s in sprites)
              SizedBox(
                key: ValueKey('vn-sprite-${s.id}'),
                width: slot,
                height: box.maxHeight,
                child: AnimatedOpacity(
                  opacity: s.speaking ? 1 : 0.6,
                  duration: still ? Duration.zero : _fade,
                  child: AnimatedSwitcher(
                    duration: still ? Duration.zero : _fade,
                    child: Image.file(
                      s.image,
                      key: ValueKey(s.image.path),
                      width: slot,
                      height: box.maxHeight,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      cacheHeight: box.maxHeight.isFinite
                          ? (box.maxHeight * dpr).round()
                          : null,
                      gaplessPlayback: true,
                      semanticLabel: s.name,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
