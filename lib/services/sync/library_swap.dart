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
import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_file_set.dart';
import 'swap_journal.dart';
import 'sync_state_store.dart';

/// Where set-aside libraries wait for an Undo: `KoboldManager/sync/r/<n>`.
/// Short on purpose, since a character's deepest file must stay under
/// Windows' path length limit beneath it.
const kAsideFolder = 'KoboldManager/sync/r';

/// The sidecar files SQLite may keep beside a database.
const _dbSidecars = ['-journal', '-wal', '-shm'];

String _rel(String root, String abs) =>
    p.split(p.relative(abs, from: root)).join('/');

/// Plans swapping in [incomingDb] and [incomingFiles] (staged under [root]),
/// with every local library file they replace, and every one in
/// [removePaths], set aside in a new `r/<n>` folder.
///
/// The live database is moved aside first, not copied: the move also
/// proves no second copy of the app holds it, and a late write can't be
/// lost. The incoming database moves in last.
Future<({SwapJournal journal, String aside})> planLibrarySwap({
  required String root,
  required String dbPath,
  required File incomingDb,
  required Map<String, File> incomingFiles,
  required Set<String> removePaths,
  required SwapFinish Function(String aside) finish,
}) async {
  final aside = await _newAsideFolder(root);
  final dbRel = _rel(root, dbPath);
  final moves = <SwapMove>[];
  for (final suffix in ['', ..._dbSidecars]) {
    if (await File('$dbPath$suffix').exists()) {
      moves.add(
        SwapMove('$dbRel$suffix', '$aside/db/${p.basename(dbPath)}$suffix'),
      );
    }
  }
  for (final path in {...incomingFiles.keys, ...removePaths}) {
    if (await libraryFileAt(root, path).exists()) {
      moves.add(SwapMove(path, '$aside/files/$path'));
    }
  }
  final asideCount = moves.length;
  for (final entry in incomingFiles.entries) {
    moves.add(SwapMove(_rel(root, entry.value.path), entry.key));
  }
  moves.add(SwapMove(_rel(root, incomingDb.path), dbRel));

  await Directory(
    p.joinAll([root, ...aside.split('/')]),
  ).create(recursive: true);
  // What the swap brought in, so an Undo knows what to take back out.
  await File(p.joinAll([root, ...aside.split('/'), 'undo.json'])).writeAsString(
    jsonEncode({'movedIn': incomingFiles.keys.toList()..sort()}),
    flush: true,
  );
  return (
    journal: SwapJournal(
      moves: moves,
      asideCount: asideCount,
      finish: finish(aside),
    ),
    aside: aside,
  );
}

Future<String> _newAsideFolder(String root) async {
  final base = Directory(p.joinAll([root, ...kAsideFolder.split('/')]));
  var n = 1;
  if (await base.exists()) {
    await for (final e in base.list()) {
      final k = int.tryParse(p.basename(e.path));
      if (k != null && k >= n) n = k + 1;
    }
  }
  return '$kAsideFolder/$n';
}

/// What an Undo of the Get that set [undo] aside swaps back in: that
/// folder's database and files, removing what the Get brought in.
Future<
  ({
    File db,
    Map<String, File> files,
    Set<String> remove,
    Map<String, Object?>? prefs,
  })?
>
undoSources(String root, UndoRecord undo, String dbName) async {
  final dir = Directory(p.joinAll([root, ...undo.folder.split('/')]));
  final db = File(p.join(dir.path, 'db', dbName));
  if (!await db.exists()) return null;
  final files = <String, File>{};
  final filesDir = Directory(p.join(dir.path, 'files'));
  if (await filesDir.exists()) {
    await for (final e in filesDir.list(recursive: true, followLinks: false)) {
      if (e is File) files[_rel(filesDir.path, e.path)] = e;
    }
  }
  final remove = <String>{};
  final record = File(p.join(dir.path, 'undo.json'));
  if (await record.exists()) {
    final json = jsonDecode(await record.readAsString()) as Map;
    for (final path in json['movedIn'] as List? ?? const []) {
      if (!files.containsKey(path)) remove.add(path as String);
    }
  }
  // The library prefs the swap saved beside what it set aside.
  final saved = File(p.join(dir.path, 'prefs.json'));
  final prefs = await saved.exists()
      ? Map<String, Object?>.from(jsonDecode(await saved.readAsString()) as Map)
      : null;
  return (db: db, files: files, remove: remove, prefs: prefs);
}

/// Deletes set-aside libraries nothing can undo to any more: everything
/// in `r/` except [keep].
Future<void> pruneAsideFolders(String root, {String? keep}) async {
  final base = Directory(p.joinAll([root, ...kAsideFolder.split('/')]));
  if (!await base.exists()) return;
  await for (final e in base.list()) {
    if (keep != null && _rel(root, e.path) == keep) continue;
    await e.delete(recursive: true);
  }
}
