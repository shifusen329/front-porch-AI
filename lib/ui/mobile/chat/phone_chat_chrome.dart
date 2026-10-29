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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/pages/chat_page_chrome.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// How a phone arranges a chat: the transcript takes the whole width, with
/// its status lines and the composer below it, kept clear of the gesture
/// bar and lifted by the keyboard. The side panel is not here: it opens over
/// the chat as a sheet (showChatPanelSheet). ChatPage owns and builds every
/// piece, as it does for [DesktopChatChrome].
class PhoneChatChrome extends StatelessWidget {
  const PhoneChatChrome({
    super.key,
    required this.chatService,
    required this.appBar,
    required this.transcript,
    required this.inputArea,
  });

  final ChatService chatService;
  final PreferredSizeWidget appBar;
  final Widget transcript;
  final Widget inputArea;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: appBar,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            ChatAbsenceBanner(chatService: chatService),
            Expanded(child: transcript),
            const LiveGenerationStatusBar(),
            const NarrationStatusBar(),
            ChatEvaluationProgress(chatService: chatService, inline: true),
            RepaintBoundary(child: inputArea),
          ],
        ),
      ),
    );
  }
}
