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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/utils.dart';

// Android opens files through its app chooser ("get content") so file
// managers like Cx File Explorer are offered. What the chooser is asked for
// decides which apps and files show; the extension check catches a file app
// handing over something the import can't read.

void main() {
  group('pickIntentTypes', () {
    test('images, ZIPs and other picks ask for the right types', () {
      expect(pickIntentTypes(FileType.image, null), ['image/*']);
      expect(
        pickIntentTypes(FileType.custom, ['zip']),
        containsAll(['application/zip', 'application/x-zip-compressed']),
      );
      expect(pickIntentTypes(FileType.custom, ['.PNG']), ['image/png']);
      expect(pickIntentTypes(FileType.any, null), isEmpty);
    });

    test('an extension with no fixed type asks for every file', () {
      // `*/*`: a `.porch`, or a JSON a provider calls octet-stream, must
      // never be hidden, and every file app must be listed.
      for (final exts in [
        ['porch'],
        ['gguf'],
        ['json'],
        ['zip', 'fpchat'],
      ]) {
        expect(
          pickIntentTypes(FileType.custom, exts),
          isEmpty,
          reason: '$exts',
        );
      }
    });
  });

  test('a picked file must have an extension the import asked for', () {
    expect(pickedFileAllowed('Sprites.ZIP', FileType.custom, ['zip']), isTrue);
    expect(pickedFileAllowed('sprites.png', FileType.custom, ['zip']), isFalse);
    expect(pickedFileAllowed('sprites', FileType.custom, ['zip']), isFalse);
    expect(pickedFileAllowed('face.webp', FileType.image, null), isTrue);
    expect(
      const WrongPickedFileType('a.png', ['zip', 'json']).hint,
      'Pick a file that ends in .zip or .json.',
    );
  });

  test('a cached copy reads back as the picked file', () async {
    final dir = await Directory.systemTemp.createTemp('picked_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}pack.zip');
    final bytes = Uint8List.fromList(List.generate(3000, (i) => i & 0xff));
    await file.writeAsBytes(bytes);

    final picked = LocalPlatformFile(path: file.path, name: 'pack.zip');
    expect(picked.path, file.path);
    expect(picked.extension, 'zip');
    expect(await picked.length(), 3000);
    expect(await FilePickerResult([picked]).firstBytes(), bytes);
    expect(
      (await picked.readAsByteStream().toList()).expand((c) => c).toList(),
      bytes,
    );
  });
}
