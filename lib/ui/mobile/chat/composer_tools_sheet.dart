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
import 'package:front_porch_ai/ui/pages/chat_page.composer_parts.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input_bar.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The phone composer's **+** sheet: who you are (persona), a photo for the
/// next message, Image Studio, and Impersonate — the desktop composer's
/// buttons that do not fit beside a phone's message box. Each closes the
/// sheet, then does exactly what its desktop button does.
Future<void> showComposerToolsSheet(
  BuildContext context, {
  required ChatService chatService,
  required TextEditingController controller,
  required ValueGetter<bool> isPageMounted,
  required VoidCallback onAttachImage,
  required VoidCallback onOpenImageStudio,
}) {
  return showWarmSheet<void>(
    context,
    builder: (sheet) {
      void run(VoidCallback action) {
        Navigator.of(sheet).pop();
        action();
      }

      final persona = sheet.watch<UserPersonaService>().persona;
      final imageGen = Provider.of<StorageService>(
        sheet,
        listen: false,
      ).imageGenSettings.imageGenEnabled;
      final iconInk = AppColors.iconSecondary(sheet);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const ComposerPersonaAvatar(radius: 18),
            title: const Text('Persona'),
            subtitle: Text(
              persona.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => run(() => showPersonaSwitcher(context)),
          ),
          if (!chatService.observerMode)
            ListTile(
              leading: Icon(Icons.add_photo_alternate_outlined, color: iconInk),
              title: const Text('Attach photo'),
              subtitle: const Text('Sent with your next message'),
              onTap: () => run(onAttachImage),
            ),
          if (imageGen)
            ListTile(
              leading: Icon(
                Icons.auto_awesome,
                color: AppColors.formAccentOf(sheet),
              ),
              title: const Text('Image Studio'),
              onTap: () => run(onOpenImageStudio),
            ),
          ListTile(
            leading: Icon(
              Icons.auto_fix_high,
              color: AccentColors.amberOf(sheet),
            ),
            title: const Text('Impersonate'),
            subtitle: const Text('The AI writes your next message'),
            enabled: !chatService.isGenerating,
            onTap: () => run(
              () => impersonateIntoComposer(
                chatService,
                controller,
                isPageMounted: isPageMounted,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}
