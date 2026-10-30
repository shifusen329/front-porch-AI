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
import 'dart:typed_data';

import 'package:front_porch_ai/app_version.dart';

/// The folder on the sync place that holds this release channel's library.
/// Nightly and Rawhide builds keep their own, as they keep their own data.
String get kSyncChannelFolder =>
    isPreRelease ? 'FrontPorchAI-Beta' : 'FrontPorchAI';

/// The default name of the folder the app creates on a sync place.
const kDefaultSyncFolderName = 'Front Porch AI Sync';

/// `latest.json` as read, with the tag a conditional write must quote.
class HeadRead {
  const HeadRead(this.bytes, this.tag);
  final Uint8List bytes;
  final String tag;
}

/// Where libraries are sent and fetched: a WebDAV server or a folder.
///
/// Paths are relative to this channel's folder and use `/`. Everything on a
/// place is written once and never changed, except `latest.json`, which is
/// only written through [writeHead] so two devices can't silently overwrite
/// each other.
abstract class SyncPlace {
  /// A short description for status lines ("cloud.example.com").
  String get label;

  /// `latest.json`, or null when nothing has been sent here yet.
  Future<HeadRead?> readHead();

  /// Writes `latest.json` only if it still carries [ifTag] (null: only if it
  /// does not exist yet). Throws [HeadChangedException] when another device
  /// wrote it first.
  Future<void> writeHead(List<int> bytes, {required String? ifTag});

  /// A small file, or null when it is absent.
  Future<Uint8List?> readFile(String path);

  Future<bool> exists(String path);

  /// Streams [path] into [dest]. Throws [SyncPlaceException] with
  /// [SyncPlaceException.missing] when the file isn't there.
  Future<void> download(String path, File dest, {void Function(int)? onBytes});

  /// Stores [size] bytes from [open] at [path], creating its folders.
  Future<void> upload(
    String path,
    Stream<List<int>> Function() open,
    int size, {
    void Function(int)? onBytes,
  });

  Future<void> delete(String path);

  /// Test connection: can this place hold a library safely? Throws a
  /// [SyncPlaceException] that says what is wrong.
  Future<void> probe();

  void close() {}
}

/// A sync place failure, worded for the person reading it.
class SyncPlaceException implements Exception {
  const SyncPlaceException(this.message, {this.missing = false});

  final String message;

  /// The file asked for isn't on the place.
  final bool missing;

  @override
  String toString() => message;
}

/// `latest.json` changed since it was read: another device sent meanwhile.
class HeadChangedException implements Exception {
  const HeadChangedException();

  @override
  String toString() =>
      'Another device sent a library while this one was sending.';
}
