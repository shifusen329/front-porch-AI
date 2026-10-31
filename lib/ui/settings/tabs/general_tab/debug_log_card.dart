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
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart'
    show PickerPrefs, PlatformCaps, formatBytes;

import 'debug_log_viewer.dart';

/// The name a saved copy of the log is offered under.
String debugLogSaveName(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'front-porch-log-${at.year}-${two(at.month)}-${two(at.day)}-'
      '${two(at.hour)}${two(at.minute)}.txt';
}

/// Settings → General → Troubleshooting: the debug log's switch, and what to
/// do with the log: view it, save a copy to share, open its folder on a
/// computer, or clear it.
class DebugLogCard extends StatefulWidget {
  const DebugLogCard({super.key, this.log});

  /// The app's own log when null.
  final DebugLog? log;

  @override
  State<DebugLogCard> createState() => _DebugLogCardState();
}

class _DebugLogCardState extends State<DebugLogCard> {
  DebugLog get _log => widget.log ?? DebugLog.instance;
  int _bytes = 0;
  String? _folder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _log.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _log.removeListener(_changed);
    super.dispose();
  }

  void _changed() => unawaited(_refresh());

  Future<void> _refresh() async {
    try {
      final bytes = await _log.size();
      final folder = await _log.folderPath();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _folder = folder;
      });
    } catch (e) {
      debugPrint('[DebugLog] could not read the log: $e');
    }
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  // Runs a button's [step]; a failure is said, not thrown.
  Future<void> _attempt(String failure, Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('[DebugLog] $failure: $e');
      if (mounted) _say('$failure: $e');
    }
  }

  Future<void> _view() => _attempt('The log could not be read', () async {
    final text = await _log.contents();
    if (mounted) await showDebugLogViewer(context, text);
  });

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _attempt('The log could not be saved', () async {
      final text = await _log.contents();
      if (!mounted || text.isEmpty) return;
      final saved = await GuardedPicker.saveFile(
        context,
        category: PickerPrefs.catExport,
        bytes: Uint8List.fromList(utf8.encode(text)),
        dialogTitle: 'Save a copy of the debug log',
        fileName: debugLogSaveName(DateTime.now()),
      );
      if (saved != null && mounted) {
        _say('Saved the log as ${p.basename(saved)}.');
      }
    });
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _openFolder() =>
      _attempt('The folder could not be opened', () async {
        final folder = _folder;
        if (folder == null) return;
        if (!await launchUrl(Uri.directory(folder)) && mounted) {
          _say('The folder could not be opened. It is $folder');
        }
      });

  Future<void> _clear() => _attempt('The log could not be cleared', () async {
    await _log.clear();
    if (mounted) _say('The debug log is cleared.');
  });

  @override
  Widget build(BuildContext context) {
    final hasLog = _bytes > 0;
    final problem = _log.problem;
    final desktop = PlatformCaps.current.isDesktop;
    final note = TextStyle(
      fontSize: 12.5,
      color: AppColors.textSecondary(context),
    );
    // A Material, not a coloured box, so the switch row's ink shows.
    return Material(
      color: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('debug-logging'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Write a debug log',
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              subtitle: Text(
                'Keeps what the app does, its warnings and its errors, with the '
                'time, in a file on this device. Turn it on, do what goes '
                'wrong, then save a copy to share. Keys and passwords are '
                'blanked out, but the log can hold parts of your chats, so look '
                'it over before you post it.',
                style: note,
              ),
              value: _log.enabled,
              onChanged: (on) => _attempt(
                'The debug log could not be turned ${on ? 'on' : 'off'}',
                () => _log.setEnabled(on),
              ),
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'The log could not be written: $problem',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: StatusColors.dangerOf(context),
                  ),
                ),
              ),
            Text(
              hasLog
                  ? '${DebugLog.fileName} · ${formatBytes(_bytes)}'
                  : 'No log yet.',
              style: note,
            ),
            if (desktop && _folder != null)
              SelectableText(
                _folder!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textTertiary(context),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  key: const ValueKey('debug-log-view'),
                  avatar: const Icon(Icons.article_outlined, size: 16),
                  label: const Text('View'),
                  onPressed: hasLog ? _view : null,
                ),
                ActionChip(
                  key: const ValueKey('debug-log-save'),
                  avatar: const Icon(Icons.save_alt, size: 16),
                  label: const Text('Save a copy…'),
                  onPressed: hasLog && !_saving ? _save : null,
                ),
                if (desktop)
                  ActionChip(
                    key: const ValueKey('debug-log-folder'),
                    avatar: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Open folder'),
                    onPressed: hasLog ? _openFolder : null,
                  ),
                ActionChip(
                  key: const ValueKey('debug-log-clear'),
                  avatar: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear'),
                  onPressed: hasLog ? _clear : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
