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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/ui/theme/theme.dart';

/// The chat log in visual-novel mode: a see-through panel over the lower
/// part of the stage, holding the ordinary transcript ([child]) with all it
/// does (scrolling back, find, jumping to a message). Drag its handle to
/// give the log more or less of the screen, or tap it to read the whole
/// chat and tap again to see the stage. The height is remembered.
class VisualNovelLogPanel extends StatefulWidget {
  const VisualNovelLogPanel({super.key, required this.child});

  final Widget child;

  /// Share of the height the log takes until the user drags it.
  static const defaultShare = 0.38;
  static const _minShare = 0.2;
  static const _prefKey = 'vn_log_share';

  /// Widest the log gets on a big window, so lines stay readable and the
  /// figures show beside it.
  static const maxWidth = 920.0;

  @override
  State<VisualNovelLogPanel> createState() => _VisualNovelLogPanelState();
}

class _VisualNovelLogPanelState extends State<VisualNovelLogPanel> {
  double _share = VisualNovelLogPanel.defaultShare;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(VisualNovelLogPanel._prefKey);
    if (saved != null && mounted) setState(() => _share = saved);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(VisualNovelLogPanel._prefKey, _share);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight;
        final share = _expanded ? 1.0 : _share;
        final panel = (height * share).clamp(0.0, height);
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: VisualNovelLogPanel.maxWidth,
            ),
            child: SizedBox(
              key: const Key('vn-log-panel'),
              height: panel,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context).withValues(alpha: 0.82),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    _handle(context, height),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _handle(BuildContext context, double height) {
    return Semantics(
      button: true,
      label: _expanded ? 'Show the stage' : 'Show the whole chat',
      child: GestureDetector(
        key: const Key('vn-log-handle'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        onVerticalDragUpdate: (d) => setState(() {
          final current = _expanded ? 1.0 : _share;
          _expanded = false;
          _share = (current - d.delta.dy / height).clamp(
            VisualNovelLogPanel._minShare,
            1.0,
          );
        }),
        onVerticalDragEnd: (_) => unawaited(_save()),
        child: SizedBox(
          height: 24,
          child: Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: InkColors.handleOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
