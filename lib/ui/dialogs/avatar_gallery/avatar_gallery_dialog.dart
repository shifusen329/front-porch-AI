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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_bulk_actions.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_expressions_section.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_looks_section.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_select_bar.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_selection.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/emotion_picker.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The one unified Avatar Gallery — gallery avatars + expression images in a
/// single warm-porch dialog, sharing one ★ canonical-avatar star. Replaces the
/// old glassmorphic `character_avatars_dialog.dart`.
///
/// [character] MUST be the origin LIBRARY card (the caller resolves group members
/// first). [mode] is caller-passed: [WardrobeMode.inChat] enables per-chat
/// selection and needs [chatService].
Future<void> showAvatarGallery({
  required BuildContext context,
  required CharacterCard character,
  required CharacterRepository repository,
  required StorageService storage,
  required WardrobeMode mode,
  ChatService? chatService,
}) {
  if (character.dbId == null) return Future.value();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _AvatarGalleryDialog(
      controller: AvatarGalleryController(
        libraryCard: character,
        repository: repository,
        storage: storage,
        mode: mode,
        chat: chatService,
      ),
    ),
  );
}

class _AvatarGalleryDialog extends StatefulWidget {
  const _AvatarGalleryDialog({required this.controller});
  final AvatarGalleryController controller;

  @override
  State<_AvatarGalleryDialog> createState() => _AvatarGalleryDialogState();
}

class _AvatarGalleryDialogState extends State<_AvatarGalleryDialog> {
  AvatarGalleryController get _c => widget.controller;
  final _sel = AvatarGallerySelection();

  /// Set from the first tap of a Delete until it settles: a second tap in
  /// the same frame must not open a second confirm or delete twice.
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _sel.addListener(_onSelection);
    _c.init();
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _sel.removeListener(_onSelection);
    _sel.dispose();
    _c.dispose();
    super.dispose();
  }

  void _onSelection() {
    if (mounted) setState(() {});
  }

  void _onChange() {
    if (!mounted) return;
    final err = _c.lastError;
    if (err != null) {
      _c.lastError = null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Something went wrong: $err')));
    }
    _sel.keepOnly(_c.looks.followedBy(_c.expressions).map((a) => a.id));
    setState(() {});
  }

  // ── Add flows (pickers live here; the controller does the persistence) ──────
  Future<void> _addLook() async {
    final bytes = await pickImageBytes(context);
    if (bytes != null) await _c.addLook(bytes);
  }

  Future<void> _replacePortrait() async {
    final bytes = await pickImageBytes(context);
    if (bytes == null || !mounted) return;
    final cropped = await ImageCropDialog.show(context, imageBytes: bytes);
    if (cropped == null) return;
    await _c.replacePortrait(cropped);
  }

  Future<void> _addExpression() async {
    final bytes = await pickImageBytes(context);
    if (bytes == null || !mounted) return;
    final emotion = await _pickEmotion(_c.usedLabels, preview: bytes);
    if (emotion == null) return;
    await _c.addExpression(bytes, emotion);
  }

  Future<void> _relabel(String avatarId) async {
    final emotion = await _pickEmotion(_c.usedLabelsExcept(avatarId));
    if (emotion != null) _c.setLabelDraft(avatarId, emotion);
  }

  Future<void> _importZip() async {
    final zip = await pickZipBytes(context);
    if (zip == null) return;
    final pack = decodeSpritePack(
      zip,
      labels: _c.storage.expressionSettings.expressionLabels,
    );
    if (!mounted) return;
    if (pack.entries.isEmpty) {
      // Nothing to put in their place, so nothing here is touched.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing in that ZIP is named for an expression. The gallery '
            'was not changed.',
          ),
        ),
      );
      return;
    }
    var replace = false;
    if (_c.expressions.isNotEmpty) {
      final mode = await askPackImportMode(
        context,
        existing: _c.expressions.length,
        incoming: pack.entries.length,
      );
      if (mode == null) return;
      replace = mode == PackImportMode.replace;
    }
    final (added, unrecognized, skipped) = await _c.importSpritePack(
      [for (final e in pack.entries) (bytes: e.bytes, emotion: e.emotion)],
      pack.unrecognized,
      replace: replace,
    );
    if (!mounted) return;
    final parts = <String>[
      'Imported $added',
      if (skipped > 0) '$skipped skipped ($kMaxExpressions expressions)',
      if (unrecognized > 0) '$unrecognized unrecognized',
    ];
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(parts.join(' · '))));
  }

  /// Past the expression limit only the expressions in [used] are offered.
  Future<String?> _pickEmotion(Set<String> used, {Uint8List? preview}) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dctx) => Dialog(
        backgroundColor: AppColors.surfaceOf(dctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: EmotionPicker(
              previewBytes: preview,
              labels: labelsThatFit(
                _c.storage.expressionSettings.expressionLabels,
                used,
              ),
              onPick: (e) => Navigator.pop(dctx, e),
              onCancel: () => Navigator.pop(dctx),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String avatarId) async {
    final img =
        _c.looks.where((l) => l.id == avatarId).firstOrNull ??
        _c.expressions.where((e) => e.id == avatarId).firstOrNull;
    if (img == null) return;
    final ok = await showWarmDialog<bool>(
      context,
      title: 'Delete this image?',
      content: const WarmDialogText(
        'This removes it from the gallery. It won\'t touch the portrait.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Delete',
          destructive: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok == true) await _c.remove(img);
  }

  /// Delete N from the select bar: one confirm with the count and a strip
  /// of thumbnails, then one batch.
  Future<void> _deleteSelected() async {
    if (_deleting || _sel.count == 0) return;
    _deleting = true;
    try {
      final picked = [
        for (final a in _c.looks.followedBy(_c.expressions))
          if (_sel.contains(a.id)) a,
      ];
      final ok = await confirmGalleryDelete(context, [
        for (final a in picked) _c.fileFor(a),
      ]);
      if (!ok || !mounted) return;
      _sel.cancel();
      await _c.removeMany(picked.map((a) => a.id));
    } finally {
      _deleting = false;
    }
  }

  /// Clear looks / Clear expressions from a section's ⋮ menu.
  Future<void> _clear({required bool looks}) async {
    final count = (looks ? _c.looks : _c.expressions).length;
    if (_deleting || count == 0) return;
    _deleting = true;
    try {
      final ok = await confirmGalleryClear(context, looks: looks, count: count);
      if (ok && mounted) await _c.clear(looks: looks);
    } finally {
      _deleting = false;
    }
  }

  Future<void> _confirmDeletePortrait() async {
    // The SAME selection rule the action uses (portrait_promotion.dart), so
    // the preview can never show a different image than the one promoted —
    // the Discord report's confusion was exactly not knowing WHICH image
    // would move into the portrait slot.
    final candidate = promotionCandidate(_c.looks, _c.favoriteId);
    if (candidate == null) return; // affordance is hidden with no looks
    final ok = await confirmPortraitSwap(
      context,
      _c.fileFor(candidate),
      starred: candidate.id == _c.favoriteId,
    );
    if (ok) await _c.deletePortrait();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AvatarGalleryLooksSection(
                      controller: _c,
                      onAddLook: _addLook,
                      onReplacePortrait: _replacePortrait,
                      onDelete: _confirmDelete,
                      onDeletePortrait: _confirmDeletePortrait,
                      selection: _sel,
                      onClear: () => _clear(looks: true),
                    ),
                    const SizedBox(height: 22),
                    Divider(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 14),
                    AvatarGalleryExpressionsSection(
                      controller: _c,
                      onAddExpression: _addExpression,
                      onImportZip: _importZip,
                      onExpand: () {
                        _c.expressionsExpanded = true;
                        _onChange();
                        _addExpression();
                      },
                      onRelabel: _relabel,
                      onDelete: _confirmDelete,
                      selection: _sel,
                      onClear: () => _clear(looks: false),
                    ),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    if (_sel.active) {
      final label = _sel.last?.label?.trim() ?? '';
      final alternates = label.isEmpty
          ? 0
          : _c.expressions
                .where(
                  (e) =>
                      (e.label ?? '').trim().toLowerCase() ==
                      label.toLowerCase(),
                )
                .length;
      return GallerySelectBar(
        count: _sel.count,
        onSelectAll: () => _sel.selectAll(_c.looks.followedBy(_c.expressions)),
        labelToSelect: alternates > 1 ? label : null,
        onSelectLabel: () => _sel.selectLabel(label, _c.expressions),
        onCancel: _sel.cancel,
        onDelete: _sel.count == 0 ? null : _deleteSelected,
      );
    }
    final undo = _c.pendingUndo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (undo != null)
          GalleryUndoBanner(
            message: undo.added.isNotEmpty
                ? 'Replaced ${undo.count} expression '
                      '${undo.count == 1 ? 'image' : 'images'} with '
                      '${undo.added.length} from the pack'
                : 'Deleted ${undo.count} ${undo.count == 1 ? 'image' : 'images'}',
            onUndo: _c.undo,
          ),
        _actionBar(),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.photo_library_outlined,
            color: AppColors.formAccentOf(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Avatar Gallery — ${_c.libraryCard.name}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          if (_c.saving)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          IconButton(
            tooltip: 'Close',
            icon: Icon(Icons.close, color: AppColors.iconSecondary(context)),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '${_c.looks.length} gallery · ${_c.expressions.length} expressions'
              '${_c.expressions.isEmpty ? '' : ' · emotion labels save on Done'}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _c.saving
                ? null
                : () async {
                    await _c.flushOnDone();
                    if (mounted) Navigator.of(context).pop();
                  },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
