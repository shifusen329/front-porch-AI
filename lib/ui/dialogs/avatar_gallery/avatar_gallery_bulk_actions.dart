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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Answers a warm dialog once: a second tap in the same frame would
/// otherwise pop the gallery underneath too.
class _Once<T> {
  _Once(this.context);
  final BuildContext context;
  bool _done = false;

  void call(T value) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(value);
  }
}

/// "Delete 12 images?" with a strip of the first few, for Delete N.
Future<bool> confirmGalleryDelete(
  BuildContext context,
  List<File> pictures,
) async {
  final answer = _Once<bool>(context);
  final n = pictures.length;
  final ok = await showWarmDialog<bool>(
    context,
    title: n == 1 ? 'Delete this image?' : 'Delete $n images?',
    width: 420,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in pictures.take(8))
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  f,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  cacheWidth: kPortraitAvatarDecodeWidth,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.image_outlined,
                    size: 40,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
              ),
            if (n > 8)
              SizedBox(
                height: 44,
                child: Center(child: WarmDialogText('+${n - 8}')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const WarmDialogText(
          'They leave the gallery; the portrait stays. Undo brings them back '
          'for a few seconds.',
        ),
      ],
    ),
    actions: [
      warmDialogCancel(context, value: false),
      warmDialogConfirm(
        context,
        label: n == 1 ? 'Delete' : 'Delete $n',
        destructive: true,
        onPressed: () => answer(true),
      ),
    ],
  );
  return ok == true;
}

/// "Delete all 42 expression images?" for Clear expressions / Clear looks.
Future<bool> confirmGalleryClear(
  BuildContext context, {
  required bool looks,
  required int count,
}) async {
  final answer = _Once<bool>(context);
  final what = looks ? 'gallery looks' : 'expression images';
  final stays = looks
      ? 'The portrait and the expression images stay.'
      : 'The portrait and the gallery looks stay.';
  final ok = await showWarmDialog<bool>(
    context,
    title: 'Delete all $count $what?',
    width: 400,
    content: WarmDialogText('$stays Undo brings them back for a few seconds.'),
    actions: [
      warmDialogCancel(context, value: false),
      warmDialogConfirm(
        context,
        label: 'Delete all',
        destructive: true,
        onPressed: () => answer(true),
      ),
    ],
  );
  return ok == true;
}

/// What a ZIP sprite pack does with the expressions already here.
enum PackImportMode { add, replace }

/// Asked when the character already has expressions. Null is Cancel.
Future<PackImportMode?> askPackImportMode(
  BuildContext context, {
  required int existing,
  required int incoming,
}) {
  final answer = _Once<PackImportMode>(context);
  return showWarmDialog<PackImportMode>(
    context,
    title: 'Add to these, or replace them?',
    width: 420,
    content: WarmDialogText(
      'This character has $existing expression '
      '${existing == 1 ? 'image' : 'images'}, and the pack has $incoming. '
      'Replace deletes the ones here first (the gallery looks stay); Undo '
      'brings them back for a few seconds.',
    ),
    actions: [
      warmDialogCancel(context),
      TextButton(
        onPressed: () => answer(PackImportMode.replace),
        child: Text(
          'Replace them',
          style: TextStyle(color: StatusColors.dangerOf(context)),
        ),
      ),
      warmDialogConfirm(
        context,
        label: 'Add to these',
        onPressed: () => answer(PackImportMode.add),
      ),
    ],
  );
}

/// "Swap the portrait?" with the look that would take its place: [starred]
/// when it is the ★ look, else the first gallery look.
Future<bool> confirmPortraitSwap(
  BuildContext context,
  File candidate, {
  required bool starred,
}) async {
  final ok = await showWarmDialog<bool>(
    context,
    title: 'Swap the portrait?',
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            candidate,
            width: 56,
            height: 56,
            cacheWidth: kPortraitAvatarDecodeWidth,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              Icons.image_outlined,
              size: 40,
              color: AppColors.iconSecondary(context),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: WarmDialogText(
            'This image — ${starred ? 'your ★ starred look' : 'your first '
                      'gallery look'} — becomes the new portrait, and the old '
            'portrait moves into the gallery as a look. Nothing is '
            'deleted; swap back any time.',
          ),
        ),
      ],
    ),
    actions: [
      warmDialogCancel(context),
      warmDialogConfirm(
        context,
        label: 'Swap portrait',
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
  return ok == true;
}
