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

import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// Image types an imported ZIP may carry.
const kZipImageExts = {'png', 'jpg', 'jpeg', 'webp', 'gif'};

/// The image files in a ZIP, each by its base name: packs with folders
/// ("sprites/joy.png") still resolve, which matching the full path did not.
Iterable<({String name, Uint8List bytes})> zipImages(Uint8List zipBytes) sync* {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.split('/').last.split(r'\').last;
    if (!kZipImageExts.contains(name.split('.').last.toLowerCase())) continue;
    final data = entry.content as Uint8List?;
    if (data != null) yield (name: name, bytes: data);
  }
}
