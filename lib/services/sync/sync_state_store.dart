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

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/app_version.dart';

/// What this device last did with the sync place.
class LastSync {
  const LastSync({
    required this.snapshotId,
    required this.libraryId,
    required this.at,
    required this.sent,
    required this.device,
  });

  factory LastSync.fromJson(Map json) => LastSync(
    snapshotId: json['snapshot'] as String,
    libraryId: json['library'] as String,
    at: DateTime.parse(json['at'] as String),
    sent: json['sent'] == true,
    device: json['device'] as String? ?? '',
  );

  final String snapshotId;
  final String libraryId;
  final DateTime at;

  /// True for a Send from this device, false for a Get.
  final bool sent;

  /// The device whose library that snapshot is.
  final String device;

  Map<String, Object> toJson() => {
    'snapshot': snapshotId,
    'library': libraryId,
    'at': at.toUtc().toIso8601String(),
    'sent': sent,
    'device': device,
  };
}

/// A Get this device can still undo: its own library waits in [folder].
class UndoRecord {
  const UndoRecord({
    required this.folder,
    required this.at,
    required this.device,
  });

  factory UndoRecord.fromJson(Map json) => UndoRecord(
    folder: json['folder'] as String,
    at: DateTime.parse(json['at'] as String),
    device: json['device'] as String? ?? '',
  );

  /// Root-relative `/` path of the set-aside library.
  final String folder;
  final DateTime at;

  /// Whose library replaced it.
  final String device;

  static const keepFor = Duration(days: 7);

  bool expiredAt(DateTime now) => now.difference(at) > keepFor;

  Map<String, Object> toJson() => {
    'folder': folder,
    'at': at.toUtc().toIso8601String(),
    'device': device,
  };
}

/// This device's identity and its record of the last sync, in prefs rather
/// than the data folder: copying a data folder to a new computer must not
/// make the new computer send as the old one.
///
/// The id also carries the machine it was made on (the host name, or
/// Android's per-device id). Prefs restored onto another phone by Android's
/// backup, or copied with the app's settings, meet a different machine and
/// get a new id.
class SyncStateStore {
  SyncStateStore(this._prefs, {Future<String> Function()? machine})
    : _machine = machine ?? currentMachine;

  final SharedPreferences _prefs;
  final Future<String> Function() _machine;

  static String _k(String key) => isPreRelease ? 'beta_$key' : key;

  static const _deviceChannel = MethodChannel('app.sidepatio.android/device');

  /// The host name on desktop; Android's per-device, per-app id on Android.
  static Future<String> currentMachine() async {
    if (Platform.isAndroid) {
      try {
        return await _deviceChannel.invokeMethod<String>('deviceId') ??
            'android';
      } on PlatformException catch (e) {
        return 'android:${e.code}';
      } on MissingPluginException {
        return 'android';
      }
    }
    return Platform.localHostname;
  }

  Future<String> deviceId() async {
    final machine = await _machine();
    final raw = _prefs.getString(_k('sync_device'));
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map;
        if (json['machine'] == machine) return json['id'] as String;
      } on FormatException {
        // Re-mint below.
      }
    }
    final id = const Uuid().v4();
    await _prefs.setString(
      _k('sync_device'),
      jsonEncode({'id': id, 'machine': machine}),
    );
    // A new identity has synced nothing yet.
    await _prefs.remove(_k('sync_last'));
    await _prefs.remove(_k('sync_pending_send'));
    return id;
  }

  LastSync? get lastSync => _read('sync_last', LastSync.fromJson);

  Future<void> setLastSync(LastSync value) =>
      _prefs.setString(_k('sync_last'), jsonEncode(value.toJson()));

  /// A snapshot this device was sending when it last stopped. If the head
  /// names it, the send finished and only the record was lost.
  String? get pendingSend => _prefs.getString(_k('sync_pending_send'));

  Future<void> setPendingSend(String? id) => id == null
      ? _prefs.remove(_k('sync_pending_send'))
      : _prefs.setString(_k('sync_pending_send'), id);

  UndoRecord? get undo => _read('sync_undo', UndoRecord.fromJson);

  Future<void> setUndo(UndoRecord? value) => value == null
      ? _prefs.remove(_k('sync_undo'))
      : _prefs.setString(_k('sync_undo'), jsonEncode(value.toJson()));

  T? _read<T>(String key, T Function(Map) parse) {
    final raw = _prefs.getString(_k(key));
    if (raw == null) return null;
    try {
      return parse(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
