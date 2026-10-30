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
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backup_service.dart';

import 'library_prefs.dart';
import 'library_swap.dart';
import 'swap_journal.dart';
import 'sync_host.dart';

/// A swap stopped with files part-moved. The journal finishes it at the
/// next start, so the database stays closed until then.
class SwapStuck implements Exception {
  const SwapStuck(this.cause);
  final Object cause;

  @override
  String toString() => 'SwapStuck: $cause';
}

/// Test hook: stop a swap after this many file moves.
int? debugSwapCrashAfter;

/// Replaces the live library with [db] and [files], setting aside what they
/// replace (and every path in [remove]) in a new `r/<n>` folder.
///
/// Nothing may write while the files move: the UI leaves every editor, the
/// open chat is detached so nothing in memory is saved into the incoming
/// library, the backup timer stops, and database opens are held until the
/// new file is in place. Returns false when the rebind failed and the app
/// needs a restart; throws [SwapStuck] when the moves themselves failed.
Future<bool> runLibrarySwap({
  required String root,
  required SharedPreferences prefs,
  required SyncHost host,
  required String dbPath,
  required File db,
  required Map<String, File> files,
  required Set<String> remove,
  required SwapFinish Function(String aside) finish,
  required Future<void> Function() afterMoves,
  bool keepAside = true,
}) async {
  host.popToRoot();
  await host.flushSaves();
  final token = await host.detachChat();
  await BackupService.stopAutoBackup();
  final currentPrefs = readLibraryPrefs(prefs);
  await AppDatabase.closeAndReset();
  final release = AppDatabase.holdOpens();
  try {
    final plan = await planLibrarySwap(
      root: root,
      dbPath: dbPath,
      incomingDb: db,
      incomingFiles: files,
      removePaths: remove,
      finish: finish,
    );
    // What Undo puts back besides the files.
    await File(
      p.joinAll([root, ...plan.aside.split('/'), 'prefs.json']),
    ).writeAsString(jsonEncode(currentPrefs), flush: true);
    await plan.journal.write(root);
    await plan.journal.runMoves(root, crashAfter: debugSwapCrashAfter);
    await plan.journal.complete(root, prefs);
    await afterMoves();
    await pruneAsideFolders(root, keep: keepAside ? plan.aside : null);
  } catch (e) {
    // Opening the database now could open a half-moved one, so opens stay
    // held; the person is asked to restart.
    throw SwapStuck(e);
  }
  release();
  final rebound = await host.rebind();
  await host.afterSwap();
  BackupService.startAutoBackup();
  if (rebound) await host.reattachChat(token);
  return rebound;
}
