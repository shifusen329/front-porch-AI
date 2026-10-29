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

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

// The decoder moved to services so the web relay can import packs too.
export 'package:front_porch_ai/services/sprite_pack.dart';

/// IO helpers for the Avatar Gallery add flows — file and ZIP picking (the
/// sprite-pack decoder is `services/sprite_pack.dart`). No repository, no
/// state: keeps the controller + shell under the size cap. The pickers take a
/// [BuildContext] only so a failed file window can explain itself
/// ([GuardedPicker]).

/// Pick a single image and return its bytes, or null if cancelled. Handles the
/// macOS desktop quirk where `.bytes` is null and only `.path` is populated.
Future<Uint8List?> pickImageBytes(BuildContext context) async {
  final result = await GuardedPicker.pickFiles(
    context,
    category: PickerPrefs.catImage,
    type: FileType.image,
    allowMultiple: false,
  );
  return _firstBytes(result);
}

/// Pick a `.zip` sprite pack and return its bytes, or null if cancelled.
Future<Uint8List?> pickZipBytes(BuildContext context) async {
  final result = await GuardedPicker.pickFiles(
    context,
    category: PickerPrefs.catImport,
    type: FileType.custom,
    allowedExtensions: ['zip'],
    allowMultiple: false,
  );
  return _firstBytes(result);
}

Future<Uint8List?> _firstBytes(FilePickerResult? result) async {
  return result?.firstBytes();
}
