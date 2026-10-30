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

import 'library_digest.dart';
import 'library_swap_runner.dart';
import 'snapshot_stager.dart';
import 'sync_manifest.dart';
import 'sync_place.dart';
import 'sync_settings.dart';

/// Why Sync is off on a developer run with a data-folder override.
const kSyncDisabledReason =
    'Sync is off while FRONT_PORCH_AI_DATA_DIR points the data folder '
    'somewhere else.';

/// A sync failure in words for the person reading it.
String syncErrorWords(Object e) => switch (e) {
  SyncPlaceException() || GetRefused() || HeadChangedException() => '$e',
  SyncPasswordStoreException() => '$e',
  SwapStuck(:final cause) => syncErrorWords(cause),
  FileSystemException(:final message, :final path) =>
    'A file couldn\'t be read or written ($message${path == null ? '' : ': $path'}).',
  _ => 'Something went wrong: $e',
};

/// "21:40" today, else "2026-10-28 21:40", in local time.
String syncWhen(DateTime t, {DateTime? now}) {
  final l = t.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(l.hour)}:${two(l.minute)}';
  if (l.year == today.year && l.month == today.month && l.day == today.day) {
    return time;
  }
  return '${l.year}-${two(l.month)}-${two(l.day)} $time';
}

/// "12 characters · 340 chats · 1.2 GB" for a snapshot.
String syncSummary(SnapshotManifest m) {
  String count(String table, String one, String many) {
    final n = m.counts[table] ?? 0;
    return '$n ${n == 1 ? one : many}';
  }

  return [
    count('characters', 'character', 'characters'),
    count('sessions', 'chat', 'chats'),
    syncSize(m.totalBytes),
  ].join(' · ');
}

String syncSize(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// "Changed here since the last sync: 3 chats (Porch night, …), the Data
/// Bank, card art and pictures."
String describeLocalChanges({
  required bool neverSynced,
  required bool unknown,
  DigestChanges? changes,
  List<String> chatNames = const [],
}) {
  if (neverSynced) {
    return 'This device has a library of its own and hasn\'t synced with '
        'this sync place before.';
  }
  if (unknown) {
    return 'This device\'s library was put back with Undo since the last '
        'sync, so it counts as changed.';
  }
  if (changes == null || changes.isEmpty) return 'Nothing changed here.';
  final parts = <String>[];
  final chats = changes.sessionIds.length;
  if (chats > 0) {
    final named = chatNames.isEmpty
        ? ''
        : ' (${chatNames.join(', ')}'
              '${chats > chatNames.length ? ', …' : ''})';
    parts.add('$chats ${chats == 1 ? 'chat' : 'chats'}$named');
  }
  parts.addAll(changes.areas);
  if (changes.files) parts.add('card art and pictures');
  return 'Changed here since the last sync: ${parts.join(', ')}.';
}
