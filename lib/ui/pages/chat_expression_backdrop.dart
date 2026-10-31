// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The character's expression, dimmed behind the chat, when Expression
/// Images → Display is Background Only or Both. A child of the chat's
/// backdrop [Stack]. The visual novel stage takes its place when [novel].
class ChatExpressionBackdrop extends StatelessWidget {
  const ChatExpressionBackdrop({
    super.key,
    required this.character,
    required this.novel,
  });

  final CharacterCard? character;
  final bool novel;

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chat, _) {
        final storage = Provider.of<StorageService>(context, listen: false);
        final settings = storage.expressionSettings;
        final char = character;
        if (novel ||
            !settings.expressionEnabled ||
            !settings.expressionsAsBackground ||
            chat.isEvaluatingRealism ||
            char == null ||
            expressionsFrom(char.avatarImages).isEmpty) {
          return const SizedBox.shrink();
        }
        final avatar = chat.resolveExpressionAvatar(
          char,
          rerollIfSame: settings.expressionRerollSame,
        );
        if (avatar == null) return const SizedBox.shrink();
        final avatarDir = storage.characterAvatarDir(char.name);
        final avatarFile = File('${avatarDir.path}/${avatar.filename}');
        return Positioned.fill(
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Stack(
                key: ValueKey('expr_bg_${avatar.id}'),
                fit: StackFit.expand,
                children: [
                  Image.file(
                    avatarFile,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  Container(
                    decoration: BoxDecoration(color: InkColors.dim(0.85)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
