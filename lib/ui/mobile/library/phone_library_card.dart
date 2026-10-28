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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/cards/character_grid_card_face.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// What every phone library card shares: a 3:4 picture with the name and a
/// line of activity on a scrim, an always-visible ⋮ (there is no hover to
/// reveal it), and a check when the card is picked in selection mode.
class _PhoneCardFrame extends StatelessWidget {
  const _PhoneCardFrame({
    required this.art,
    required this.name,
    required this.meta,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onMenu,
    this.isGroup = false,
  });

  final Widget art;
  final String name;
  final String? meta;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final radius = AppCorners.of(context).circular(16);
    final terracotta = AppColors.porchTerracottaOf(context);
    final ink = AppColors.textPrimary(context);
    return Semantics(
      button: true,
      label: meta == null ? name : '$name, $meta',
      selected: selecting ? selected : null,
      child: Material(
        color: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? BorderSide(color: AppColors.porchAmberOf(context), width: 2.5)
              : isGroup
              ? BorderSide(color: terracotta.withValues(alpha: 0.55))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onMenu,
          child: Stack(
            fit: StackFit.expand,
            children: [
              art,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.cardOf(context).withValues(alpha: 0),
                        AppColors.cardOf(context).withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (meta != null)
                          Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isGroup)
                Positioned(
                  top: 10,
                  left: 10,
                  child: _Badge(
                    icon: Icons.groups,
                    label: 'Group',
                    color: terracotta,
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: selecting
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? AppColors.porchAmberOf(context)
                              : ink,
                        ),
                      )
                    : IconButton(
                        tooltip: 'Actions for $name',
                        onPressed: onMenu,
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.cardOf(
                            context,
                          ).withValues(alpha: 0.72),
                          child: Icon(Icons.more_vert, size: 18, color: ink),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A character in the phone library.
class PhoneCharacterCard extends StatelessWidget {
  const PhoneCharacterCard({
    super.key,
    required this.character,
    required this.image,
    required this.imageCacheEpoch,
    required this.meta,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onMenu,
  });

  final CharacterCard character;
  final File Function(CharacterCard card) image;
  final int imageCacheEpoch;
  final String? meta;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return _PhoneCardFrame(
      art: character.imagePath != null
          ? CharacterGridCardCover(
              character: character,
              file: image(character),
              imageCacheEpoch: imageCacheEpoch,
              size: 64,
            )
          : const CharacterGridCardNoPortrait(size: 64),
      name: character.name,
      meta: meta,
      selected: selected,
      selecting: selecting,
      onTap: onTap,
      onMenu: onMenu,
    );
  }
}

/// A group cast in the phone library, with its members' montage.
class PhoneGroupCard extends StatelessWidget {
  const PhoneGroupCard({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onMenu,
  });

  final GroupChat group;
  final GroupChatRepository groupRepo;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return _PhoneCardFrame(
      isGroup: true,
      art: LayoutBuilder(
        builder: (context, box) => PhoneGroupMontage(
          group: group,
          groupRepo: groupRepo,
          side: box.maxWidth,
        ),
      ),
      name: group.name,
      meta: null,
      selected: selected,
      selecting: selecting,
      onTap: onTap,
      onMenu: onMenu,
    );
  }
}

/// Up to four member portraits of a group, tiled into a square of [side].
class PhoneGroupMontage extends StatefulWidget {
  const PhoneGroupMontage({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.side,
  });

  final GroupChat group;
  final GroupChatRepository groupRepo;
  final double side;

  @override
  State<PhoneGroupMontage> createState() => _PhoneGroupMontageState();
}

class _PhoneGroupMontageState extends State<PhoneGroupMontage> {
  late Future<List<File>> _avatars = widget.groupRepo.getMemberAvatarFiles(
    widget.group.id,
  );

  @override
  void didUpdateWidget(PhoneGroupMontage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A repository reload hands out a new GroupChat after any edit.
    if (!identical(oldWidget.group, widget.group)) {
      _avatars = widget.groupRepo.getMemberAvatarFiles(widget.group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<File>>(
      future: _avatars,
      builder: (context, snap) => GroupAvatarMontage(
        images: (snap.data ?? const <File>[]).take(4).toList(),
        side: widget.side,
      ),
    );
  }
}
