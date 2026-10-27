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
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The Hugging Face model the Local ONNX expression classifier runs: an
/// `owner/name` id or a pasted huggingface.co link, with Use and a reset to
/// the default. Shows the labels the model gives once it is on disk, so a
/// fine-tune's own labels are visible before images are tagged with them.
class ExpressionModelField extends StatefulWidget {
  const ExpressionModelField({super.key, required this.settings});

  final ExpressionSettings settings;

  @override
  State<ExpressionModelField> createState() => _ExpressionModelFieldState();
}

class _ExpressionModelFieldState extends State<ExpressionModelField> {
  late final _controller = TextEditingController(
    text: widget.settings.expressionOnnxModel,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _use(String value) async {
    if (normalizeExpressionModel(value) == null && value.trim().isNotEmpty) {
      setState(() => _error = 'Use owner/name, like $kDefaultExpressionModel');
      return;
    }
    setState(() => _error = null);
    await widget.settings.setExpressionOnnxModel(value);
    _controller.text = widget.settings.expressionOnnxModel;
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final labels = settings.expressionModelLabels;
    final own = [
      for (final l in labels ?? const <String>[])
        if (!EmotionLabels.all.contains(l)) l,
    ];
    final hint = TextStyle(
      fontSize: 11,
      color: AppColors.textTertiary(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.hub_outlined,
              size: 16,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Model:',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary(context),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'owner/name on Hugging Face',
                  hintStyle: hint,
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.restore, size: 16),
                    tooltip: 'Back to the default model',
                    onPressed: () => _use(''),
                  ),
                ),
                onSubmitted: _use,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _use(_controller.text),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.porchAmberOf(context),
              ),
              child: const Text('Use'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 4),
          child: Text(
            labels == null
                ? 'An ONNX text classifier with onnx/model.onnx, vocab.txt and '
                      'config.json. Its labels show here once it downloads.'
                : own.isEmpty
                ? '${labels.length} labels, all standard ones.'
                : '${labels.length} labels. Its own, for tagging images: '
                      '${own.join(', ')}',
            style: hint,
          ),
        ),
      ],
    );
  }
}
