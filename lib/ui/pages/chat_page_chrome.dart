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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/chat_components/overlays/absence_recap_banner.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// How the desktop arranges a chat: the app bar, the transcript column with
/// its status lines and composer, and the resizable sidebar on the right.
/// ChatPage owns every piece's state and builds the pieces; this only places
/// them, so another form factor can place the same pieces its own way.
class DesktopChatChrome extends StatelessWidget {
  const DesktopChatChrome({
    super.key,
    required this.chatService,
    required this.appBar,
    required this.transcript,
    required this.inputArea,
    required this.sidebar,
    required this.sidebarWidth,
    required this.onSidebarWidth,
  });

  final ChatService chatService;
  final PreferredSizeWidget appBar;
  final Widget transcript;
  final Widget inputArea;
  final Widget sidebar;
  final double sidebarWidth;
  final ValueChanged<double> onSidebarWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: appBar,
      body: Row(
        children: [
          Expanded(
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
          ChatResizeSidebar(
            width: sidebarWidth,
            onWidth: onSidebarWidth,
            child: RepaintBoundary(child: sidebar),
          ),
        ],
      ),
    );
  }
}

/// The "Previously on…" welcome-back banner (Living Time §2). App-voice,
/// dismissible, gated: enabled + over-threshold gap + a real session.
class ChatAbsenceBanner extends StatelessWidget {
  const ChatAbsenceBanner({super.key, required this.chatService});

  final ChatService chatService;

  @override
  Widget build(BuildContext context) {
    // Subscribe so a settings toggle updates live; the gate itself lives
    // once on ChatService.
    Provider.of<StorageService>(context);
    final phrase = chatService.absenceBannerPhrase;
    final sid = chatService.currentSessionId;
    if (phrase == null || sid == null) return const SizedBox.shrink();
    return AbsenceRecapBanner(
      sessionId: sid,
      phrase: phrase,
      recap: chatService.summary,
    );
  }
}
