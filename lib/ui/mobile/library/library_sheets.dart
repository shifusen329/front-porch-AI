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

import 'package:front_porch_ai/ui/layout/layout.dart';
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/toolbar/home_toolbar_controls.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Phone-only: starts selection mode with the card already picked.
const kSelectCardAction = 'select';

/// Phone-only row of the "New" sheet.
const kImportCardAction = 'import_card';

/// A card's actions as a sheet: the desktop right-click menu's entries and
/// values, so the same handler runs them, plus Select.
Future<String?> showCardActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<CardMenuEntry> entries,
}) {
  final rows = [
    ...entries.where((e) => e.tone != CardMenuTone.danger),
    const CardMenuEntry(kSelectCardAction, Icons.check_box_outlined, 'Select'),
  ];
  final danger = entries.where((e) => e.tone == CardMenuTone.danger);
  return showWarmSheet<String>(
    context,
    builder: (sheet) => _SheetList(
      header: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
      ),
      children: [
        for (final e in rows) _EntryTile(entry: e),
        if (danger.isNotEmpty) const Divider(),
        for (final e in danger) _EntryTile(entry: e),
      ],
    ),
  );
}

/// The Characters "New" sheet: the creation destinations and the Stoop,
/// then importing a card. Returns a destination id or [kImportCardAction].
Future<String?> showCreateSheet(BuildContext context) {
  return showWarmSheet<String>(
    context,
    builder: (sheet) => _SheetList(
      children: [
        for (final d in destinationsPlaced(PhonePlacement.createSheet))
          ListTile(
            leading: Icon(
              d.icon,
              color: switch (d.id) {
                'ai_creator' => NavColors.creatorOf(sheet),
                // The desktop sidebar's Stoop teal.
                kStoopDestination => NavColors.stoopOf(sheet),
                _ => AppColors.iconSecondary(sheet),
              },
            ),
            title: Text(d.label),
            onTap: () => Navigator.of(sheet).pop(d.id),
          ),
        ListTile(
          leading: Icon(
            Icons.file_download_outlined,
            color: AppColors.iconSecondary(sheet),
          ),
          title: const Text('Import character card'),
          subtitle: const Text('PNG, JSON, CHARX or BYAF'),
          onTap: () => Navigator.of(sheet).pop(kImportCardAction),
        ),
      ],
    ),
  );
}

/// Picks one of the library's sort orders.
Future<String?> showSortSheet(BuildContext context, {required String current}) {
  return showWarmSheet<String>(
    context,
    builder: (sheet) => _SheetList(
      header: const ListTile(
        title: Text('Sort by', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      children: [
        RadioGroup<String>(
          groupValue: current,
          onChanged: (mode) => Navigator.of(sheet).pop(mode),
          child: Column(
            children: [
              for (final (mode, label) in kHomeToolbarSortItems)
                RadioListTile<String>(value: mode, title: Text(label)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SheetList extends StatelessWidget {
  const _SheetList({this.header, required this.children});

  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [?header, if (header != null) const Divider(), ...children],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final CardMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(entry.icon, color: entry.iconColor(context)),
      title: Text(
        entry.label,
        style: TextStyle(color: entry.labelColor(context)),
      ),
      onTap: () => Navigator.of(context).pop(entry.value),
    );
  }
}
