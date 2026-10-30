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
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'sync_place.dart';

/// A folder on this computer: a NAS share, or a folder Nextcloud, Dropbox,
/// OneDrive or Syncthing keeps in sync.
///
/// A folder has no conditional write, so [writeHead] re-reads `latest.json`
/// just before swapping in the new one. Sync tools that saw two devices
/// write at once leave a conflict copy beside it; [readHead] refuses to
/// guess which one is right.
class FolderPlace extends SyncPlace {
  FolderPlace(String folder, List<String> subfolders)
    : _dir = Directory(p.joinAll([folder, ...subfolders])),
      _label = folder;

  final Directory _dir;
  final String _label;

  @override
  String get label => _label;

  File _file(String path) => File(p.joinAll([_dir.path, ...path.split('/')]));

  static final _conflictCopy = RegExp(
    r'^latest.*(conflict|\(\d+\)|-\d+\.json$)',
    caseSensitive: false,
  );

  @override
  Future<HeadRead?> readHead() async {
    if (!await _dir.exists()) return null;
    final copies = <String>[];
    await for (final entity in _dir.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          name != 'latest.json' &&
          _conflictCopy.hasMatch(name)) {
        copies.add(name);
      }
    }
    if (copies.isNotEmpty) {
      throw SyncPlaceException(
        'The sync folder has a second copy of latest.json (${copies.join(', ')}), '
        'left by the program that syncs the folder when two devices sent at '
        'once. Delete the copy you don\'t want, then try again.',
      );
    }
    final file = _file('latest.json');
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return HeadRead(bytes, sha256.convert(bytes).toString());
  }

  @override
  Future<void> writeHead(List<int> bytes, {required String? ifTag}) async {
    final current = await readHead();
    if (current?.tag != ifTag) throw const HeadChangedException();
    await _writeAtomically(_file('latest.json'), bytes);
  }

  Future<void> _writeAtomically(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    final file = _file(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<bool> exists(String path) => _file(path).exists();

  @override
  Future<void> download(
    String path,
    File dest, {
    void Function(int)? onBytes,
  }) async {
    final source = _file(path);
    if (!await source.exists()) {
      throw SyncPlaceException(
        'The sync folder is still receiving files ($path isn\'t there yet). '
        'Try again in a few minutes.',
        missing: true,
      );
    }
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    final sink = part.openWrite();
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        onBytes?.call(chunk.length);
      }
    } finally {
      await sink.close();
    }
    await part.rename(dest.path);
  }

  @override
  Future<void> upload(
    String path,
    Stream<List<int>> Function() open,
    int size, {
    void Function(int)? onBytes,
  }) async {
    final file = _file(path);
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    final sink = part.openWrite();
    try {
      await for (final chunk in open()) {
        sink.add(chunk);
        onBytes?.call(chunk.length);
      }
    } finally {
      await sink.close();
    }
    await part.rename(file.path);
  }

  @override
  Future<void> delete(String path) async {
    final file = _file(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> probe() async {
    try {
      await _dir.create(recursive: true);
      final probe = _file('probe.txt');
      await probe.writeAsString('Front Porch AI connection test', flush: true);
      await probe.delete();
    } on FileSystemException catch (e) {
      throw SyncPlaceException(
        'Couldn\'t write to $_label: ${e.osError?.message ?? e.message}.',
      );
    }
  }
}
