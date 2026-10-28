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

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/mobile/shell/destination_actions.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The phone's More tab: the desktop sidebar's long tail (Personas, Worlds,
/// Image Studio, Backups, Settings), the community links, and About.
class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          for (final d in destinationsPlaced(PhonePlacement.more))
            _DestinationTile(destination: d),
          const _SectionLabel('COMMUNITY'),
          for (final d in destinationsPlaced(PhonePlacement.community))
            _DestinationTile(destination: d, external: true),
          ListTile(
            leading: Icon(
              Icons.info_outline,
              color: AppColors.iconSecondary(context),
            ),
            title: const Text('About'),
            subtitle: const Text('v$appVersion'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showWarmDialog<void>(
              context,
              title: 'Front Porch AI',
              icon: Icons.info_outline,
              content: const WarmDialogText(
                'Version $appVersion\n\n'
                'Free software under the GNU Affero General Public License, '
                'version 3 or later.',
              ),
              actions: [warmDialogCancel(context, label: 'OK')],
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.destination, this.external = false});

  final AppDestination destination;

  /// Opens outside the app, so it says so instead of showing a chevron.
  final bool external;

  @override
  Widget build(BuildContext context) {
    final color = switch (destination.id) {
      'discord' => NavColors.discord,
      'coffee' => NavColors.kofi,
      _ => AppColors.iconSecondary(context),
    };
    return ListTile(
      leading: Icon(destination.icon, color: color),
      title: Text(destination.label),
      trailing: Icon(external ? Icons.open_in_new : Icons.chevron_right),
      onTap: () => phoneDestinationActions[destination.id]?.call(context),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textTertiary(context),
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
