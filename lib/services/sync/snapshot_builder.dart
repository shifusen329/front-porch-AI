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
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';

import 'library_digest.dart';
import 'library_file_set.dart';
import 'library_prefs.dart';
import 'sync_manifest.dart';

/// The tables counted for status lines and the empty-library check.
const kCountedTables = [
  'characters',
  'sessions',
  'messages',
  'personas',
  'groups',
  'worlds',
];

/// A library packed for sending, still on this device.
class OutgoingSnapshot {
  const OutgoingSnapshot({
    required this.dbGz,
    required this.database,
    required this.files,
    required this.locals,
    required this.counts,
    required this.digest,
    required this.prefs,
  });

  /// The gzipped database copy.
  final File dbGz;
  final SnapshotFile database;
  final List<SnapshotFile> files;

  /// Where each of [files] is on this device.
  final Map<String, File> locals;
  final Map<String, int> counts;
  final LibraryDigest digest;
  final Map<String, Object?> prefs;
}

/// The working folder a Send packs into.
Directory outgoingDir(String root) =>
    Directory(p.join(root, 'KoboldManager', 'sync', 'out'));

/// Packs this device's library: a consistent copy of the database with this
/// device's web logins removed, and every file in [kSyncedFolders].
///
/// The caller holds the library still (no reply, import or editor running)
/// until this returns, so the copy and the files agree.
Future<OutgoingSnapshot> buildOutgoingSnapshot({
  required AppDatabase live,
  required String root,
  required FileHashCache hashes,
  required SharedPreferences prefs,
}) async {
  final out = outgoingDir(root);
  if (await out.exists()) await out.delete(recursive: true);
  await out.create(recursive: true);
  final copy = p.join(out.path, 'library.db');
  await live.customStatement("VACUUM INTO '${copy.replaceAll("'", "''")}'");

  final version = await readSqliteUserVersion(File(copy));
  if (version == null) throw StateError('VACUUM INTO wrote no database');

  // Digested before the scrub below, so it matches what this device's live
  // library digests to (digestLiveLibrary) and an unchanged library reads
  // as unchanged after the Send.
  final listed = await listLibraryFiles(root);
  final listedShas = await hashes.hashAll(listed);
  final digest = await digestLibrary(copy, listedShas);

  final scrubbed = await Isolate.run(
    () => _scrubCopy(copy, version, root, [...kSyncedFolders]),
  );
  final extras = [
    for (final e in scrubbed.extras)
      LibraryFile(
        path: e.path,
        file: File(e.local),
        size: e.size,
        modified: e.modified,
      ),
  ];
  final all = [...listed, ...extras];
  final shas = {
    ...listedShas,
    ...await hashes.hashAll(extras, keepOthers: true),
  };
  await hashes.save();

  final gz = File(p.join(out.path, 'library.db.gz'));
  final database = await Isolate.run(() => _gzip(copy, gz.path));

  final files = <SnapshotFile>[];
  final locals = <String, File>{};
  for (final f in all) {
    final sha = shas[f.path]!;
    final parts = f.size > kBlobPartBytes
        ? await Isolate.run(() => _partsOf(f.file.path))
        : const <BlobRef>[];
    files.add(SnapshotFile(path: f.path, sha: sha, size: f.size, parts: parts));
    locals[f.path] = f.file;
  }
  return OutgoingSnapshot(
    dbGz: gz,
    database: database,
    files: files,
    locals: locals,
    counts: scrubbed.counts,
    digest: digest,
    prefs: readLibraryPrefs(prefs),
  );
}

typedef _Extra = ({String path, String local, int size, DateTime modified});

/// In the copy: drop this device's web logins, point persona avatars that
/// live outside the library at a copy that travels with it, count rows,
/// then VACUUM so the deleted login rows don't linger in free pages.
Future<({Map<String, int> counts, List<_Extra> extras})> _scrubCopy(
  String copy,
  int version,
  String root,
  List<String> synced,
) async {
  final db = NativeDatabase(File(copy));
  try {
    await db.ensureOpen(AsIsDatabase(version));
    final authTables = await db.runSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name LIKE 'web_auth_%'",
      const [],
    );
    for (final row in authTables) {
      await db.runCustom('DELETE FROM "${row['name']}"', const []);
    }

    final extras = <_Extra>[];
    final personas = await db.runSelect(
      'SELECT id, avatar_path FROM personas WHERE avatar_path IS NOT NULL',
      const [],
    );
    for (final row in personas) {
      final stored = row['avatar_path'] as String;
      if (!p.isAbsolute(stored)) continue;
      final inLibrary = synced.any(
        (f) => p.isWithin(p.joinAll([root, ...f.split('/')]), stored),
      );
      if (inLibrary) continue;
      final file = File(stored);
      if (!await file.exists()) continue;
      final name = 'fpai-sync-${row['id']}-${p.basename(stored)}';
      final stat = await file.stat();
      extras.add((
        path: 'persona_avatars/$name',
        local: stored,
        size: stat.size,
        modified: stat.modified,
      ));
      await db.runUpdate('UPDATE personas SET avatar_path = ? WHERE id = ?', [
        p.join(root, 'persona_avatars', name),
        row['id'],
      ]);
    }

    final counts = <String, int>{};
    for (final table in kCountedTables) {
      final rows = await db.runSelect(
        'SELECT COUNT(*) AS n FROM "$table" WHERE deleted_at IS NULL',
        const [],
      );
      counts[table] = rows.first['n'] as int;
    }
    await db.runCustom('VACUUM', const []);
    return (counts: counts, extras: extras);
  } finally {
    await db.close();
  }
}

Future<SnapshotFile> _gzip(String from, String to) async {
  await File(
    from,
  ).openRead().transform(gzip.encoder).pipe(File(to).openWrite());
  final size = await File(to).length();
  final sha = (await sha256.bind(File(to).openRead()).first).toString();
  final parts = size > kBlobPartBytes ? await _partsOf(to) : const <BlobRef>[];
  return SnapshotFile(
    path: 'library.db.gz',
    sha: sha,
    size: size,
    parts: parts,
  );
}

/// The [kBlobPartBytes] pieces of [path], each named by its own sha.
Future<List<BlobRef>> _partsOf(String path) async {
  final file = File(path);
  final size = await file.length();
  final parts = <BlobRef>[];
  for (var start = 0; start < size; start += kBlobPartBytes) {
    final end = (start + kBlobPartBytes).clamp(0, size);
    final sha = await sha256.bind(file.openRead(start, end)).first;
    parts.add(BlobRef(sha.toString(), end - start));
  }
  return parts;
}

/// This device's library digest right now, from a fresh copy of the
/// database (never the live file) and the library files' hashes.
Future<LibraryDigest> digestLiveLibrary({
  required AppDatabase live,
  required String root,
  required FileHashCache hashes,
}) async {
  final dir = Directory(p.join(root, 'KoboldManager', 'sync', 'check'));
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final copy = p.join(dir.path, 'library.db');
  try {
    await live.customStatement("VACUUM INTO '${copy.replaceAll("'", "''")}'");
    final shas = await hashes.hashAll(await listLibraryFiles(root));
    await hashes.save();
    return await digestLibrary(copy, shas);
  } finally {
    await dir.delete(recursive: true);
  }
}
