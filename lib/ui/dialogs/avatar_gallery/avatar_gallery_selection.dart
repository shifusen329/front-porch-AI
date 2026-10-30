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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';

/// The gallery's Select mode: which looks and expression images are picked
/// for one Delete. The portrait is never part of it. Like the library's
/// Multi-select, but scoped to one gallery and its own section rules.
class AvatarGallerySelection extends ChangeNotifier {
  bool active = false;
  final Set<String> ids = {};

  /// The last expression image picked, for "Select every <label>".
  AvatarImage? last;

  int get count => ids.length;
  bool contains(String id) => ids.contains(id);

  void start() {
    active = true;
    notifyListeners();
  }

  void cancel() {
    active = false;
    ids.clear();
    last = null;
    notifyListeners();
  }

  void toggle(AvatarImage image) {
    if (!ids.remove(image.id)) {
      ids.add(image.id);
      last = image.isLook ? null : image;
    } else if (last?.id == image.id) {
      last = null;
    }
    notifyListeners();
  }

  void selectAll(Iterable<AvatarImage> images) {
    ids.addAll(images.map((a) => a.id));
    notifyListeners();
  }

  /// Every expression image sharing [label] (the alternates of one emotion).
  void selectLabel(String label, Iterable<AvatarImage> expressions) {
    final key = label.trim().toLowerCase();
    ids.addAll([
      for (final e in expressions)
        if ((e.label ?? '').trim().toLowerCase() == key) e.id,
    ]);
    notifyListeners();
  }

  /// Drops picks that are no longer in the gallery (after a reload).
  void keepOnly(Iterable<String> present) {
    final keep = present.toSet();
    final before = ids.length;
    ids.retainWhere(keep.contains);
    if (last != null && !keep.contains(last!.id)) last = null;
    if (ids.length != before) notifyListeners();
  }
}
