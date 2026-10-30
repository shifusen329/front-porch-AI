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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'path_rebase.dart';

/// A setting that is library content, though it lives in prefs.
class LibraryPref {
  const LibraryPref(this.name, {this.prefixed = true});

  /// The key without the pre-release `beta_` prefix.
  final String name;

  /// False for the few keys every build shares unprefixed.
  final bool prefixed;

  String get key => prefixed && isPreRelease ? 'beta_$name' : name;
}

/// Library content kept in prefs. Backends, keys, models, voices and
/// appearance are this device's own and never travel.
const kLibraryPrefs = [
  LibraryPref('saved_prompts'),
  LibraryPref('macro_global_vars'),
  LibraryPref('custom_backgrounds'),
  LibraryPref('chat_background'),
  LibraryPref('wiki_url_by_character'),
  LibraryPref('wiki_urls_by_session'),
  LibraryPref('wiki_saved_urls'),
  LibraryPref('image_consent_characters', prefixed: false),
  LibraryPref('tool_verdicts'),
  // Which embedding model made the stored vectors, which travel in the DB.
  LibraryPref('embedding_index_model'),
  // Which porch memories already became journal cards in the DB.
  LibraryPref('porch_consumed_block_keys'),
];

/// The library prefs this device has, by logical name.
Map<String, Object?> readLibraryPrefs(SharedPreferences prefs) {
  final out = <String, Object?>{};
  for (final pref in kLibraryPrefs) {
    final value = prefs.get(pref.key);
    if (value is String || value is List<String>) out[pref.name] = value;
  }
  return out;
}

/// Replaces this device's library prefs with [values] from a snapshot.
/// Background files are re-pointed with [rebase]. A pref the sender didn't
/// have is removed here too, so the two libraries match.
Future<void> applyLibraryPrefs(
  SharedPreferences prefs,
  Map<String, Object?> values,
  PathRebase rebase,
) async {
  for (final pref in kLibraryPrefs) {
    var value = values[pref.name];
    if (pref.name == 'custom_backgrounds' && value is String) {
      value = _rebaseBackgrounds(value, rebase);
    }
    if (value is String) {
      await prefs.setString(pref.key, value);
    } else if (value is List) {
      await prefs.setStringList(pref.key, [for (final v in value) '$v']);
    } else {
      await prefs.remove(pref.key);
    }
  }
  // The one-time cleanup of imported card stamps runs again on the cards
  // that just arrived.
  await prefs.remove(
    isPreRelease
        ? 'beta_imported_needs_stamp_cleared'
        : 'imported_needs_stamp_cleared',
  );
}

String _rebaseBackgrounds(String raw, PathRebase rebase) {
  try {
    final decoded = jsonDecode(raw);
    if (rebaseJsonPaths(decoded, rebase)) return jsonEncode(decoded);
  } on FormatException catch (e) {
    debugPrint('[Sync] custom_backgrounds is not JSON, kept as sent: $e');
  }
  return raw;
}

/// Settings load into memory once and their setters save from memory, so
/// after [applyLibraryPrefs] each section reads prefs again. Without this
/// the next "add background" would write the old list back.
Future<void> reloadLibraryPrefs(StorageService storage) async {
  storage.presetSettings.load();
  storage.lorebookSettings.load();
  storage.uiSettings.load();
  await storage.webSearchSettings.load();
  storage.toolVerdictSettings.load();
  storage.memorySettings.load();
  storage.uiSettings.notify();
}
