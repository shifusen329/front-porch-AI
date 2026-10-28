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

// The composer pieces the desktop bar and the phone composer share: the
// message field, Impersonate, Stop, and when the turn buttons show. Each
// layout places them its own way; what they do lives here once. (Voice
// input and the turn buttons themselves are toggleVoiceInput and
// chatDirectorTurnButtons in chat_page.input_actions.dart.)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The message box: hint by connection state, the reading size, and the
/// styled-text controller's colouring (so the platform's spell underline
/// stays off; corrections still come from the keyboard or context menu).
class ChatComposerField extends StatelessWidget {
  const ChatComposerField({
    super.key,
    required this.chatService,
    required this.controller,
    required this.focusNode,
    required this.minLines,
    required this.maxLines,
    this.textCapitalization = TextCapitalization.none,
  });

  final ChatService chatService;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int minLines;
  final int maxLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Consumer2<LLMProvider, OpenRouterService>(
      builder: (context, llm, _, _) {
        final apiReady = llm.composerConnectionReady;
        final hint = chatComposerHint(
          apiReady: apiReady,
          observerMode: chatService.observerMode,
          reason: llm.composerConnectionHint,
        );
        final storage = Provider.of<StorageService>(context);
        return ReadingSizeScope(
          textScale: storage.uiSettings.textScale,
          child: AppTextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !chatService.isLoadingSession,
            maxLines: maxLines,
            minLines: minLines,
            textInputAction: TextInputAction.newline,
            textCapitalization: textCapitalization,
            style: readingSurfaceStyle(color: AppColors.textPrimary(context)),
            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: !apiReady
                    ? AppColors.negativeAccentOf(context)
                    : chatService.observerMode
                    ? AppColors.porchAmberOf(context).withValues(alpha: 0.7)
                    : AppColors.textTertiary(context),
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: AppCorners.of(context).circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Impersonate: the AI writes the user's next message into [controller],
/// continuing whatever is already typed.
void impersonateIntoComposer(
  ChatService chatService,
  TextEditingController controller, {
  required ValueGetter<bool> isPageMounted,
}) {
  chatService.impersonateUser(
    prefix: controller.text,
    onToken: (accumulated) {
      // ChatService is app-scoped and impersonation keeps streaming after
      // the page pops — writing a disposed controller here throws inside
      // the stream loop.
      if (!isPageMounted()) return;
      controller.text = accumulated;
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: accumulated.length),
      );
    },
  );
}

/// Stop: ends an auto-chat run as well as the reply being written.
void stopComposerGeneration(ChatService chatService) {
  chatService.stopAutoPlay();
  chatService.stopGeneration();
}

/// Whether the group's turn buttons show: a group, and nothing generating
/// unless it is the auto-chat (Pause stays up through its reply).
bool showsDirectorTurnButtons(ChatService chatService) =>
    chatService.isGroupMode &&
    (!chatService.isGenerating || chatService.autoPlayActive);

/// Whether Generate reply shows: a 1:1 whose last message is the user's
/// (say the reply was deleted), so the AI is up next.
bool showsGenerateReply(ChatService chatService) =>
    !chatService.isGroupMode &&
    !chatService.isGenerating &&
    !chatService.autoPlayActive &&
    chatService.messages.isNotEmpty &&
    chatService.messages.last.isUser;
