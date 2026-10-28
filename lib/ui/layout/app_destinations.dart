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

/// Where a destination lives in the phone shell.
enum PhonePlacement {
  /// A bottom-bar tab.
  tab,

  /// A row of the Characters tab's "New" sheet.
  createSheet,

  /// A row of the More tab.
  more,

  /// An outbound link under More → Community.
  community,

  /// Not offered on a phone; [AppDestination.hiddenBecause] says why.
  hidden,
}

/// One place the app can take the user, and where it sits on a phone.
/// Every desktop sidebar entry has exactly one row
/// (test/hygiene/destination_registry_test.dart), so a new desktop
/// destination cannot ship without a decision about the phone.
class AppDestination {
  const AppDestination(
    this.id,
    this.label,
    this.icon,
    this.phone, {
    this.desktopLabel,
    this.hiddenBecause,
  });

  final String id;

  /// What the phone calls it.
  final String label;
  final IconData icon;
  final PhonePlacement phone;

  /// The desktop sidebar's label, or null for a phone-only destination.
  final String? desktopLabel;

  /// Required for [PhonePlacement.hidden].
  final String? hiddenBecause;
}

/// The community links, shared by the desktop sidebar and the phone's More.
const kDiscordInviteUrl = 'https://discord.gg/e4tET6rpdv';
const kKofiUrl = 'https://ko-fi.com/sosukeaizen37411';

const kChatsDestination = 'chats';
const kCharactersDestination = 'characters';
const kStoopDestination = 'stoop';
const kStoriesDestination = 'stories';
const kMoreDestination = 'more';

/// In bottom-bar order for tabs, then sheet and More order.
const appDestinations = <AppDestination>[
  AppDestination(
    kChatsDestination,
    'Chats',
    Icons.chat_bubble_outline,
    PhonePlacement.tab,
  ),
  AppDestination(
    kCharactersDestination,
    'Characters',
    Icons.people_outline,
    PhonePlacement.tab,
    desktopLabel: 'Home',
  ),
  AppDestination(
    kStoopDestination,
    'Stoop',
    Icons.travel_explore,
    PhonePlacement.tab,
    desktopLabel: 'The Stoop',
  ),
  AppDestination(
    kStoriesDestination,
    'Stories',
    Icons.auto_stories_outlined,
    PhonePlacement.tab,
  ),
  AppDestination(kMoreDestination, 'More', Icons.menu, PhonePlacement.tab),
  AppDestination(
    'ai_creator',
    'Create with AI',
    Icons.psychology,
    PhonePlacement.createSheet,
    desktopLabel: 'AI Character Creator',
  ),
  AppDestination(
    'create_character',
    'Create Character',
    Icons.add_circle_outline,
    PhonePlacement.createSheet,
    desktopLabel: 'Create Character',
  ),
  AppDestination(
    'create_group',
    'Create Group Chat',
    Icons.group_add_outlined,
    PhonePlacement.createSheet,
    desktopLabel: 'Create Group Chat',
  ),
  AppDestination(
    'personas',
    'Personas',
    Icons.person_outline,
    PhonePlacement.more,
    desktopLabel: 'User Persona',
  ),
  AppDestination(
    'worlds',
    'Worlds',
    Icons.public,
    PhonePlacement.more,
    desktopLabel: 'Worlds',
  ),
  AppDestination(
    'image_studio',
    'Image Studio',
    Icons.auto_awesome,
    PhonePlacement.more,
    desktopLabel: 'Image Studio',
  ),
  AppDestination(
    'backups',
    'Backups & Restore',
    Icons.settings_backup_restore,
    PhonePlacement.more,
    desktopLabel: 'Backups & Restore',
  ),
  AppDestination(
    'settings',
    'Settings',
    Icons.settings_outlined,
    PhonePlacement.more,
    desktopLabel: 'Settings',
  ),
  AppDestination(
    'discord',
    'Join the Discord',
    Icons.discord,
    PhonePlacement.community,
    desktopLabel: 'Join the Discord',
  ),
  AppDestination(
    'coffee',
    'Buy Me a Coffee',
    Icons.coffee_outlined,
    PhonePlacement.community,
    desktopLabel: 'Buy Me a Coffee ☕',
  ),
  AppDestination(
    'manage_models',
    'Manage Models',
    Icons.storage,
    PhonePlacement.hidden,
    desktopLabel: 'Manage Models',
    hiddenBecause:
        'It manages GGUF files for the app-run KoboldCpp, which a phone '
        'cannot run; a remote host picks its model in Settings → Backend.',
  ),
];

Iterable<AppDestination> destinationsPlaced(PhonePlacement placement) =>
    appDestinations.where((d) => d.phone == placement);
