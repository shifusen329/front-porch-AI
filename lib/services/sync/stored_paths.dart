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

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import 'package:front_porch_ai/database/database.dart';

import 'path_rebase.dart';

/// Moves every full path the library stores onto [rebase]'s target root:
/// chat photos (message and swipe metadata), story cast portraits and
/// persona avatars. Character and gallery rows store bare file names and
/// need nothing. Run inside the caller's transaction.
Future<void> rebaseStoredPaths(AppDatabase db, PathRebase rebase) async {
  await _rebaseJsonColumn(db, 'messages', 'metadata', rebase);
  await _rebaseJsonColumn(db, 'messages', 'swipe_metadata', rebase);
  await _rebaseJsonColumn(db, 'story_projects', 'data', rebase);
  final personas = await db
      .customSelect(
        'SELECT id, avatar_path FROM personas WHERE avatar_path IS NOT NULL',
      )
      .get();
  for (final row in personas) {
    final stored = row.read<String>('avatar_path');
    final moved = rebase.rebase(stored);
    if (moved != stored) {
      await db.customUpdate(
        'UPDATE personas SET avatar_path = ? WHERE id = ?',
        variables: [Variable(moved), Variable(row.read<String>('id'))],
      );
    }
  }
}

Future<void> _rebaseJsonColumn(
  AppDatabase db,
  String table,
  String column,
  PathRebase rebase,
) async {
  final rows = await db
      .customSelect(
        'SELECT id AS k, "$column" AS v FROM "$table" '
        // Every key in kPathJsonKeys contains "path" or is "portrait".
        'WHERE "$column" LIKE \'%path%\' OR "$column" LIKE \'%portrait%\'',
      )
      .get();
  for (final row in rows) {
    final raw = row.read<String>('v');
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      continue;
    }
    if (!rebaseJsonPaths(decoded, rebase)) continue;
    await db.customUpdate(
      'UPDATE "$table" SET "$column" = ? WHERE id = ?',
      variables: [
        Variable(jsonEncode(decoded)),
        Variable(row.read<String>('k')),
      ],
    );
  }
}

/// After Change Data Directory moved the library from [oldRoot] to
/// [newRoot]: chat photos and persona avatars still named the old folder,
/// so they broke after every move. Rewrites them in the moved database,
/// which must be closed; opens are held so nothing else opens it meanwhile.
Future<void> rebaseLibraryAfterMove({
  required String oldRoot,
  required String newRoot,
}) async {
  final release = AppDatabase.holdOpens();
  final db = AppDatabase.forReunification(await AppDatabase.locateFile());
  try {
    await db.transaction(
      () => rebaseStoredPaths(
        db,
        PathRebase(sourceRoot: oldRoot, targetRoot: newRoot),
      ),
    );
  } finally {
    await db.close();
    release();
  }
}
