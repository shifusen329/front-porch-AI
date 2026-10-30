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

import 'library_digest.dart';
import 'library_file_set.dart';
import 'snapshot_builder.dart';
import 'sync_host.dart';
import 'sync_state_store.dart';

/// What changed on this device since its last sync.
class LocalChanges {
  const LocalChanges({
    this.changes,
    this.titles = const [],
    this.neverSynced = false,
    this.unknown = false,
  });

  /// Null when this device never synced or can't tell.
  final DigestChanges? changes;

  /// Names of up to three changed chats.
  final List<String> titles;

  /// Never synced, and has a library of its own.
  final bool neverSynced;

  /// The library was put back with Undo, so no digest to compare with.
  final bool unknown;

  bool get any =>
      neverSynced || unknown || (changes != null && !changes!.isEmpty);
}

/// Compares this device's library now with the digest recorded at its last
/// sync. A device that never synced counts as changed when it has any
/// characters or chats.
Future<LocalChanges> checkLocalChanges({
  required SyncStateStore state,
  required String root,
  required SyncHost host,
  required FileHashCache hashes,
}) async {
  final deviceId = await state.deviceId();
  if (state.lastSync == null) {
    final rows = await host.database
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM characters WHERE deleted_at IS NULL) '
          '+ (SELECT COUNT(*) FROM sessions WHERE deleted_at IS NULL) AS n',
        )
        .getSingle();
    return LocalChanges(neverSynced: rows.read<int>('n') > 0);
  }
  final recorded = await loadDigest(root, deviceId);
  if (recorded == null) return const LocalChanges(unknown: true);
  final now = await digestLiveLibrary(
    live: host.database,
    root: root,
    hashes: hashes,
  );
  final changes = now.since(recorded);
  final titles = await host.chatTitles(changes.sessionIds.take(3).toList());
  return LocalChanges(changes: changes, titles: titles.values.toList());
}
