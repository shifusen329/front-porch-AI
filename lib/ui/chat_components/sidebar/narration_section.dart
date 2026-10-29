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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/services/tts_playback/tts_playback.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import '../overlays/narration_status_bar.dart';
import 'porch_accordion.dart';

/// Narrate All: reads the chat back from its first message, or from the
/// `#N` picked under "Starting at", each line in its speaker's voice. The
/// strip above the message box shows the same progress and a Stop.
class NarrationSection extends StatefulWidget {
  const NarrationSection({
    super.key,
    required this.chatService,
    this.loadScript,
  });

  final ChatService chatService;

  /// The lines from `#from`; [ChatService.narrationScript] when null.
  final Future<List<NarrationLine>?> Function(int from)? loadScript;

  @override
  State<NarrationSection> createState() => _NarrationSectionState();
}

class _NarrationSectionState extends State<NarrationSection> {
  final _from = TextEditingController();
  bool _startAt = false;

  /// Set while the script loads, so a double tap starts one narration.
  bool _starting = false;

  @override
  void dispose() {
    _from.dispose();
    super.dispose();
  }

  /// The `#N` to start at: the box's first number, whether typed ("12") or
  /// picked ("#12 · Riley — …"), else the first message.
  int get _fromNumber {
    if (!_startAt) return 1;
    final n = RegExp(r'\d+').firstMatch(_from.text)?.group(0);
    return int.tryParse(n ?? '') ?? 1;
  }

  Future<void> _narrate(TtsService tts) async {
    if (_starting || tts.narration.isRunning) return;
    final chat = widget.chatService;
    final session = chat.currentSessionId;
    setState(() => _starting = true);
    try {
      final from = _fromNumber;
      final lines =
          await (widget.loadScript?.call(from) ??
              chat.narrationScript(from: from));
      if (!mounted || lines == null) return;
      if (lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to narrate from there.')),
        );
        return;
      }
      unawaited(
        tts.narration.start(
          lines,
          stillCurrent: () => chat.currentSessionId == session,
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tts = Provider.of<TtsService>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final narration = tts.narration;
    return ListenableBuilder(
      listenable: narration,
      builder: (context, _) {
        final running = narration.isRunning;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Reads the chat aloud in order: your lines in your voice, '
              'each character in theirs, the narrator in the narrator voice.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('narration-start-at'),
              value: _startAt,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Starting at'),
              onChanged: running
                  ? null
                  : (v) => setState(() => _startAt = v ?? false),
            ),
            DropdownMenu<int>(
              key: const Key('narration-from'),
              controller: _from,
              enabled: _startAt && !running,
              enableFilter: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              hintText: 'Message number, e.g. 12',
              menuHeight: 320,
              dropdownMenuEntries: _entries(storage.ttsSettings),
            ),
            const SizedBox(height: 10),
            if (running) ...[
              Text(
                narrationProgressLabel(narration),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: narration.total == 0
                    ? null
                    : narration.done / narration.total,
                color: AppColors.porchAmberOf(context),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('narration-stop'),
                onPressed: narration.cancel,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stop'),
              ),
            ] else
              FilledButton.icon(
                key: const Key('narration-narrate'),
                onPressed: _starting ? null : () => _narrate(tts),
                icon: const Icon(Icons.record_voice_over, size: 18),
                label: Text(_starting ? 'Loading the chat…' : 'Narrate'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.porchAmberOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                ),
              ),
          ],
        );
      },
    );
  }

  /// One entry per line that is read aloud: "#12 · Riley — Pull up a…".
  List<DropdownMenuEntry<int>> _entries(TtsSettings tts) {
    final chat = widget.chatService;
    final base = chat.historyBasePosition;
    final messages = chat.messages;
    return [
      for (var i = 0; i < messages.length; i++)
        if (chat.voiceOf(messages[i], tts).speak)
          DropdownMenuEntry(
            value: base + i + 1,
            label:
                '#${base + i + 1} · ${messages[i].sender} — '
                '${_preview(messages[i].displayText)}',
          ),
    ];
  }

  static String _preview(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 40 ? flat : '${flat.substring(0, 40)}…';
  }
}

/// The Narration accordion in the chat's side panel, there only while
/// text-to-speech is on (like the messages' Speak buttons). While a
/// narration runs its title line shows the progress, so it reads even when
/// collapsed.
class NarrationGroup extends StatelessWidget {
  const NarrationGroup({
    super.key,
    required this.chatService,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
    this.loadScript,
  });

  final ChatService chatService;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;

  /// See [NarrationSection.loadScript].
  final Future<List<NarrationLine>?> Function(int from)? loadScript;

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    if (!storage.ttsSettings.ttsEnabled) return const SizedBox.shrink();
    final narration = Provider.of<TtsService>(context, listen: false).narration;
    return ListenableBuilder(
      listenable: narration,
      builder: (context, child) => PorchAccordion(
        id: 'narration',
        emoji: '🔊',
        title: 'Narration',
        subtitle: narration.isRunning
            ? narrationProgressLabel(narration)
            : null,
        accent: AppColors.porchAmberOf(context),
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        child: child!,
      ),
      child: NarrationSection(chatService: chatService, loadScript: loadScript),
    );
  }
}
