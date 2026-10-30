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

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The folders under the library root that travel with a snapshot, as
/// root-relative `/` paths. Everything else (models, engines, caches,
/// backups, logs, Waifu projects, Image Batches) stays on each device.
const kSyncedFolders = [
  'KoboldManager/Characters',
  'KoboldManager/images',
  'chats/images',
  'groups',
  'custom_backgrounds',
  'persona_avatars',
  'tools',
  'skills',
  'chargen/templates',
];

/// Half-written downloads and OS litter never travel.
bool _skipped(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.part') ||
      lower.endsWith('.fpai-part') ||
      lower == '.ds_store' ||
      lower == 'thumbs.db' ||
      lower == 'desktop.ini';
}

/// One library file, by its root-relative `/` path.
class LibraryFile {
  const LibraryFile({
    required this.path,
    required this.file,
    required this.size,
    required this.modified,
  });

  final String path;
  final File file;
  final int size;
  final DateTime modified;
}

/// Every file in [kSyncedFolders] under [root], sorted by path.
Future<List<LibraryFile>> listLibraryFiles(String root) async {
  final out = <LibraryFile>[];
  for (final folder in kSyncedFolders) {
    final dir = Directory(p.joinAll([root, ...folder.split('/')]));
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || _skipped(p.basename(entity.path))) continue;
      final stat = await entity.stat();
      out.add(
        LibraryFile(
          path: p.split(p.relative(entity.path, from: root)).join('/'),
          file: entity,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// The local file a root-relative `/` [path] names.
File libraryFileAt(String root, String path) =>
    File(p.joinAll([root, ...path.split('/')]));

const _reservedWindowsNames = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Why the snapshot's [paths] can't land on this device, or an empty list.
///
/// A snapshot comes from a server, so every path is checked before anything
/// downloads: relative, inside a synced folder, no `..`. Names a Linux or
/// Android library allows but Windows can't create (`CON`, a trailing space,
/// a tab from a pasted card name) are refused with the folder that needs
/// renaming. On a case-insensitive disk `Alice/` and `alice/` would merge,
/// so that is refused too.
List<String> incomingPathProblems(
  Iterable<String> paths, {
  bool? windowsNames,
  bool? caseInsensitive,
}) {
  final windows = windowsNames ?? Platform.isWindows;
  final foldCase = caseInsensitive ?? (Platform.isWindows || Platform.isMacOS);
  final problems = <String>[];
  final seen = <String, String>{};
  for (final path in paths) {
    final segments = path.split('/');
    final inFolder = kSyncedFolders.any((f) => path.startsWith('$f/'));
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        !inFolder ||
        segments.any((s) => s.isEmpty || s == '.' || s == '..')) {
      problems.add('"$path" is not a library file.');
      continue;
    }
    final bad = segments.firstWhere(
      (s) => !_legalName(s, windows: windows),
      orElse: () => '',
    );
    if (bad.isNotEmpty) {
      problems.add(
        '"$bad" can\'t be a file or folder name on this device '
        '(in $path). Rename it on the device that sent the library, then '
        'send again.',
      );
      continue;
    }
    if (foldCase) {
      final key = path.toLowerCase();
      final other = seen[key];
      if (other != null && other != path) {
        problems.add(
          '"$path" and "$other" differ only in capital letters, which this '
          'device can\'t keep apart. Rename one on the device that sent the '
          'library.',
        );
      }
      seen[key] = path;
    }
  }
  return problems;
}

bool _legalName(String name, {required bool windows}) {
  if (name.codeUnits.any((c) => c < 32)) return false;
  if (!windows) return true;
  if (RegExp(r'[<>:"|?*]').hasMatch(name)) return false;
  if (name.endsWith(' ') || name.endsWith('.')) return false;
  final stem = name.split('.').first.toLowerCase();
  return !_reservedWindowsNames.contains(stem);
}

/// sha256 of each library file, remembered by size and modified time in
/// `<root>/KoboldManager/sync/hashes.json` so a Send only hashes what changed.
class FileHashCache {
  FileHashCache(this.root);

  final String root;
  final Map<String, _CachedHash> _entries = {};
  bool _loaded = false;

  File get _file => File(p.join(root, 'KoboldManager', 'sync', 'hashes.json'));

  Future<void> load() async {
    _loaded = true;
    _entries.clear();
    try {
      if (!await _file.exists()) return;
      final raw = jsonDecode(await _file.readAsString()) as Map;
      raw.forEach((key, value) {
        if (value is Map) _entries[key as String] = _CachedHash.fromJson(value);
      });
    } catch (e) {
      // A damaged cache only costs a full re-hash.
      debugPrint('[Sync] File hash cache unreadable, re-hashing: $e');
    }
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({for (final e in _entries.entries) e.key: e.value.toJson()}),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  /// The sha256 of every file in [files], hashing in a background isolate
  /// only those whose size or time moved. A cache entry written within two
  /// seconds of the file's own time is not trusted: FAT and HFS+ keep coarse
  /// times, so a same-size edit in that window would look unchanged.
  ///
  /// Entries for files not in [files] are dropped, unless [keepOthers] (a
  /// second call for a few extra files).
  Future<Map<String, String>> hashAll(
    List<LibraryFile> files, {
    bool keepOthers = false,
  }) async {
    if (!_loaded) await load();
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = <LibraryFile>[];
    final out = <String, String>{};
    for (final f in files) {
      final hit = _entries[f.path];
      final mtime = f.modified.millisecondsSinceEpoch;
      if (hit != null &&
          hit.size == f.size &&
          hit.mtime == mtime &&
          (hit.cachedAt - mtime).abs() >= 2000) {
        out[f.path] = hit.sha;
      } else {
        stale.add(f);
      }
    }
    if (stale.isNotEmpty) {
      final paths = [for (final f in stale) f.file.path];
      final shas = await Isolate.run(() => _hashFiles(paths));
      for (var i = 0; i < stale.length; i++) {
        final f = stale[i];
        out[f.path] = shas[i];
        _entries[f.path] = _CachedHash(
          size: f.size,
          mtime: f.modified.millisecondsSinceEpoch,
          sha: shas[i],
          cachedAt: now,
        );
      }
    }
    if (!keepOthers) _entries.removeWhere((key, _) => !out.containsKey(key));
    return out;
  }
}

Future<List<String>> _hashFiles(List<String> paths) async {
  final out = <String>[];
  for (final path in paths) {
    out.add((await sha256.bind(File(path).openRead()).first).toString());
  }
  return out;
}

class _CachedHash {
  const _CachedHash({
    required this.size,
    required this.mtime,
    required this.sha,
    required this.cachedAt,
  });

  factory _CachedHash.fromJson(Map json) => _CachedHash(
    size: json['size'] as int,
    mtime: json['mtime'] as int,
    sha: json['sha'] as String,
    cachedAt: json['at'] as int,
  );

  final int size;
  final int mtime;
  final String sha;
  final int cachedAt;

  Map<String, Object> toJson() => {
    'size': size,
    'mtime': mtime,
    'sha': sha,
    'at': cachedAt,
  };
}
