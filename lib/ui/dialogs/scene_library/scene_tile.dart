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

import 'package:front_porch_ai/services/scenes/scenes.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'scene_place_form.dart';

/// One scene picture: the place under it, its time, a tap to rename and a
/// ✕ to delete. [showing] marks the one the chat has on screen.
class SceneTile extends StatelessWidget {
  const SceneTile({
    super.key,
    required this.scene,
    required this.showing,
    required this.onEdit,
    required this.onDelete,
  });

  final SceneImage scene;
  final bool showing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final label = [
      scene.place,
      if (scene.time != null) sceneTimeLabel(scene.time).toLowerCase(),
      if (scene.alt > 0) '#${scene.alt}',
    ].join(' · ');
    return Material(
      key: ValueKey('scene-tile-${scene.name}'),
      color: AppColors.cardOf(context),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: showing ? accent : AppColors.borderOf(context),
              width: showing ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      scene.file,
                      fit: BoxFit.cover,
                      cacheWidth: (160 * dpr).round(),
                      errorBuilder: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.iconSecondary(context),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton.filledTonal(
                        key: ValueKey('scene-delete-${scene.name}'),
                        tooltip: 'Delete',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: onDelete,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: showing ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
