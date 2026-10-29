// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hands a downloaded APK to Android's own installer
// (android/app/src/main/kotlin/app/sidepatio/android/MainActivity.kt).
// Android asks the user to confirm, then closes and replaces the app.

import 'package:flutter/services.dart';

class ApkInstaller {
  ApkInstaller._();

  static const _channel = MethodChannel('app.sidepatio.android/apk_installer');

  /// Whether Android lets this app install packages ("Install unknown
  /// apps" in Android's settings).
  static Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  /// Opens Android's "Install unknown apps" page for this app.
  static Future<void> openInstallPermission() =>
      _channel.invokeMethod<void>('openInstallPermission');

  /// [path] must be under the cache's `updates/` folder, the one the
  /// manifest's FileProvider shares.
  static Future<void> install(String path) =>
      _channel.invokeMethod<void>('install', {'path': path});
}
