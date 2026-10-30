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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'library_digest.dart';
import 'library_prefs.dart';
import 'path_rebase.dart';
import 'sync_state_store.dart';

/// One rename in a library swap, as root-relative `/` paths.
class SwapMove {
  const SwapMove(this.from, this.to);

  factory SwapMove.fromJson(List json) =>
      SwapMove(json[0] as String, json[1] as String);

  final String from;
  final String to;

  List<String> toJson() => [from, to];
}

/// What finishing a swap writes once every file is in place.
class SwapFinish {
  const SwapFinish({
    required this.deviceId,
    required this.prefs,
    required this.sourceRoot,
    this.lastSync,
    this.undo,
    this.digest,
  });

  factory SwapFinish.fromJson(Map json) => SwapFinish(
    deviceId: json['deviceId'] as String,
    prefs: Map<String, Object?>.from(json['prefs'] as Map? ?? const {}),
    sourceRoot: json['sourceRoot'] as String,
    lastSync: json['lastSync'] == null
        ? null
        : LastSync.fromJson(json['lastSync'] as Map),
    undo: json['undo'] == null
        ? null
        : UndoRecord.fromJson(json['undo'] as Map),
    digest: json['digest'] == null
        ? null
        : LibraryDigest.fromJson(json['digest'] as Map),
  );

  final String deviceId;

  /// The library prefs the incoming library carries.
  final Map<String, Object?> prefs;

  /// The root its stored paths were written under.
  final String sourceRoot;
  final LastSync? lastSync;

  /// The Undo this swap offers; null clears it (an Undo finishing).
  final UndoRecord? undo;

  /// Recorded as the last sync's digest; null records none (after an Undo
  /// the library counts as changed).
  final LibraryDigest? digest;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'prefs': prefs,
    'sourceRoot': sourceRoot,
    'lastSync': lastSync?.toJson(),
    'undo': undo?.toJson(),
    'digest': digest?.toJson(),
  };
}

/// `KoboldManager/sync/swap.json`: every move a swap makes, written before
/// the first one. The database and the card files must change together (a
/// card's settings live in its PNG), so a swap cut short by a crash or by
/// Android ending the app is finished at the next start, before the
/// database opens.
class SwapJournal {
  const SwapJournal({
    required this.moves,
    required this.asideCount,
    required this.finish,
  });

  factory SwapJournal.fromJson(Map json) => SwapJournal(
    moves: [
      for (final m in json['moves'] as List) SwapMove.fromJson(m as List),
    ],
    asideCount: json['asideCount'] as int,
    finish: SwapFinish.fromJson(json['finish'] as Map),
  );

  final List<SwapMove> moves;

  /// The first [asideCount] moves set this device's files aside; the rest
  /// move the incoming ones in. A path can be the source of an aside move
  /// and later the target of an incoming one, so once incoming moves start
  /// the aside moves must never run again (they would set the NEW file
  /// aside over the old one).
  final int asideCount;
  final SwapFinish finish;

  static File fileIn(String root) =>
      File(p.join(root, 'KoboldManager', 'sync', 'swap.json'));

  /// Exists once the incoming moves have begun.
  static File _incomingMarker(String root) =>
      File(p.join(root, 'KoboldManager', 'sync', 'swap.in'));

  static Future<SwapJournal?> pending(String root) async {
    final file = fileIn(root);
    if (!await file.exists()) return null;
    return SwapJournal.fromJson(jsonDecode(await file.readAsString()) as Map);
  }

  Future<void> write(String root) async {
    final file = fileIn(root);
    await file.parent.create(recursive: true);
    final marker = _incomingMarker(root);
    if (await marker.exists()) await marker.delete();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'moves': [for (final m in moves) m.toJson()],
        'asideCount': asideCount,
        'finish': finish.toJson(),
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Makes every move not yet made. Within each phase a move can run
  /// again: one whose source is gone and whose target is there happened.
  Future<void> runMoves(String root, {int? crashAfter}) async {
    final marker = _incomingMarker(root);
    final start = await marker.exists() ? asideCount : 0;
    var done = 0;
    for (var i = start; i < moves.length; i++) {
      if (i == asideCount && !await marker.exists()) {
        await marker.writeAsString('in', flush: true);
      }
      await _move(root, moves[i]);
      done++;
      if (crashAfter != null && start + done == crashAfter) {
        throw const SwapInterrupted();
      }
    }
  }

  /// Applies [finish] and removes the journal. The last step: until it
  /// runs, the next start runs it again.
  Future<void> complete(String root, SharedPreferences prefs) async {
    await applyLibraryPrefs(
      prefs,
      finish.prefs,
      PathRebase(sourceRoot: finish.sourceRoot, targetRoot: root),
    );
    final state = SyncStateStore(prefs);
    if (finish.lastSync != null) await state.setLastSync(finish.lastSync!);
    await state.setUndo(finish.undo);
    final digest = digestFile(root, finish.deviceId);
    if (finish.digest != null) {
      await saveDigest(root, finish.deviceId, finish.digest!);
    } else if (await digest.exists()) {
      await digest.delete();
    }
    final marker = _incomingMarker(root);
    if (await marker.exists()) await marker.delete();
    await fileIn(root).delete();
  }
}

/// Thrown by the test hook that stops a swap part-way.
@visibleForTesting
class SwapInterrupted implements Exception {
  const SwapInterrupted();
}

File _at(String root, String rel) => File(p.joinAll([root, ...rel.split('/')]));

Future<void> _move(String root, SwapMove move) async {
  final from = _at(root, move.from);
  final to = _at(root, move.to);
  final hasFrom = await from.exists();
  if (!hasFrom) {
    if (await to.exists()) return;
    throw FileSystemException(
      'Neither side of a library swap move exists',
      from.path,
    );
  }
  await to.parent.create(recursive: true);
  if (await to.exists()) await to.delete();
  for (var attempt = 0; ; attempt++) {
    try {
      await from.rename(to.path);
      return;
    } on FileSystemException catch (e) {
      // Windows: an antivirus scan or the thumbnail cache can hold a file
      // that was just written for a moment.
      if (Platform.isWindows && attempt < 5 && e.osError?.errorCode == 32) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        continue;
      }
      // Different drives: a rename can't cross them, a copy can.
      await from.copy(to.path);
      await from.delete();
      return;
    }
  }
}

/// Finishes a swap a previous run left half done. Called at startup before
/// the database opens. Returns true when one was finished.
Future<bool> replayPendingSwap(String root, SharedPreferences prefs) async {
  final SwapJournal? journal;
  try {
    journal = await SwapJournal.pending(root);
  } on FormatException catch (e) {
    // The journal is written to a temp file and renamed, so a torn one
    // means the swap never started.
    debugPrint('[Sync] Unreadable swap journal ignored: $e');
    await SwapJournal.fileIn(root).delete();
    return false;
  }
  if (journal == null) return false;
  debugPrint('[Sync] Finishing a library swap that was interrupted');
  await journal.runMoves(root);
  await journal.complete(root, prefs);
  return true;
}
