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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// How much of the log the viewer shows: the newest part. Saving a copy
/// gives the whole log.
const kDebugLogViewerChars = 100000;

/// The newest [kDebugLogViewerChars] of [log], from the start of a line.
String debugLogTail(String log) {
  if (log.length <= kDebugLogViewerChars) return log;
  final cut = log.length - kDebugLogViewerChars;
  final lineStart = log.indexOf('\n', cut);
  return lineStart < 0 ? log.substring(cut) : log.substring(lineStart + 1);
}

/// Shows the newest part of [log], scrolled to the end, with Copy.
Future<void> showDebugLogViewer(BuildContext context, String log) {
  final shown = debugLogTail(log);
  return showWarmDialog<void>(
    context,
    title: 'Debug log',
    icon: Icons.article_outlined,
    width: 760,
    content: DebugLogText(text: shown),
    actions: [
      TextButton(
        key: const ValueKey('debug-log-copy'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: shown));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied what the viewer shows.')),
            );
          }
        },
        child: const Text('Copy'),
      ),
      warmDialogCancel(context, label: 'Close'),
    ],
  );
}

/// The log as selectable monospace text that opens on its newest line.
class DebugLogText extends StatelessWidget {
  const DebugLogText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Container(
      height: (height * 0.5).clamp(120.0, 460.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        padding: const EdgeInsets.all(10),
        child: SelectableText(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            height: 1.4,
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }
}
