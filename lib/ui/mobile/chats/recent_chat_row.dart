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

import 'package:front_porch_ai/database/database.dart' show RecentSession;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/mobile/library/phone_library_card.dart';
import 'package:front_porch_ai/ui/pages/home/cards/character_grid_card_face.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart';

const double _kAvatar = 56;

/// One conversation in the Chats tab: who, the chat's own name if it has
/// one, when, and the last thing said.
class RecentChatRow extends StatelessWidget {
  const RecentChatRow({
    super.key,
    required this.session,
    required this.snippet,
    this.character,
    this.group,
    required this.groupRepo,
    required this.imageCacheEpoch,
    required this.onTap,
    required this.onMenu,
  });

  final RecentSession session;
  final String? snippet;
  final CharacterCard? character;
  final GroupChat? group;
  final GroupChatRepository groupRepo;
  final int imageCacheEpoch;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  Widget _avatar(BuildContext context) {
    final character = this.character;
    final group = this.group;
    final Widget art;
    if (group != null) {
      art = PhoneGroupMontage(
        group: group,
        groupRepo: groupRepo,
        side: _kAvatar,
      );
    } else if (character != null && character.imagePath != null) {
      art = CharacterGridCardCover(
        character: character,
        file: resolveHomeCardImage(context, character),
        imageCacheEpoch: imageCacheEpoch,
        size: 24,
      );
    } else {
      art = const CharacterGridCardNoPortrait(size: 24);
    }
    return ClipOval(
      child: SizedBox.square(dimension: _kAvatar, child: art),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = session.sessionName;
    return InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 14,
          children: [
            _avatar(context),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: session.displayName,
                            children: [
                              if (name != null && name.isNotEmpty)
                                TextSpan(
                                  text: ' · $name',
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        formatRelativeTime(session.lastMessageAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                  if (snippet != null)
                    Text(
                      snippet!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
