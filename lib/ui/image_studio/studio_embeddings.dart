// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The embeddings on the desk, under the negative prompt. Each one says
/// whether it goes in the prompt or the negative prompt, and Add lists what
/// the image server has.
class StudioEmbeddings extends StatelessWidget {
  const StudioEmbeddings({super.key, required this.settings, this.canWrite});

  final ImageGenSettings settings;
  final bool Function()? canWrite;

  void _save(List<ImageGenEmbedding> picks) {
    if (canWrite?.call() ?? true) settings.setImageGenEmbeddings(picks);
  }

  Future<void> _add(BuildContext context) async {
    final name = await showWarmDialog<String>(
      context,
      title: 'Add an embedding',
      icon: Icons.add,
      width: 380,
      content: _EmbeddingPicker(
        settings: settings,
        taken: {for (final e in settings.imageGenEmbeddings) e.name},
      ),
      actions: [warmDialogCancel(context)],
    );
    if (name == null) return;
    _save([...settings.imageGenEmbeddings, ImageGenEmbedding.picked(name)]);
  }

  @override
  Widget build(BuildContext context) {
    final picks = settings.imageGenEmbeddings;
    final primary = AppColors.textPrimary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Embeddings', style: TextStyle(color: primary)),
        if (picks.isEmpty)
          Text(
            'None yet. Add one your image server has, such as a negative '
            'embedding made for your model.',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
        for (final pick in picks)
          Row(
            key: ValueKey('embedding-${pick.name}'),
            children: [
              Expanded(
                child: Text(
                  pick.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: primary),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Prompt')),
                  ButtonSegment(value: true, label: Text('Negative')),
                ],
                selected: {pick.negative},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (side) => _save([
                  for (final e in picks)
                    e.name == pick.name
                        ? ImageGenEmbedding(e.name, negative: side.single)
                        : e,
                ]),
              ),
              IconButton(
                tooltip: 'Remove ${pick.name}',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _save([
                  for (final e in picks)
                    if (e.name != pick.name) e,
                ]),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('embedding-add'),
            onPressed: () => _add(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add an embedding'),
          ),
        ),
      ],
    );
  }
}

/// The server's embeddings, read when the dialog opens. A tap closes the
/// dialog with that name; one already on the desk is ticked and stays put.
class _EmbeddingPicker extends StatefulWidget {
  const _EmbeddingPicker({required this.settings, required this.taken});

  final ImageGenSettings settings;
  final Set<String> taken;

  @override
  State<_EmbeddingPicker> createState() => _EmbeddingPickerState();
}

class _EmbeddingPickerState extends State<_EmbeddingPicker> {
  late final Future<EmbeddingListing> _listing = fetchEmbeddingListing(
    backend: widget.settings.imageGenBackend,
    a1111Url: widget.settings.localImageGenUrl,
    comfyUrl: widget.settings.comfyUiUrl,
  );

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondary(context);
    return FutureBuilder<EmbeddingListing>(
      future: _listing,
      builder: (context, snap) {
        final listing = snap.data;
        if (listing == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final problem =
            listing.problem ??
            (listing.fits.isEmpty && listing.others.isEmpty
                ? 'The image server lists no embeddings.'
                : null);
        if (problem != null) {
          return Text(problem, style: TextStyle(color: secondary));
        }
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final name in listing.fits)
                ListTile(
                  key: ValueKey('embedding-pick-$name'),
                  dense: true,
                  title: Text(name),
                  enabled: !widget.taken.contains(name),
                  trailing: widget.taken.contains(name)
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.of(context).pop(name),
                ),
              if (listing.others.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Made for another kind of model, so the server skips '
                    'these with the one it has loaded:',
                    style: TextStyle(color: secondary, fontSize: 12),
                  ),
                ),
                for (final name in listing.others)
                  ListTile(dense: true, enabled: false, title: Text(name)),
              ],
            ],
          ),
        );
      },
    );
  }
}
