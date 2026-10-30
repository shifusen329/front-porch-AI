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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

/// Tables whose contents never count as "this library changed": the
/// change counter itself, this device's web logins, and the memory vectors
/// (derived from the messages, which are counted).
bool _digestSkips(String table) =>
    table == 'sync_meta' ||
    table == 'message_embeddings' ||
    table.startsWith('web_auth_') ||
    table.startsWith('sqlite_');

/// What each digested table is called in "changed here" lines. Sessions and
/// messages are reported per chat instead.
const kDigestTableLabels = {
  'characters': 'characters',
  'avatar_images': 'gallery pictures',
  'personas': 'personas',
  'groups': 'groups',
  'group_members': 'groups',
  'worlds': 'worlds',
  'chat_worlds': 'worlds',
  'folders': 'folders',
  'data_bank_entries': 'the Data Bank',
  'objectives': 'quests',
  'journal_memories': 'journals',
  'growth_rings': 'Growth Rings',
  'growth_state': 'Growth Rings',
  'story_projects': 'Porch Stories',
};

/// The SQLite header's `user_version` (bytes 60–63), read without opening
/// the database: Drift rewrites it on open, so a newer file must be refused
/// before anything opens it. Null when [file] isn't an SQLite database.
Future<int?> readSqliteUserVersion(File file) async {
  final raf = await file.open();
  try {
    final header = await raf.read(64);
    if (header.length < 64 ||
        utf8.decode(header.sublist(0, 15), allowMalformed: true) !=
            'SQLite format 3') {
      return null;
    }
    return ByteData.sublistView(Uint8List.fromList(header)).getUint32(60);
  } finally {
    await raf.close();
  }
}

/// A content fingerprint of one library, used to tell whether this device
/// changed it since the last sync.
///
/// Opening a chat, a save that rewrites the same messages under fresh ids,
/// and the startup purge of deleted rows must not count, so `updated_at`,
/// message ids and soft-deleted rows are left out. Each chat is also
/// fingerprinted on its own so the conflict prompt can name what changed.
class LibraryDigest {
  const LibraryDigest({
    required this.tables,
    required this.sessions,
    required this.files,
  });

  factory LibraryDigest.fromJson(Map json) => LibraryDigest(
    tables: Map<String, String>.from(json['tables'] as Map),
    sessions: Map<String, String>.from(json['sessions'] as Map),
    files: json['files'] as String,
  );

  final Map<String, String> tables;
  final Map<String, String> sessions;
  final String files;

  Map<String, Object> toJson() => {
    'tables': tables,
    'sessions': sessions,
    'files': files,
  };

  /// What differs from [before].
  DigestChanges since(LibraryDigest before) {
    final sessionIds = <String>{
      for (final e in sessions.entries)
        if (before.sessions[e.key] != e.value) e.key,
      for (final id in before.sessions.keys)
        if (!sessions.containsKey(id)) id,
    };
    final labels = <String>{};
    for (final name in {...tables.keys, ...before.tables.keys}) {
      if (name == 'sessions' || name == 'messages') continue;
      if (tables[name] != before.tables[name]) {
        labels.add(kDigestTableLabels[name] ?? name.replaceAll('_', ' '));
      }
    }
    return DigestChanges(
      sessionIds: sessionIds.toList()..sort(),
      areas: labels.toList()..sort(),
      files: files != before.files,
    );
  }
}

/// The difference between two [LibraryDigest]s.
class DigestChanges {
  const DigestChanges({
    required this.sessionIds,
    required this.areas,
    required this.files,
  });

  /// Chats added, removed or changed.
  final List<String> sessionIds;

  /// Other parts of the library that changed, as [kDigestTableLabels] words.
  final List<String> areas;

  /// Card art, pictures or other library files changed.
  final bool files;

  bool get isEmpty => sessionIds.isEmpty && areas.isEmpty && !files;
}

/// Digests the database at [dbPath] (a copy, never the live file) plus the
/// library files' [fileShas], in a background isolate.
Future<LibraryDigest> digestLibrary(
  String dbPath,
  Map<String, String> fileShas,
) async {
  final version = await readSqliteUserVersion(File(dbPath));
  if (version == null) {
    throw FormatException('$dbPath is not a library database');
  }
  final files =
      (fileShas.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key}\t${e.value}\n')
          .join();
  final filesDigest = sha256.convert(utf8.encode(files)).toString();
  final json = await Isolate.run(() => _digestDatabase(dbPath, version));
  return LibraryDigest(
    tables: Map<String, String>.from(json['tables'] as Map),
    sessions: Map<String, String>.from(json['sessions'] as Map),
    files: filesDigest,
  );
}

/// Opens a database file without migrating it: Drift writes `user_version`
/// whenever it differs from the opener's, so the opener claims the file's
/// own version and does nothing before open.
class AsIsDatabase implements QueryExecutorUser {
  const AsIsDatabase(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// An order-free sum of row hashes, so no ORDER BY is needed and two equal
/// rows don't cancel out the way XOR would.
class _Accumulator {
  int _a = 0;
  int _b = 0;
  int _rows = 0;

  void add(List<int> hash) {
    final data = ByteData.sublistView(Uint8List.fromList(hash));
    _a = (_a + data.getInt64(0)).toSigned(64);
    _b = (_b + data.getInt64(8)).toSigned(64);
    _rows++;
  }

  String get value =>
      '$_rows:${_a.toUnsigned(64).toRadixString(16)}:${_b.toUnsigned(64).toRadixString(16)}';
}

Future<Map<String, Object>> _digestDatabase(String dbPath, int version) async {
  final db = NativeDatabase(File(dbPath));
  try {
    await db.ensureOpen(AsIsDatabase(version));
    final tables = [
      for (final row in await db.runSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        const [],
      ))
        row['name'] as String,
    ].where((t) => !_digestSkips(t));

    final tableDigests = <String, String>{};
    final sessions = <String, _Accumulator>{};
    for (final table in tables) {
      final info = await db.runSelect('PRAGMA table_info("$table")', const []);
      final names = [for (final c in info) c['name'] as String];
      final cols = names
          .where((c) => c != 'updated_at')
          .where((c) => !(table == 'messages' && c == 'id'))
          .toList();
      if (cols.isEmpty) continue;
      final live = names.contains('deleted_at')
          ? 'deleted_at IS NULL AND '
          : '';
      final select = cols.map((c) => '"$c"').join(', ');
      final sessionCol = switch (table) {
        'sessions' => cols.indexOf('id'),
        'messages' => cols.indexOf('session_id'),
        _ => -1,
      };
      final acc = _Accumulator();
      var lastRowId = -1 << 62;
      while (true) {
        final page = await db.runSelect(
          'SELECT rowid AS _rid, $select FROM "$table" '
          'WHERE $live rowid > ? ORDER BY rowid LIMIT 2000',
          [lastRowId],
        );
        if (page.isEmpty) break;
        for (final row in page) {
          lastRowId = row['_rid'] as int;
          final values = [for (final c in cols) _canonical(row[c])];
          final hash = sha256.convert(utf8.encode(jsonEncode(values))).bytes;
          acc.add(hash);
          if (sessionCol >= 0) {
            final id = row[cols[sessionCol]];
            if (id is String) {
              sessions.putIfAbsent(id, _Accumulator.new).add(hash);
            }
          }
        }
      }
      tableDigests[table] = acc.value;
    }
    return {
      'tables': tableDigests,
      'sessions': {for (final e in sessions.entries) e.key: e.value.value},
    };
  } finally {
    await db.close();
  }
}

Object? _canonical(Object? value) =>
    value is Uint8List ? base64Encode(value) : value;

/// Where this device keeps the digest of its last sync. Keyed by device id
/// so a data folder copied to another computer carries nothing it trusts.
File digestFile(String root, String deviceId) =>
    File(p.join(root, 'KoboldManager', 'sync', 'digest-$deviceId.json'));

Future<LibraryDigest?> loadDigest(String root, String deviceId) async {
  final file = digestFile(root, deviceId);
  if (!await file.exists()) return null;
  try {
    return LibraryDigest.fromJson(jsonDecode(await file.readAsString()) as Map);
  } on FormatException {
    return null;
  }
}

Future<void> saveDigest(String root, String deviceId, LibraryDigest d) async {
  final file = digestFile(root, deviceId);
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(jsonEncode(d.toJson()), flush: true);
  await tmp.rename(file.path);
}
