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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// The gallery's footer while selecting: the count, Select all, Select every
/// "<label>" for the last emotion picked, Cancel, and Delete N. Wraps on a
/// phone instead of overflowing.
class GallerySelectBar extends StatelessWidget {
  const GallerySelectBar({
    super.key,
    required this.count,
    required this.onSelectAll,
    required this.labelToSelect,
    required this.onSelectLabel,
    required this.onCancel,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onSelectAll;

  /// The last expression picked has alternates under this label; null hides
  /// "Select every".
  final String? labelToSelect;
  final VoidCallback onSelectLabel;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: onSelectAll,
                child: const Text('Select all'),
              ),
              if (labelToSelect != null)
                TextButton(
                  onPressed: onSelectLabel,
                  child: Text('Select every "$labelToSelect"'),
                ),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: StatusColors.dangerOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                ),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text('Delete $count'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Deleted 42 images · Undo", inside the gallery: a snackbar from the
/// dialog would sit under its barrier where Undo can't be tapped.
class GalleryUndoBanner extends StatelessWidget {
  const GalleryUndoBanner({
    super.key,
    required this.message,
    required this.onUndo,
  });

  final String message;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.delete_sweep_outlined,
            size: 18,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          TextButton(onPressed: onUndo, child: const Text('Undo')),
        ],
      ),
    );
  }
}
