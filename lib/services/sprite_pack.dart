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

import 'package:front_porch_ai/utils/emotion_labels.dart';

/// One recognized emotion sprite from a pack.
class SpritePackEntry {
  const SpritePackEntry(this.bytes, this.emotion);
  final Uint8List bytes;
  final String emotion;
}

/// The result of decoding a sprite pack: the recognized (emotion-named) entries
/// plus a count of files whose name matched no emotion label.
class SpritePackResult {
  const SpritePackResult(this.entries, this.unrecognized);
  final List<SpritePackEntry> entries;
  final int unrecognized;
}

/// Decode a ZIP sprite pack: image files whose base name is an emotion label
/// (`joy.png`) or an alternate of one (`joy-1.png`, `joy_2.png`, `joy.3.png`)
/// become [SpritePackEntry]s; others are counted as
/// [SpritePackResult.unrecognized]. [labels] are the names recognized: the
/// standard set plus any the expression classifier model adds.
///
/// Entries come back grouped by label in [labels] order, each label's base
/// first and then its alternates by number (`-2` before `-10`), so a pack
/// imports in a stable order and a label's first image is its base.
SpritePackResult decodeSpritePack(
  Uint8List zipBytes, {
  List<String> labels = EmotionLabels.all,
}) {
  const imageExts = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
  final found = <({SpritePackEntry entry, int label, int alt, String name})>[];
  var unrecognized = 0;

  final archive = ZipDecoder().decodeBytes(zipBytes);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    // Match on the file's BASENAME so packs with folders ("sprites/joy.png")
    // still resolve — matching the full path silently failed every foldered pack.
    final name = entry.name.split('/').last.split(r'\').last;
    final ext = name.split('.').last.toLowerCase();
    if (!imageExts.contains(ext)) continue;

    final base = name.replaceAll(RegExp(r'\.\w+$'), '').toLowerCase();
    // The longest label wins, so `reverse-cowgirl-1` is never `reverse`.
    var match = -1;
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i];
      final fits =
          base == label ||
          base.startsWith('$label-') ||
          base.startsWith('$label.') ||
          base.startsWith('${label}_');
      if (fits && (match < 0 || label.length > labels[match].length)) {
        match = i;
      }
    }
    final data = entry.content as Uint8List?;
    if (match < 0 || data == null) {
      unrecognized++;
      continue;
    }
    final suffix = base.substring(labels[match].length);
    found.add((
      entry: SpritePackEntry(data, labels[match]),
      label: match,
      // The base sorts first, numbered alternates by number, then any other
      // suffix by name.
      alt: suffix.isEmpty ? -1 : int.tryParse(suffix.substring(1)) ?? 1 << 30,
      name: base,
    ));
  }
  found.sort(
    (a, b) => a.label != b.label
        ? a.label.compareTo(b.label)
        : a.alt != b.alt
        ? a.alt.compareTo(b.alt)
        : a.name.compareTo(b.name),
  );
  return SpritePackResult([for (final f in found) f.entry], unrecognized);
}
