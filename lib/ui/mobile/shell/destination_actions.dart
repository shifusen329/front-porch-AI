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
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/ui/image_studio/home_image_studio.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

typedef DestinationAction = Future<void> Function(BuildContext context);

/// What opening each destination that is not a tab does on a phone, keyed
/// by [AppDestination.id]. Pages open full screen over the tab bar, on the
/// app's one navigator. test/hygiene/destination_registry_test.dart checks
/// every sheet, More and community row has an entry here.
final Map<String, DestinationAction> phoneDestinationActions = {
  'ai_creator': (c) => _push(c, const CharacterCreatorPage()),
  'create_character': (c) => _push(c, const CreateCharacterPage(asRoute: true)),
  'create_group': (c) => _push(c, const CreateGroupChatPage()),
  'personas': (c) => _push(c, const UserPersonaPage()),
  // The desktop shows Worlds as a sidebar tab with no app bar of its own.
  'worlds': (c) => _push(
    c,
    Scaffold(
      appBar: AppBar(title: const Text('Worlds')),
      body: const WorldManagementPage(),
    ),
  ),
  'image_studio': showHomeImageStudio,
  'backups': (c) => _push(c, const BackupsPage()),
  'settings': (c) => _push(c, const SettingsPage()),
  'discord': (_) => _openLink(kDiscordInviteUrl),
  'coffee': (_) => _openLink(kKofiUrl),
};

Future<void> _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

Future<void> _openLink(String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    debugPrint('[More] could not open $url');
  }
}
