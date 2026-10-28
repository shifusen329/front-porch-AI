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

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory/memory.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Clear and re-vectorize: how many stored texts memory search has, whether
/// their vectors came from another model, and the rebuild with its progress.
class VectorRebuildCard extends StatefulWidget {
  const VectorRebuildCard({
    super.key,
    required this.rebuilder,
    required this.embeddings,
  });

  final VectorRebuilder rebuilder;
  final EmbeddingService embeddings;

  @override
  State<VectorRebuildCard> createState() => _VectorRebuildCardState();
}

class _VectorRebuildCardState extends State<VectorRebuildCard> {
  @override
  void initState() {
    super.initState();
    widget.rebuilder.refreshCounts().catchError((Object e) {
      debugPrint('[RAG:Rebuild] counting stored vectors failed: $e');
      return (total: 0, missing: 0);
    });
  }

  Future<void> _confirmRebuild() async {
    final yes = await showWarmDialog<bool>(
      context,
      title: 'Re-vectorize everything?',
      icon: Icons.refresh,
      accent: AppColors.porchAmberOf(context),
      content: WarmDialogText(
        'Every saved memory, Journal card and Data Bank entry loses its '
        'vector and gets a new one from ${_modelName(widget.embeddings.choice.activeModelId)}. '
        'The text itself is kept. Memory search finds less until it '
        'finishes; you can stop and resume.',
      ),
      actions: [
        Builder(builder: (ctx) => warmDialogCancel(ctx, value: false)),
        Builder(
          builder: (ctx) => warmDialogConfirm(
            ctx,
            label: 'Re-vectorize',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );
    if (yes == true) await widget.rebuilder.rebuild();
  }

  /// `endpoint|model` → `model`; the on-device one by its name.
  static String _modelName(String id) {
    final bar = id.indexOf('|');
    return bar < 0 ? id : id.substring(bar + 1);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.rebuilder, widget.embeddings]),
      builder: (context, _) {
        final r = widget.rebuilder;
        final emb = widget.embeddings;
        final counts = r.counts;
        final muted = AppColors.textTertiary(context);
        final small = TextStyle(fontSize: 12, height: 1.4, color: muted);
        final progress = r.total > 0 ? r.done / r.total : null;
        final mismatch =
            !emb.choice.indexMatchesModel && (counts?.total ?? 0) > 0;
        return Container(
          key: const Key('vector-rebuild-card'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.sunkenSurfaceOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: mismatch
                  ? StatusColors.warningOf(context)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stored vectors',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                counts == null
                    ? 'Counting…'
                    : '${counts.total} saved memories, Journal cards and '
                          'Data Bank entries'
                          '${counts.missing > 0 ? ', ${counts.missing} without a vector' : ''}.',
                style: small,
              ),
              if (mismatch) ...[
                const SizedBox(height: 6),
                Text(
                  'They were made with ${_modelName(emb.choice.indexModel)}, and '
                  'memory search now uses ${_modelName(emb.choice.activeModelId)}. '
                  'Vectors from two models don\'t compare, so old memories '
                  'won\'t be found until you re-vectorize.',
                  key: const Key('vector-model-mismatch'),
                  style: small.copyWith(color: StatusColors.warningOf(context)),
                ),
              ],
              if (r.running) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: AppColors.borderOf(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.porchAmberOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${r.done} of ${r.total}', style: small),
              ],
              if (!r.running && r.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  r.error!,
                  style: small.copyWith(color: StatusColors.dangerOf(context)),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (r.running)
                    OutlinedButton.icon(
                      onPressed: r.cancel,
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text('Stop'),
                    )
                  else ...[
                    FilledButton.icon(
                      key: const Key('vector-rebuild-button'),
                      onPressed: emb.choice.isConfigured
                          ? _confirmRebuild
                          : null,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Clear and re-vectorize everything'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.formAccentOf(context),
                        foregroundColor: AppColors.onAccentOf(context),
                      ),
                    ),
                    if ((counts?.missing ?? 0) > 0)
                      OutlinedButton(
                        key: const Key('vector-resume-button'),
                        onPressed: emb.choice.isConfigured
                            ? r.vectorizeMissing
                            : null,
                        child: Text('Vectorize the ${counts!.missing} missing'),
                      ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
