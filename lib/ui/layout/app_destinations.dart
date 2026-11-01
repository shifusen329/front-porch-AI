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

  /// In the bottom bar, but it opens its page over the tabs instead of
  /// becoming one.
  barButton,

  /// A sub-tab of the Porch tab.
  porch,

  /// A row of the Characters "New" sheet.
  createSheet,

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

const kChatsDestination = 'chats';
const kPorchDestination = 'porch';
const kSettingsDestination = 'settings';
const kCharactersDestination = 'characters';
const kPersonasDestination = 'personas';
const kWorldsDestination = 'worlds';
const kStoriesDestination = 'stories';
const kStoopDestination = 'stoop';

/// In bottom-bar order for tabs and bar buttons, then Porch and sheet order.
const appDestinations = <AppDestination>[
  AppDestination(
    kChatsDestination,
    'Chats',
    Icons.chat_bubble_outline,
    PhonePlacement.tab,
  ),
  AppDestination(
    kPorchDestination,
    'Porch',
    Icons.deck_outlined,
    PhonePlacement.tab,
  ),
  AppDestination(
    'image_studio',
    'Images',
    Icons.auto_awesome,
    PhonePlacement.barButton,
    desktopLabel: 'Image Studio',
  ),
  AppDestination(
    kSettingsDestination,
    'Settings',
    Icons.settings_outlined,
    PhonePlacement.tab,
    desktopLabel: 'Settings',
  ),
  AppDestination(
    kCharactersDestination,
    'Characters',
    Icons.people_outline,
    PhonePlacement.porch,
    desktopLabel: 'Home',
  ),
  AppDestination(
    kPersonasDestination,
    'Personas',
    Icons.person_outline,
    PhonePlacement.porch,
    desktopLabel: 'User Persona',
  ),
  AppDestination(
    kWorldsDestination,
    'Worlds',
    Icons.public,
    PhonePlacement.porch,
    desktopLabel: 'Worlds',
  ),
  AppDestination(
    kStoriesDestination,
    'Stories',
    Icons.auto_stories_outlined,
    PhonePlacement.porch,
  ),
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
  // Phone only: the desktop sidebar has no Stoop button.
  AppDestination(
    kStoopDestination,
    'Browse The Stoop',
    Icons.travel_explore,
    PhonePlacement.createSheet,
  ),
  AppDestination(
    'backups',
    'Backups & Restore',
    Icons.settings_backup_restore,
    PhonePlacement.hidden,
    desktopLabel: 'Backups & Restore',
    hiddenBecause: 'A phone opens it as the Backups tab in Settings.',
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

/// What the bottom bar (or rail) shows, in order: the tabs and the buttons.
Iterable<AppDestination> get phoneBarItems => appDestinations.where(
  (d) => d.phone == PhonePlacement.tab || d.phone == PhonePlacement.barButton,
);
