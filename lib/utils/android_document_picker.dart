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

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/utils/picker_prefs.dart';

/// Opening files on Android through Android's app chooser ("get content"),
/// so file managers such as Cx File Explorer, and the network shares they
/// reach, can hand over a file. The file_picker plugin's storage picker lists
/// storage providers only. The native half is in `MainActivity.kt`; it copies
/// each pick into the app's cache, the same as the plugin does.
class AndroidDocumentPicker {
  AndroidDocumentPicker._();

  static const _channel = MethodChannel('app.sidepatio.android/file_picker');

  /// Null when the user backs out. Throws [WrongPickedFileType] when a file
  /// app hands over a file without one of the [extensions] asked for.
  static Future<FilePickerResult?> pick(
    FileType type,
    List<String>? extensions,
    bool multiple, [
    String? title,
  ]) async {
    final picked =
        await _channel.invokeListMethod<Map<Object?, Object?>>('pickFiles', {
          'title': title,
          'mimeTypes': pickIntentTypes(type, extensions),
          'multiple': multiple,
        }) ??
        const [];
    if (picked.isEmpty) return null;
    final files = [
      for (final f in picked)
        LocalPlatformFile(
          path: f['path']! as String,
          name: f['name']! as String,
          size: (f['size'] as num?)?.toInt(),
        ),
    ];
    for (final f in files) {
      if (!pickedFileAllowed(f.name, type, extensions)) {
        throw WrongPickedFileType(f.name, extensions!);
      }
    }
    return FilePickerResult(multiple ? files : [files.first]);
  }
}

/// MIME types narrow what the Files app shows; file managers listen for any
/// type. Only extensions every provider types the same way are mapped: an
/// empty list asks for `*/*`, so a `.porch` or a `.json` labelled
/// `application/octet-stream` is never hidden. [pickedFileAllowed] checks
/// the extension afterwards.
List<String> pickIntentTypes(FileType type, List<String>? extensions) {
  switch (type) {
    case FileType.image:
      return const ['image/*'];
    case FileType.video:
      return const ['video/*'];
    case FileType.audio:
      return const ['audio/*'];
    case FileType.media:
      return const ['image/*', 'video/*', 'audio/*'];
    case FileType.custom:
      final mimes = <String>{};
      for (final e in extensions ?? const <String>[]) {
        final known = _mimeByExtension[_bare(e)];
        if (known == null) return const [];
        mimes.addAll(known);
      }
      return mimes.toList();
    case FileType.any:
      return const [];
  }
}

const _mimeByExtension = <String, List<String>>{
  'zip': [
    'application/zip',
    'application/x-zip-compressed',
    'application/octet-stream',
  ],
  'png': ['image/png'],
  'jpg': ['image/jpeg'],
  'jpeg': ['image/jpeg'],
  'webp': ['image/webp'],
  'gif': ['image/gif'],
};

/// Whether [name] has one of [extensions], ignoring case. Only a custom pick
/// names extensions; any other pick takes what the chooser hands over.
bool pickedFileAllowed(String name, FileType type, List<String>? extensions) {
  if (type != FileType.custom || extensions == null || extensions.isEmpty) {
    return true;
  }
  final ext = _bare(p.extension(name));
  return extensions.any((e) => _bare(e) == ext);
}

String _bare(String extension) =>
    extension.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');

/// A file app handed over a file this import can't read.
class WrongPickedFileType implements Exception {
  const WrongPickedFileType(this.fileName, this.extensions);

  final String fileName;
  final List<String> extensions;

  /// What to pick instead, for the failure dialog.
  String get hint =>
      'Pick a file that ends in ${extensions.map((e) => '.${_bare(e)}').join(' or ')}.';

  @override
  String toString() => "$fileName isn't a file this import can read.";
}

/// A picked file the app's cache holds a copy of.
base class LocalPlatformFile extends PlatformFile {
  LocalPlatformFile({required String path, required this.name, int? size})
    : _path = path,
      _size = size;

  final String _path;
  final int? _size;

  @override
  final String name;

  @override
  Uri get uri => Uri.file(_path);

  @override
  XFile get xFile => XFile(_path, name: name);

  @override
  int? lengthSync() => _size;

  @override
  Future<int?> length() async => _size ?? await File(_path).length();

  @override
  Future<Uint8List> readAsBytes() => File(_path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => File(_path).openRead().map(
    (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
  );
}
