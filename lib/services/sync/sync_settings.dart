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

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';

import 'folder_place.dart';
import 'sync_place.dart';
import 'webdav_place.dart';

/// Which kind of sync place is set up.
enum SyncPlaceKind { none, webdav, folder }

/// The OS key store couldn't keep the WebDAV password. Shown as is; falling
/// back to plain storage would defeat the store.
class SyncPasswordStoreException implements Exception {
  const SyncPasswordStoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The WebDAV app password, in the OS secure store (Windows Credential
/// Manager, Android Keystore, the macOS keychain).
class SyncPasswordStore {
  SyncPasswordStore({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<void> Function(String key) delete,
  }) : _read = read,
       _write = write,
       _delete = delete;

  factory SyncPasswordStore.secure([
    FlutterSecureStorage storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  ]) => SyncPasswordStore(
    read: (key) => storage.read(key: key),
    write: (key, value) => storage.write(key: key, value: value),
    delete: (key) => storage.delete(key: key),
  );

  /// Tests hand in an in-memory store.
  @visibleForTesting
  static SyncPasswordStore? debugStore;

  static SyncPasswordStore open() => debugStore ?? SyncPasswordStore.secure();

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;

  static String get _key =>
      isPreRelease ? 'beta_sync_webdav_password' : 'sync_webdav_password';

  Future<T> _guard<T>(String action, Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      debugPrint('[Sync] password store $action failed: ${e.runtimeType}');
      throw SyncPasswordStoreException(
        action == 'read'
            ? 'This device\'s key store couldn\'t be read, so the sync '
                  'password is unavailable. Enter it again.'
            : 'This device\'s key store couldn\'t save the sync password.',
      );
    }
  }

  Future<String?> read() => _guard('read', () async {
    final value = await _read(_key);
    return (value == null || value.isEmpty) ? null : value;
  });

  Future<void> save(String password) =>
      _guard('write', () => _write(_key, password));

  Future<void> clear() => _guard('write', () => _delete(_key));
}

/// Where this device syncs to, and the two automatic switches.
class SyncSettings extends ChangeNotifier {
  SyncSettings(this._prefs);

  final SharedPreferences _prefs;

  static String _k(String key) => isPreRelease ? 'beta_$key' : key;

  SyncPlaceKind get kind => SyncPlaceKind.values.firstWhere(
    (k) => k.name == _prefs.getString(_k('sync_place_kind')),
    orElse: () => SyncPlaceKind.none,
  );
  String get serverUrl => _prefs.getString(_k('sync_webdav_url')) ?? '';
  String get username => _prefs.getString(_k('sync_webdav_user')) ?? '';
  String get folderPath => _prefs.getString(_k('sync_folder_path')) ?? '';
  String get folderName =>
      _prefs.getString(_k('sync_folder_name')) ?? kDefaultSyncFolderName;
  String get deviceName => _prefs.getString(_k('sync_device_name')) ?? '';
  bool get sendOnClose => _prefs.getBool(_k('sync_send_on_close')) ?? false;
  bool get checkOnStart => _prefs.getBool(_k('sync_check_on_start')) ?? false;

  Future<void> setPlace({
    required SyncPlaceKind kind,
    String? serverUrl,
    String? username,
    String? folderPath,
    String? folderName,
  }) async {
    await _prefs.setString(_k('sync_place_kind'), kind.name);
    if (serverUrl != null) {
      await _prefs.setString(_k('sync_webdav_url'), serverUrl.trim());
    }
    if (username != null) {
      await _prefs.setString(_k('sync_webdav_user'), username.trim());
    }
    if (folderPath != null) {
      await _prefs.setString(_k('sync_folder_path'), folderPath.trim());
    }
    if (folderName != null) {
      final name = folderName.trim();
      await _prefs.setString(
        _k('sync_folder_name'),
        name.isEmpty ? kDefaultSyncFolderName : name,
      );
    }
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    await _prefs.setString(_k('sync_device_name'), name.trim());
    notifyListeners();
  }

  Future<void> setSendOnClose(bool value) async {
    await _prefs.setBool(_k('sync_send_on_close'), value);
    notifyListeners();
  }

  Future<void> setCheckOnStart(bool value) async {
    await _prefs.setBool(_k('sync_check_on_start'), value);
    notifyListeners();
  }

  bool get isConfigured => switch (kind) {
    SyncPlaceKind.none => false,
    SyncPlaceKind.webdav => serverUrl.isNotEmpty && username.isNotEmpty,
    SyncPlaceKind.folder => folderPath.isNotEmpty,
  };

  /// The place these settings name, or null when none is set up. Throws
  /// [SyncPlaceException] when the WebDAV password is missing.
  Future<SyncPlace?> openPlace(SyncPasswordStore passwords) async {
    final folder = [folderName, kSyncChannelFolder];
    switch (kind) {
      case SyncPlaceKind.none:
        return null;
      case SyncPlaceKind.folder:
        return folderPath.isEmpty ? null : FolderPlace(folderPath, folder);
      case SyncPlaceKind.webdav:
        if (serverUrl.isEmpty || username.isEmpty) return null;
        final password = await passwords.read();
        if (password == null) {
          throw const SyncPlaceException(
            'Enter the sync password in Settings → Sync.',
          );
        }
        return WebDavPlace(
          serverUrl: serverUrl,
          username: username,
          password: password,
          folder: folder,
        );
    }
  }
}
