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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/models/models.dart';

import 'character_repository.dart';
import 'storage_service.dart';

/// What one gallery removal took, kept for its Undo.
class GalleryRemoval {
  GalleryRemoval({
    required this.batchId,
    required this.characterId,
    required this.removed,
    required this.favoriteBefore,
    required this.favoriteAfter,
    required this.primeBefore,
    required this.primeAfter,
  });

  final String batchId;
  final String characterId;
  final List<AvatarImage> removed;

  /// The ★ (canonical avatar) before and after; null is the portrait.
  final String? favoriteBefore;
  final String? favoriteAfter;

  /// The default expression (`displayOrder + 1`) before and after.
  final int primeBefore;
  final int primeAfter;

  /// Images a Replace added after this removal; an Undo takes them out.
  final List<String> added = [];

  int get count => removed.length;
}

/// Where removed pictures wait for an Undo: outside `Characters/`, so Sync
/// and card exports never pick them up.
Directory galleryUndoRoot(StorageService storage) =>
    Directory(p.join(storage.rootPath ?? '', 'KoboldManager', 'gallery_undo'));

Directory _holdOf(StorageService storage, String batchId) =>
    Directory(p.join(galleryUndoRoot(storage).path, batchId));

/// The default expression once [remaining] is all that is left: [prime] when
/// an expression still sits there, else the first expression, else 1. The
/// same rule the gallery always used, so a prime that was already dangling
/// is mended too.
int healPrime(List<AvatarImage> remaining, int prime) {
  final expressions = remaining.where((a) => !a.isLook).toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  if (expressions.any((e) => e.displayOrder + 1 == prime)) return prime;
  return expressions.isEmpty ? 1 : expressions.first.displayOrder + 1;
}

/// Removes [ids] from [card]'s gallery in one go, for the desktop gallery and
/// the phone web app alike. The ★ and the default expression are fixed once
/// for the whole batch, and [card]'s in-memory gallery is refreshed so chats
/// stop choosing pictures that are gone. Null when nothing was removed.
Future<GalleryRemoval?> removeGalleryImages({
  required CharacterRepository repo,
  required StorageService storage,
  required CharacterCard card,
  required Iterable<String> ids,
}) async {
  final characterId = card.dbId;
  if (characterId == null) return null;
  final batchId = const Uuid().v4();
  final hold = _holdOf(storage, batchId);
  final favoriteBefore = card.frontPorchExtensions?.favoriteAvatarId;
  final primeBefore = card.primeAvatarIndex;
  final removed = await repo.batchMedia.removeAvatars(characterId, ids, hold);
  if (removed.isEmpty) {
    if (await hold.exists()) await hold.delete(recursive: true);
    return null;
  }
  final remaining = await repo.getAvatarImages(characterId);
  card.avatarImages = remaining;

  var favorite = favoriteBefore;
  if (favorite != null && removed.any((a) => a.id == favorite)) {
    favorite = null;
    (card.frontPorchExtensions ??= FrontPorchExtensions()).favoriteAvatarId =
        null;
    await repo.updateCharacter(card, notify: false);
  }
  final prime = healPrime(remaining, primeBefore);
  if (prime != primeBefore) {
    card.primeAvatarIndex = prime;
    await repo.setPrimeAvatar(characterId, prime);
  }
  return GalleryRemoval(
    batchId: batchId,
    characterId: characterId,
    removed: removed,
    favoriteBefore: favoriteBefore,
    favoriteAfter: favorite,
    primeBefore: primeBefore,
    primeAfter: prime,
  );
}

/// Removals that can still be undone, each for [keep]. After that its held
/// pictures are deleted for good.
class GalleryUndo {
  GalleryUndo({
    required this.repo,
    required this.storage,
    this.keep = const Duration(seconds: 10),
  });

  final CharacterRepository repo;
  final StorageService storage;
  final Duration keep;
  final Map<String, ({GalleryRemoval removal, Timer timer})> _held = {};

  /// Called when a removal expires on its own (so a banner can go).
  VoidCallback? onExpired;

  GalleryRemoval? removal(String batchId) => _held[batchId]?.removal;

  /// Starts [removal]'s Undo window.
  void hold(GalleryRemoval removal) {
    _held[removal.batchId] = (
      removal: removal,
      timer: Timer(keep, () async {
        await expire(removal.batchId);
        onExpired?.call();
      }),
    );
  }

  /// Puts back what [batchId] removed (and takes out what a Replace added),
  /// with the ★ and default expression it moved, unless they were changed
  /// again since. False when the window has closed.
  Future<bool> restore(String batchId, CharacterCard card) async {
    final entry = _held.remove(batchId);
    if (entry == null || card.dbId != entry.removal.characterId) return false;
    entry.timer.cancel();
    final r = entry.removal;
    final characterId = r.characterId;
    final hold = _holdOf(storage, batchId);
    await repo.batchMedia.restoreAvatars(characterId, r.removed, hold);
    await _delete(hold);
    if (r.added.isNotEmpty) {
      // What the Replace brought in goes the same way any removal does, so
      // a picture a tile is still reading can't stop the Undo half-way.
      final discard = _holdOf(storage, '$batchId-added');
      await repo.batchMedia.removeAvatars(characterId, r.added, discard);
      await _delete(discard);
    }
    card.avatarImages = await repo.getAvatarImages(characterId);
    final ext = card.frontPorchExtensions;
    if (r.favoriteBefore != r.favoriteAfter &&
        ext?.favoriteAvatarId == r.favoriteAfter) {
      (card.frontPorchExtensions ??= FrontPorchExtensions()).favoriteAvatarId =
          r.favoriteBefore;
      await repo.updateCharacter(card, notify: false);
    }
    if (r.primeBefore != r.primeAfter &&
        card.primeAvatarIndex == r.primeAfter) {
      card.primeAvatarIndex = r.primeBefore;
      await repo.setPrimeAvatar(characterId, r.primeBefore);
    }
    return true;
  }

  /// Ends [batchId]'s window and deletes its held pictures.
  Future<void> expire(String batchId) async {
    final entry = _held.remove(batchId);
    entry?.timer.cancel();
    await _delete(_holdOf(storage, batchId));
  }

  Future<void> expireAll() async {
    for (final id in _held.keys.toList()) {
      await expire(id);
    }
  }

  static Future<void> _delete(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('[Gallery] Could not clear held pictures ${dir.path}: $e');
    }
  }
}

/// At start: an Undo never outlives the app, so whatever is still held from
/// the last run is deleted.
Future<void> pruneGalleryUndo(StorageService storage) async {
  if (storage.rootPath == null) return;
  await GalleryUndo._delete(galleryUndoRoot(storage));
}
