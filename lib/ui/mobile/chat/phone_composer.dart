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

import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/pages/chat_page.composer_parts.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input_actions.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input_bar.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The phone's composer: **+** (attach and tools), the message box (one to
/// six lines, then it scrolls), and one button that is Send, Stop while a
/// reply is written, or the mic when voice input is on and the box is empty.
/// Generate reply and the group's turn buttons ride in a row above it. The
/// desktop's other buttons are in the + sheet and the app bar's ⋮.
///
/// The soft keyboard's Enter adds a new line; Send sends.
class PhoneComposer extends StatelessWidget {
  const PhoneComposer({
    super.key,
    required this.chatService,
    required this.controller,
    required this.focusNode,
    required this.pendingImage,
    required this.isPageMounted,
    required this.onSend,
    required this.onOpenTools,
  });

  final ChatService chatService;
  final TextEditingController controller;
  final FocusNode focusNode;
  final PendingImageSlot pendingImage;
  final ValueGetter<bool> isPageMounted;
  final VoidCallback onSend;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) {
    final pending = pendingImage.bytes;
    final generateReply = showsGenerateReply(chatService);
    final turnButtons = showsDirectorTurnButtons(chatService);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending != null)
          Builder(
            builder: (context) {
              LocalCaptionService.instance.configure(
                Provider.of<StorageService>(context, listen: false).rootPath,
              );
              return PendingImageChip(
                bytes: pending,
                visionOk: pendingImage.visionOk,
                blindReason: pendingImage.blindReason,
                onRemove: pendingImage.clear,
              );
            },
          ),
        const CaptionerStatusLine(),
        if (generateReply || turnButtons)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (generateReply)
                    ActionChip(
                      avatar: Icon(
                        Icons.refresh,
                        size: 18,
                        color: ChatColors.regenOf(context),
                      ),
                      label: const Text('Generate reply'),
                      onPressed: chatService.regenerateLastMessage,
                    ),
                  if (turnButtons)
                    chatDirectorTurnButtons(context, chatService),
                ],
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            border: Border(
              top: BorderSide(
                color: AppColors.borderOf(context).withValues(alpha: 0.35),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  color: AppColors.iconSecondary(context),
                ),
                tooltip: 'Attach and tools',
                onPressed: onOpenTools,
              ),
              Expanded(
                child: ChatComposerField(
                  chatService: chatService,
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(width: 4),
              _ComposerButton(
                chatService: chatService,
                controller: controller,
                hasPhoto: pending != null,
                isPageMounted: isPageMounted,
                onSend: onSend,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stop, mic or Send, in one place so the thumb always knows where to go.
class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.chatService,
    required this.controller,
    required this.hasPhoto,
    required this.isPageMounted,
    required this.onSend,
  });

  final ChatService chatService;
  final TextEditingController controller;
  final bool hasPhoto;
  final ValueGetter<bool> isPageMounted;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    if (chatService.isGenerating) {
      return IconButton.filled(
        icon: const Icon(Icons.stop),
        tooltip: chatService.autoPlayActive
            ? 'Stop Auto-Chat'
            : 'Stop Generation',
        style: IconButton.styleFrom(
          backgroundColor: StatusColors.dangerOf(context),
          foregroundColor: StatusColors.onFill,
        ),
        onPressed: () => stopComposerGeneration(chatService),
      );
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final stt = context.watch<SttService>();
        final storage = context.watch<StorageService>();
        final wantsMic =
            storage.sttSettings.sttEnabled &&
            !chatService.observerMode &&
            !hasPhoto &&
            value.text.trim().isEmpty;
        if (wantsMic || stt.isRecording) {
          if (stt.isTranscribing) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return IconButton(
            icon: Icon(
              stt.isRecording ? Icons.stop_circle : Icons.mic,
              color: stt.isRecording
                  ? StatusColors.dangerOf(context)
                  : AppColors.iconSecondary(context),
            ),
            tooltip: stt.isRecording ? 'Stop recording' : 'Voice input',
            onPressed: () => toggleVoiceInput(
              context,
              sttService: stt,
              storage: storage,
              chatService: chatService,
              controller: controller,
              isPageMounted: isPageMounted,
            ),
          );
        }
        return IconButton.filled(
          icon: Icon(
            chatService.observerMode ? Icons.movie_creation : Icons.send,
          ),
          tooltip: chatService.observerMode
              ? 'Send director note'
              : 'Send message',
          style: IconButton.styleFrom(
            backgroundColor: chatService.isGuestBusy
                ? AppColors.surfaceContainerOf(context)
                : AppColors.porchAmberOf(context),
            foregroundColor: AppColors.onAccentOf(context),
          ),
          onPressed: chatService.isLoadingSession ? null : onSend,
        );
      },
    );
  }
}
