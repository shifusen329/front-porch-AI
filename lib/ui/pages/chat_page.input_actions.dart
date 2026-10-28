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
//
// ChatPage input-bar actions: the chat-management menu and the button strip
// (image studio, attach photo, impersonate, mic, call, auto-play, send/stop).
// The strip is a list spread into the bar's Row, so it is a plain builder
// rather than a widget: its Expanded message box must stay a direct Row child.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';

import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/pages/chat_page.composer_parts.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input.dart';
import 'package:front_porch_ai/ui/pages/chat_page.session_dialogs.dart';
import 'package:front_porch_ai/ui/pages/chat_page.regen_shortcut.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The chat-management popup: the composer's folder icon on the desktop, the
/// app bar's ⋮ on a phone ([icon]). Import, export and add-character are the
/// page's own flows; the rest open from this menu's context.
class ChatManagementMenu extends StatelessWidget {
  const ChatManagementMenu({
    super.key,
    required this.chatService,
    required this.onImport,
    required this.onExport,
    required this.onConvertToGroup,
    this.icon = Icons.folder_open,
  });

  final ChatService chatService;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onConvertToGroup;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final logInk = StatusColors.successOf(context);
    return PopupMenuButton<String>(
      icon: Icon(icon, color: AppColors.iconSecondary(context)),
      padding: EdgeInsets.zero,
      tooltip: 'Chat Management',
      onSelected: (value) {
        if (value == 'new_chat') {
          showNewChatConfirmation(context);
        } else if (value == 'history') {
          showManageChats(context);
        } else if (value == 'import') {
          // itemBuilder runs once when the menu opens. A turn can start
          // while the menu is still up, leaving a stale-enabled item.
          if (!chatService.isGenerating &&
              !chatService.isSettlingTurn &&
              !chatService.isImporting) {
            onImport();
          }
        } else if (value == 'export') {
          onExport();
        } else if (value == 'context') {
          showDialog(
            context: context,
            builder: (_) => ContextViewerDialog(chatService: chatService),
          );
        } else if (value == 'to_story') {
          ChatToStoryDialog.show(context, chatService: chatService);
        } else if (value == 'fork_group') {
          onConvertToGroup();
        } else if (value == 'kobold_log') {
          showDialog(context: context, builder: (_) => const KoboldLogDialog());
        }
      },
      itemBuilder: (context) {
        final amber = AppColors.porchAmberOf(context);
        return [
          const PopupMenuItem(
            value: 'new_chat',
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 20),
                SizedBox(width: 12),
                Text('New Chat'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'history',
            child: Row(
              children: [
                Icon(Icons.history, size: 20),
                SizedBox(width: 12),
                Text('Manage Chats'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'import',
            enabled:
                !chatService.isGenerating &&
                !chatService.isSettlingTurn &&
                !chatService.isImporting,
            child: Tooltip(
              message:
                  (!chatService.isGenerating && !chatService.isSettlingTurn)
                  ? 'Import a chat file'
                  : 'Wait until the current reply finishes, then import',
              child: const Row(
                children: [
                  Icon(Icons.file_upload, size: 20),
                  SizedBox(width: 12),
                  Text('Import Chat'),
                ],
              ),
            ),
          ),
          const PopupMenuItem(
            value: 'export',
            child: Row(
              children: [
                Icon(Icons.file_download, size: 20),
                SizedBox(width: 12),
                Text('Export Chat'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'context',
            child: Row(
              children: [
                Icon(Icons.analytics_outlined, size: 20, color: amber),
                SizedBox(width: 12),
                Text('Context Budget'),
              ],
            ),
          ),
          // Living Time §4: chat → novella. 1:1 only for now
          // (multi-protagonist novelization is a future effort).
          if (chatService.activeCharacter != null &&
              chatService.activeGroup == null)
            const PopupMenuItem(
              value: 'to_story',
              child: Row(
                children: [
                  Icon(Icons.auto_stories_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Turn Into a Story…'),
                ],
              ),
            ),
          // (The old Character Evolution dialog was replaced by the
          // Growth panel in the sidebar — Journal & Memory group —
          // which hosts the toggle, timeline, and all actions.)
          if (chatService.activeCharacter != null &&
              chatService.activeGroup == null)
            PopupMenuItem(
              value: 'fork_group',
              child: Row(
                children: [
                  Icon(Icons.group_add, size: 20, color: amber),
                  SizedBox(width: 12),
                  Text('Add Character (Group)…'),
                ],
              ),
            ),
          // No local engine here (a phone): no engine log to read.
          if (PlatformCaps.current.canRunLocalEngine) ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'kobold_log',
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 20, color: logInk),
                  const SizedBox(width: 12),
                  const Text('KoboldCpp Log'),
                ],
              ),
            ),
          ],
        ];
      },
    );
  }
}

/// Every action button to the right of the menu, in Row order.
class ChatInputActionStrip {
  const ChatInputActionStrip({
    required this.chatService,
    required this.controller,
    required this.focusNode,
    required this.minLines,
    required this.isPageMounted,
    required this.onOpenImageStudio,
    required this.onAttachImage,
    required this.onStartCall,
    required this.onSend,
  });

  final ChatService chatService;

  /// The chat page's message box. It dies with the page, not with this bar.
  final TextEditingController controller;
  final FocusNode focusNode;
  final int minLines;
  final ValueGetter<bool> isPageMounted;
  final VoidCallback onOpenImageStudio;
  final VoidCallback onAttachImage;
  final VoidCallback onStartCall;
  final VoidCallback onSend;

  /// The buttons, spread into the bar's Row (a spread of the same widgets in
  /// the same order is an identical child list).
  List<Widget> build(BuildContext context) {
    final danger = StatusColors.dangerOf(context);
    return <Widget>[
      // Image Generation: the magic-wand button opens the Image
      // Studio, where the user picks a Subject (Freeform / Character
      // / Persona) and crafts the prompt.
      Consumer<StorageService>(
        builder: (context, storage, _) {
          if (!storage.imageGenSettings.imageGenEnabled) {
            return const SizedBox.shrink();
          }
          return IconButton(
            icon: Icon(
              Icons.auto_awesome,
              color: AppColors.resolve(
                context,
                AppColors.formAccentOf(context),
                AppColors.formAccentOf(context),
              ),
            ),
            padding: EdgeInsets.zero,
            tooltip: 'Image Studio',
            onPressed: onOpenImageStudio,
          );
        },
      ),

      // Attach a photo to the next message (vision-capable models
      // see the pixels; others get the history marker). Hidden in
      // observer mode — director notes carry no images.
      if (!chatService.observerMode)
        IconButton(
          icon: Icon(
            Icons.add_photo_alternate_outlined,
            color: AppColors.iconSecondary(context),
          ),
          padding: EdgeInsets.zero,
          tooltip: 'Attach photo',
          onPressed: onAttachImage,
        ),

      const SizedBox(width: 4),

      Expanded(
        child: ChatComposerField(
          chatService: chatService,
          controller: controller,
          focusNode: focusNode,
          minLines: minLines,
          maxLines: 10,
        ),
      ),
      const SizedBox(width: 4),
      // Impersonate button (magic wand — AI writes your next message)
      Tooltip(
        message: 'Impersonate (AI writes your message)',
        child: IconButton(
          icon: Icon(Icons.auto_fix_high, color: AccentColors.amberOf(context)),
          padding: EdgeInsets.zero,
          onPressed: chatService.isGenerating
              ? null
              : () => impersonateIntoComposer(
                  chatService,
                  controller,
                  isPageMounted: isPageMounted,
                ),
        ),
      ),
      // Mic button (push-to-talk STT)
      Consumer2<SttService, StorageService>(
        builder: (context, sttService, storage, _) {
          if (!storage.sttSettings.sttEnabled) {
            return const SizedBox.shrink();
          }
          if (sttService.isTranscribing) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formAccentOf(context),
                ),
              ),
            );
          }
          return Tooltip(
            message: sttService.isRecording ? 'Stop recording' : 'Voice input',
            child: IconButton(
              icon: Icon(
                sttService.isRecording ? Icons.stop_circle : Icons.mic,
                color: sttService.isRecording
                    ? danger
                    : AppColors.iconSecondary(context),
              ),
              onPressed: chatService.isGenerating
                  ? null
                  : () => toggleVoiceInput(
                      context,
                      sttService: sttService,
                      storage: storage,
                      chatService: chatService,
                      controller: controller,
                      isPageMounted: isPageMounted,
                    ),
            ),
          );
        },
      ),
      // Call button (voice call mode)
      Consumer2<SttService, StorageService>(
        builder: (context, sttService, storage, _) {
          if (!storage.sttSettings.sttEnabled || chatService.isGroupMode) {
            return const SizedBox.shrink();
          }
          return Tooltip(
            message: 'Start voice call',
            child: IconButton(
              icon: Icon(Icons.call, color: AppColors.porchAmberOf(context)),
              onPressed: chatService.isGenerating || sttService.isBusy
                  ? null
                  : () async {
                      final micOk = await sttService.checkMicAvailable();
                      if (!micOk && context.mounted) {
                        showNoMicDialog(context);
                        return;
                      }
                      onStartCall();
                    },
            ),
          );
        },
      ),
      // Auto-play (Director Mode) + Next Character; Next stays greyed out
      // while auto-play runs so Pause lands where Play was. Pause stays up
      // through an auto-chat reply: it lets that reply finish.
      if (showsDirectorTurnButtons(chatService))
        chatDirectorTurnButtons(context, chatService),
      // Generate reply (1:1 only): a visible way to (re)generate without
      // retyping. Group mode covers this with Next Character above.
      if (showsGenerateReply(chatService))
        Tooltip(
          message: 'Generate reply ($chatRegenShortcutLabel)',
          child: IconButton(
            icon: Icon(Icons.refresh, color: ChatColors.regenOf(context)),
            onPressed: () => chatService.regenerateLastMessage(),
          ),
        ),
      chatService.isGenerating
          ? IconButton(
              icon: Icon(Icons.stop_circle, color: danger),
              tooltip: chatService.autoPlayActive
                  ? 'Stop Auto-Chat'
                  : 'Stop Generation',
              onPressed: () => stopComposerGeneration(chatService),
            )
          : Tooltip(
              message: chatService.observerMode
                  ? 'Send director note'
                  : 'Send message',
              child: IconButton(
                icon: Icon(
                  chatService.observerMode ? Icons.movie_creation : Icons.send,
                  color: chatService.isGuestBusy
                      ? AppColors.iconSecondary(context)
                      : AppColors.porchAmberOf(context),
                ),
                onPressed: chatService.isLoadingSession ? null : onSend,
              ),
            ),
    ];
  }
}

/// Auto-play (Director Mode) + Next Character, for both composers. Next
/// stays greyed out while auto-play runs so Pause lands where Play was;
/// Pause stays up through an auto-chat reply: it lets that reply finish.
Widget chatDirectorTurnButtons(BuildContext context, ChatService chatService) {
  return DirectorTurnButtons(
    showAutoPlay: chatService.observerMode,
    autoPlayActive: chatService.autoPlayActive,
    autoPlayPaused: chatService.autoPlayPaused,
    turnsLeft: chatService.autoChatTurnsLeft,
    onStopAutoPlay: chatService.stopAutoPlay,
    nextTooltip: chatService.nextCharacter != null
        ? 'Next: ${chatService.nextCharacter!.name}'
        : 'Trigger next character',
    onToggleAutoPlay: chatService.autoPlayActive
        ? chatService.pauseAutoPlay
        : chatService.startAutoPlay,
    onNextCharacter: chatService.triggerNextCharacter,
    playColor: AppColors.porchAmberOf(context),
    pauseColor: StatusColors.warningOf(context),
    nextColor: Colors.purpleAccent, // theme-keep: director Next, not Play
  );
}

/// Push-to-talk, for both composers: starts recording, or stops and puts
/// the transcript in [controller] (or sends it, when the user asked for
/// that and the box is empty).
Future<void> toggleVoiceInput(
  BuildContext context, {
  required SttService sttService,
  required StorageService storage,
  required ChatService chatService,
  required TextEditingController controller,
  required ValueGetter<bool> isPageMounted,
}) async {
  if (sttService.isRecording) {
    final text = await sttService.stopRecordingAndTranscribe();
    // Whisper can finish after the chat closed and disposed [controller].
    final mounted = isPageMounted();
    if (!mounted) return;
    if (text != null && text.isNotEmpty) {
      if (storage.sttSettings.autoSendTranscription &&
          controller.text.isEmpty) {
        chatService.sendMessage(text);
      } else {
        controller.text = controller.text.isEmpty
            ? text
            : '${controller.text} $text';
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
      }
    }
    return;
  }
  final micOk = await sttService.checkMicAvailable();
  if (!micOk && context.mounted) {
    showNoMicDialog(context);
    return;
  }
  await sttService.startRecording();
}
