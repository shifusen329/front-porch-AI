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

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_store/character_row_codec.dart'
    show toBasename;

import 'library_digest.dart';
import 'library_file_set.dart';
import 'library_sender.dart';
import 'path_rebase.dart';
import 'stored_paths.dart';
import 'sync_manifest.dart';
import 'sync_place.dart';

/// A library fetched from the sync place and made ready to swap in, still
/// beside this device's own.
class IncomingLibrary {
  const IncomingLibrary({
    required this.manifest,
    required this.dbFile,
    required this.files,
    required this.digest,
    required this.dir,
  });

  final SnapshotManifest manifest;

  /// The prepared database: migrated, checked, paths rebased, this device's
  /// web logins in place.
  final File dbFile;

  /// Library files that differ from this device's, by root-relative path,
  /// already downloaded and verified.
  final Map<String, File> files;

  /// The incoming library's digest, recorded as the last sync's once it is
  /// swapped in (never re-read afterwards: the reload writes).
  final LibraryDigest digest;

  /// The staging folder, deleted after the swap.
  final Directory dir;
}

/// The working folder a Get downloads into.
Directory incomingDir(String root) =>
    Directory(p.join(root, 'KoboldManager', 'sync', 'in'));

/// A Get that cannot go ahead, worded for the person reading it.
class GetRefused implements Exception {
  const GetRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Fetches snapshot [snapshotId] (the newest when null) and prepares it.
/// Nothing in this device's library changes; [GetRefused] or
/// [SyncPlaceException] leave it as it was.
Future<IncomingLibrary?> stageSnapshot({
  required SyncPlace place,
  required String root,
  required AppDatabase live,
  required FileHashCache hashes,
  required int schemaVersion,
  String? snapshotId,
  void Function(int bytes, int total)? onBytes,
}) async {
  final read = await readPlaceHead(place);
  if (read == null) return null;
  final id = snapshotId ?? read.head.head;
  final manifest = await readManifest(place, id);
  if (manifest == null) {
    throw GetRefused('The snapshot $id is no longer on the sync place.');
  }
  if (manifest.libraryId != read.head.libraryId) {
    throw const GetRefused('That snapshot belongs to a different library.');
  }
  if (manifest.schemaVersion > schemaVersion) {
    throw GetRefused(
      'This library was sent by Front Porch AI ${manifest.appVersion}, '
      'which is newer than this device\'s. Update Front Porch AI here first.',
    );
  }
  final problems = incomingPathProblems(manifest.files.map((f) => f.path));
  if (problems.isNotEmpty) throw GetRefused(problems.first);

  final base = incomingDir(root);
  final dir = Directory(p.join(base.path, id));
  // An interrupted Get of the same snapshot keeps its verified blobs.
  if (await base.exists()) {
    await for (final other in base.list()) {
      if (other.path != dir.path) await other.delete(recursive: true);
    }
  }
  final blobs = Directory(p.join(dir.path, 'blobs'));
  await blobs.create(recursive: true);

  final local = await listLibraryFiles(root);
  final localShas = await hashes.hashAll(local);
  final changed = [
    for (final f in manifest.files)
      if (localShas[f.path] != f.sha) f,
  ];
  final total =
      manifest.database.size + changed.fold<int>(0, (s, f) => s + f.size);
  var got = 0;
  void progress(int n) {
    got += n;
    onBytes?.call(got, total);
  }

  try {
    final gz = File(p.join(dir.path, 'library.db.gz'));
    await _fetch(place, manifest.database, gz, blobs, progress);
    final db = File(p.join(dir.path, 'library.db'));
    await gz.openRead().transform(gzip.decoder).pipe(db.openWrite());

    final files = <String, File>{};
    for (final f in changed) {
      final dest = libraryFileAt(p.join(dir.path, 'files'), f.path);
      await _fetch(place, f, dest, blobs, progress);
      files[f.path] = dest;
    }

    await prepareIncomingDatabase(
      db,
      live: live,
      schemaVersion: schemaVersion,
      rebase: PathRebase(sourceRoot: manifest.sourceRoot, targetRoot: root),
    );
    final digest = await digestLibrary(db.path, {
      for (final f in manifest.files) f.path: f.sha,
    });
    return IncomingLibrary(
      manifest: manifest,
      dbFile: db,
      files: files,
      digest: digest,
      dir: dir,
    );
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == 28 || e.osError?.errorCode == 112) {
      await dir.delete(recursive: true);
      throw const GetRefused(
        'This device ran out of space while getting the library.',
      );
    }
    rethrow;
  }
}

/// Downloads [entry]'s blobs (reusing ones already staged and verified) and
/// joins them into [dest], checking the whole file's sha.
Future<void> _fetch(
  SyncPlace place,
  SnapshotFile entry,
  File dest,
  Directory blobs,
  void Function(int) progress,
) async {
  final pieces = <File>[];
  for (final blob in entry.blobs) {
    final staged = File(p.join(blobs.path, blob.sha));
    if (!await staged.exists() || await _sha(staged) != blob.sha) {
      try {
        await place.download(blobPath(blob.sha), staged);
      } on SyncPlaceException catch (e) {
        if (!e.missing) rethrow;
        throw GetRefused(
          'Part of ${entry.path} is missing on the sync place. Send the '
          'library again from the device that has it.',
        );
      }
      if (await _sha(staged) != blob.sha) {
        await staged.delete();
        throw GetRefused('Part of ${entry.path} arrived damaged. Try again.');
      }
    }
    progress(blob.size);
    pieces.add(staged);
  }
  await dest.parent.create(recursive: true);
  if (pieces.length == 1 && entry.blobs.single.sha == entry.sha) {
    await pieces.single.copy(dest.path);
  } else {
    final sink = dest.openWrite();
    for (final piece in pieces) {
      await sink.addStream(piece.openRead());
    }
    await sink.close();
  }
  if (await _sha(dest) != entry.sha) {
    await dest.delete();
    throw GetRefused('${entry.path} arrived damaged. Try again.');
  }
}

Future<String> _sha(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

/// Readies a fetched database file to replace this device's:
/// - its header version must be one this app knows (read before Drift opens
///   it, because Drift rewrites the version on open);
/// - opening it runs this app's migrations, then `integrity_check`;
/// - its web logins are replaced with [live]'s, so this device's web app
///   sessions and password survive (a sender never sends its own, but a
///   server could);
/// - stored paths move onto this device's root;
/// - character portraits keep only their file name, as the library loader
///   would on first launch (so that launch doesn't count as a change).
Future<void> prepareIncomingDatabase(
  File file, {
  required AppDatabase live,
  required int schemaVersion,
  required PathRebase rebase,
}) async {
  final version = await readSqliteUserVersion(file);
  if (version == null || version == 0) {
    throw const GetRefused('The library that arrived is not a database.');
  }
  if (version > schemaVersion) {
    throw const GetRefused(
      'This library is from a newer Front Porch AI. Update the app here first.',
    );
  }
  final db = AppDatabase.forReunification(file);
  try {
    final check = await db.customSelect('PRAGMA integrity_check').get();
    final verdict = check.isEmpty ? '' : '${check.first.data.values.first}';
    if (verdict != 'ok') {
      throw GetRefused('The library that arrived is damaged ($verdict).');
    }
    await db.transaction(() async {
      for (final table in const ['web_auth_sessions', 'web_auth_credentials']) {
        await db.customStatement('DELETE FROM "$table"');
        final rows = await live.customSelect('SELECT * FROM "$table"').get();
        for (final row in rows) {
          final cols = row.data.keys.toList();
          await db.customInsert(
            'INSERT INTO "$table" (${cols.map((c) => '"$c"').join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            variables: [for (final c in cols) Variable(row.data[c])],
          );
        }
      }
      await rebaseStoredPaths(db, rebase);
      final cards = await db
          .customSelect(
            'SELECT id, image_path FROM characters WHERE image_path IS NOT NULL',
          )
          .get();
      for (final row in cards) {
        final stored = row.read<String>('image_path');
        final name = toBasename(stored);
        if (name != stored) {
          await db.customUpdate(
            'UPDATE characters SET image_path = ? WHERE id = ?',
            variables: [Variable(name), Variable(row.read<String>('id'))],
          );
        }
      }
    });
  } finally {
    await db.close();
  }
}
