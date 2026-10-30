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

import 'package:path/path.dart' as p;

/// Moves a stored absolute path from one library root to another.
///
/// Chat photos, persona avatars, story portraits and custom backgrounds are
/// stored as full paths, so a library that arrives from another device (or a
/// root that moved) points at folders that don't exist here. The sender's
/// root may use the other OS's path style: a Windows library opened on
/// Android stores `C:\Users\…\FrontPorchAI\KoboldManager\images\x.png`.
class PathRebase {
  PathRebase({
    required String sourceRoot,
    required this.targetRoot,
    p.Context? target,
  }) : _sourceRoot = _androidAlias(sourceRoot),
       target = target ?? p.context;

  final String _sourceRoot;
  final String targetRoot;
  final p.Context target;

  /// Folders a library path can sit in, as root-relative segment runs.
  /// Matched from the end so a path from an unknown root still lands right
  /// (`D:\old\FrontPorchAI\KoboldManager\images\a.png` → `images\a.png`).
  static const anchors = <List<String>>[
    ['KoboldManager', 'images'],
    ['KoboldManager', 'Characters'],
    ['chats', 'images'],
    ['persona_avatars'],
    ['custom_backgrounds'],
    ['groups'],
  ];

  /// [stored] moved under [targetRoot], or [stored] unchanged when it isn't
  /// an absolute path inside a library.
  String rebase(String stored) {
    if (stored.isEmpty) return stored;
    final style = styleOf(stored);
    if (style == null) return stored;
    final from = _contextFor(style);
    final path = _androidAlias(stored);
    final segments = from.split(path);

    List<String>? rest;
    if (styleOf(_sourceRoot) == style && from.isWithin(_sourceRoot, path)) {
      rest = from.split(from.relative(path, from: _sourceRoot));
    } else {
      rest = _fromAnchor(segments);
    }
    if (rest == null || rest.isEmpty) return stored;
    return target.joinAll([targetRoot, ...rest]);
  }

  static List<String>? _fromAnchor(List<String> segments) {
    for (var i = segments.length - 2; i >= 1; i--) {
      for (final anchor in anchors) {
        if (i + anchor.length > segments.length - 1) continue;
        var match = true;
        for (var j = 0; j < anchor.length; j++) {
          if (segments[i + j].toLowerCase() != anchor[j].toLowerCase()) {
            match = false;
            break;
          }
        }
        if (match) return segments.sublist(i);
      }
    }
    return null;
  }

  /// The path style an absolute [path] was written in, or null when it is
  /// relative. Windows paths are drive-letter or UNC.
  static p.Style? styleOf(String path) {
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\')) {
      return p.Style.windows;
    }
    if (path.startsWith('/')) return p.Style.posix;
    return null;
  }

  static p.Context _contextFor(p.Style style) =>
      style == p.Style.windows ? p.windows : p.posix;

  /// Android reaches the same app folder as `/data/data/<pkg>` and
  /// `/data/user/0/<pkg>`; compare them as one place.
  static String _androidAlias(String path) => path.startsWith('/data/data/')
      ? '/data/user/0/${path.substring(11)}'
      : path;
}

/// Keys whose string values are stored file paths, wherever they appear in a
/// JSON blob (message metadata, swipe metadata, story projects).
const kPathJsonKeys = {'image_path', 'portrait', 'avatar_path', 'filePath'};

/// Rewrites every path under [kPathJsonKeys] in a decoded JSON value.
/// Returns true when anything changed.
bool rebaseJsonPaths(Object? node, PathRebase rebase) {
  var changed = false;
  if (node is Map) {
    for (final key in node.keys.toList()) {
      final value = node[key];
      if (value is String && kPathJsonKeys.contains(key)) {
        final moved = rebase.rebase(value);
        if (moved != value) {
          node[key] = moved;
          changed = true;
        }
      } else if (rebaseJsonPaths(value, rebase)) {
        changed = true;
      }
    }
  } else if (node is List) {
    for (final item in node) {
      if (rebaseJsonPaths(item, rebase)) changed = true;
    }
  }
  return changed;
}
