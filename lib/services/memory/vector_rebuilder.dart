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

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/embedding_service.dart';

import 'memory_vectors.dart';

/// Stored texts memory search knows, and how many of them have no vector.
typedef VectorCounts = ({int total, int missing});

/// Clears every stored memory vector and makes them again with the current
/// embedding model: chat memories (`message_embeddings`), Data Bank entries
/// and Journal cards. Their text stays; only the vectors are replaced, so a
/// rebuild that is stopped or fails part way resumes with
/// [vectorizeMissing] where it left off.
///
/// Vectors from two models never compare, so switching model without a
/// rebuild leaves memory search matching nothing (or the wrong things).
class VectorRebuilder extends ChangeNotifier {
  VectorRebuilder({
    required EmbeddingService embeddings,
    required AppDatabase Function() db,
  }) : _embeddings = embeddings,
       _db = db;

  final EmbeddingService _embeddings;
  final AppDatabase Function() _db;

  /// Texts per request to a model server.
  static const _batch = 16;

  bool _running = false;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  String? _error;
  VectorCounts? _counts;

  bool get running => _running;
  int get done => _done;
  int get total => _total;

  /// Why the last run stopped short, or null.
  String? get error => _error;

  /// The last [refreshCounts] answer, or null before the first.
  VectorCounts? get counts => _counts;

  Map<String, dynamic> get snapshot => {
    'running': _running,
    'done': _done,
    'total': _total,
    'error': _error,
    'stored': _counts?.total,
    'missing': _counts?.missing,
  };

  Future<VectorCounts> refreshCounts() async {
    final row = await _db()
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM message_embeddings) + '
          '(SELECT COUNT(*) FROM data_bank_entries) + '
          '(SELECT COUNT(*) FROM journal_memories) AS total, '
          '(SELECT COUNT(*) FROM message_embeddings WHERE dimensions = 0) + '
          '(SELECT COUNT(*) FROM data_bank_entries '
          'WHERE embedding IS NULL OR dimensions = 0) + '
          '(SELECT COUNT(*) FROM journal_memories '
          'WHERE embedding IS NULL OR dimensions = 0) AS missing',
        )
        .getSingle();
    _counts = (
      total: row.read<int>('total'),
      missing: row.read<int>('missing'),
    );
    notifyListeners();
    return _counts!;
  }

  /// Clears every vector, then makes them all again.
  Future<bool> rebuild() => _run(clearFirst: true);

  /// Makes a vector for every stored text that has none.
  Future<bool> vectorizeMissing() => _run(clearFirst: false);

  /// Empties every stored vector, keeping the texts. From here the index
  /// belongs to the current model: nothing older is left to mix with it.
  Future<void> clearAll() async {
    final db = _db();
    await db.transaction(() async {
      await db
          .update(db.messageEmbeddings)
          .write(
            MessageEmbeddingsCompanion(
              embedding: Value(Uint8List(0)),
              dimensions: const Value(0),
            ),
          );
      await db
          .update(db.dataBankEntries)
          .write(
            const DataBankEntriesCompanion(
              embedding: Value(null),
              dimensions: Value(0),
            ),
          );
      await db
          .update(db.journalMemories)
          .write(
            const JournalMemoriesCompanion(
              embedding: Value(null),
              dimensions: Value(0),
            ),
          );
    });
    await _embeddings.choice.markIndexBuilt();
    debugPrint('[RAG:Rebuild] cleared every stored vector');
    await refreshCounts();
  }

  Future<bool> _run({required bool clearFirst}) async {
    if (_running) return false;
    _running = true;
    _cancelled = false;
    _error = null;
    _done = 0;
    _total = 0;
    notifyListeners();
    try {
      // Checked first: clearing with no model to refill would leave memory
      // search with nothing.
      await _ensureModel();
      if (clearFirst) await clearAll();
      _total = (await refreshCounts()).missing;
      final db = _db();
      await _pass<MessageEmbedding>(
        page: (after) =>
            (db.select(db.messageEmbeddings)
                  ..where(
                    (t) =>
                        t.dimensions.equals(0) & t.id.isBiggerThanValue(after),
                  )
                  ..orderBy([(t) => OrderingTerm(expression: t.id)])
                  ..limit(_batch))
                .get(),
        idOf: (r) => r.id,
        textOf: (r) => r.content,
        write: (id, bytes, dims) =>
            (db.update(
              db.messageEmbeddings,
            )..where((t) => t.id.equals(id))).write(
              MessageEmbeddingsCompanion(
                embedding: Value(bytes),
                dimensions: Value(dims),
              ),
            ),
      );
      await _pass<DataBankEntry>(
        page: (after) =>
            (db.select(db.dataBankEntries)
                  ..where(
                    (t) =>
                        (t.embedding.isNull() | t.dimensions.equals(0)) &
                        t.id.isBiggerThanValue(after),
                  )
                  ..orderBy([(t) => OrderingTerm(expression: t.id)])
                  ..limit(_batch))
                .get(),
        idOf: (r) => r.id,
        textOf: (r) => r.content,
        write: (id, bytes, dims) =>
            (db.update(
              db.dataBankEntries,
            )..where((t) => t.id.equals(id))).write(
              DataBankEntriesCompanion(
                embedding: Value(bytes),
                dimensions: Value(dims),
              ),
            ),
      );
      await _pass<JournalMemoryData>(
        page: (after) =>
            (db.select(db.journalMemories)
                  ..where(
                    (t) =>
                        (t.embedding.isNull() | t.dimensions.equals(0)) &
                        t.id.isBiggerThanValue(after),
                  )
                  ..orderBy([(t) => OrderingTerm(expression: t.id)])
                  ..limit(_batch))
                .get(),
        idOf: (r) => r.id,
        textOf: (r) => r.content,
        write: (id, bytes, dims) =>
            (db.update(
              db.journalMemories,
            )..where((t) => t.id.equals(id))).write(
              JournalMemoriesCompanion(
                embedding: Value(bytes),
                dimensions: Value(dims),
              ),
            ),
      );
      if (_cancelled) _error = 'Stopped. Resume to finish the rest.';
    } catch (e) {
      _error = '$e';
      debugPrint('[RAG:Rebuild] ✗ $e');
    } finally {
      _running = false;
      await refreshCounts();
    }
    debugPrint(
      '[RAG:Rebuild] $_done of $_total done, '
      '${_counts?.missing ?? '?'} still without a vector',
    );
    return _error == null;
  }

  /// Stops after the batch in flight.
  void cancel() {
    if (_running) _cancelled = true;
  }

  Future<void> _ensureModel() async {
    if (!_embeddings.isAvailable) await _embeddings.checkAvailability();
    if (!_embeddings.isAvailable) {
      throw StateError(
        _embeddings.lastEngineError ?? 'the memory model is not set up',
      );
    }
  }

  /// One table, a page at a time in id order. A text that cleans to
  /// nothing is skipped (and stays without a vector), never retried.
  Future<void> _pass<R>({
    required Future<List<R>> Function(String after) page,
    required String Function(R row) idOf,
    required String Function(R row) textOf,
    required Future<void> Function(String id, Uint8List bytes, int dims) write,
  }) async {
    var after = '';
    while (!_cancelled) {
      final rows = await page(after);
      if (rows.isEmpty) return;
      after = idOf(rows.last);
      final todo = [
        for (final r in rows)
          if (cleanForEmbedding(textOf(r)).isNotEmpty) r,
      ];
      final vectors = await _embeddings.embedDocuments([
        for (final r in todo) cleanForEmbedding(textOf(r)),
      ]);
      await _db().transaction(() async {
        for (var i = 0; i < todo.length; i++) {
          final floats = Float32List.fromList(vectors[i]);
          await write(
            idOf(todo[i]),
            floats.buffer.asUint8List(),
            vectors[i].length,
          );
        }
      });
      _done += rows.length;
      notifyListeners();
    }
  }
}
