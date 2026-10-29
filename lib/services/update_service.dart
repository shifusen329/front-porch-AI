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

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/update/update.dart';
import 'package:front_porch_ai/utils/native_exit.dart';

part 'update_service_download.dart';
part 'update_service_install.dart';

/// Where installed copies look for a newer version. tools/publish_update.dart
/// uploads the files and writes this feed beside them.
const kUpdateFeedUrl = 'https://www.gofigstudios.com/app/latest.json';

/// Cross-platform self-update service.
/// Reads the update feed ([kUpdateFeedUrl]) and downloads/runs the update.
/// Supports Windows (Inno Setup), Android (the system package installer),
/// Linux (AppImage), and macOS (.pkg) — each only once the feed lists a file
/// for it.
class UpdateService extends ChangeNotifier {
  static const String _prefsKeyAutoCheck = 'update_auto_check';

  String _currentVersion = appVersion;
  String _latestVersion = '';
  UpdateFile? _file;
  String _releaseNotes = '';
  bool _updateAvailable = false;
  bool _checking = false;
  String? _checkError;
  bool _downloading = false;
  bool _downloadComplete = false;
  double _downloadProgress = 0.0;
  String? _downloadError;
  bool _autoCheckEnabled = true;
  String? _pendingInstallerPath;

  String get currentVersion => _currentVersion;
  String get latestVersion => _latestVersion;
  String get releaseNotes => _releaseNotes;
  bool get updateAvailable => _updateAvailable;
  bool get checking => _checking;

  /// Why the last [checkForUpdate] could not reach a verdict (server down,
  /// offline, garbled reply), or null when it got one. A false return from
  /// [checkForUpdate] only means "up to date" when this is null — otherwise
  /// the UI must say the check failed, the way the KoboldCpp and OpenCode
  /// updaters do, instead of claiming there is nothing newer.
  String? get checkError => _checkError;
  bool get downloading => _downloading;
  bool get downloadComplete => _downloadComplete;
  double get downloadProgress => _downloadProgress;

  /// Why the last [downloadUpdate] was thrown away, or null.
  String? get downloadError => _downloadError;
  bool get autoCheckEnabled => _autoCheckEnabled;
  bool get hasPendingInstaller => _pendingInstallerPath != null;

  /// User-friendly version for UI display (avoids "vrawhide.2025..." for nightlies).
  String get displayCurrentVersion => _formatVersionForDisplay(_currentVersion);
  String get displayLatestVersion => _formatVersionForDisplay(_latestVersion);

  String _formatVersionForDisplay(String v) {
    if (v.isEmpty) return v;
    final lower = v.toLowerCase();
    if (lower.startsWith('rawhide') || lower.startsWith('nightly')) {
      return v;
    }
    return 'v$v';
  }

  /// Callback invoked before the update installer runs.
  /// Gives the host app a chance to stop child processes (e.g. KoboldCPP)
  /// because exit(0) in installNow() bypasses the window close handler.
  Future<void> Function()? _shutdownCallback;
  void setShutdownCallback(Future<void> Function() callback) {
    _shutdownCallback = callback;
  }

  /// Test seam: forces [isSupported] so [checkForUpdate] runs under test.
  @visibleForTesting
  static bool? debugIsSupportedOverride;

  /// Test seam: points [checkForUpdate] at a local server instead of
  /// [kUpdateFeedUrl], so every path is pinned against real HTTP.
  @visibleForTesting
  static String? debugFeedUrlOverride;

  /// Whether this platform supports self-update.
  /// Windows: true when installed via the Inno Setup installer (.installed marker).
  /// Android: always (the system installer takes the APK).
  /// Linux: true when running as an AppImage ($APPIMAGE env var is set).
  /// macOS: true when running as an .app bundle.
  static bool get isSupported {
    final override = debugIsSupportedOverride;
    if (override != null) return override;
    if (Platform.isAndroid) return true;
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return File('$exeDir\\.installed').existsSync();
    }
    if (Platform.isLinux) {
      return Platform.environment.containsKey('APPIMAGE');
    }
    if (Platform.isMacOS) {
      // Supported when running as an .app bundle (not flutter run debug).
      // Check that the executable is inside a .app/Contents/MacOS/ structure.
      final exe = Platform.resolvedExecutable;
      return exe.contains('.app/Contents/MacOS/');
    }
    return false;
  }

  Future<void> initialize() async {
    // Always set version so the sidebar displays it on every platform.
    _currentVersion = appVersion;

    if (!isSupported) {
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _autoCheckEnabled = prefs.getBool(_prefsKeyAutoCheck) ?? true;
    notifyListeners();
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    _autoCheckEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyAutoCheck, enabled);
    notifyListeners();
  }

  /// Read the update feed for a newer version with a file for this
  /// platform. Returns true if an update is available.
  Future<bool> checkForUpdate() async {
    if (!isSupported || _checking) return false;

    _checking = true;
    _checkError = null;
    notifyListeners();

    final client = http.Client();
    final feedUrl = Uri.parse(debugFeedUrlOverride ?? kUpdateFeedUrl);
    try {
      // The timeout matches the KoboldCpp check: a server that hangs rather
      // than fails would leave the button stuck on "Checking..." forever.
      final response = await client
          .get(feedUrl)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('Update check failed: ${response.statusCode}');
        _checkError = 'update server: HTTP ${response.statusCode}';
        return false;
      }

      final UpdateFeed feed;
      try {
        // bodyBytes: nginx sends JSON without a charset, and the notes are
        // UTF-8.
        feed = UpdateFeed.parse(
          jsonDecode(utf8.decode(response.bodyBytes)),
          feedUrl,
        );
      } on FormatException catch (e) {
        debugPrint('Update check failed: $e');
        _checkError = 'unexpected reply from the update server';
        return false;
      }

      final file = feed.forThisPlatform;
      _latestVersion = feed.version;
      _releaseNotes = feed.notes;
      _file = file;
      if (file == null) {
        debugPrint('The update feed has no ${UpdateFeed.platformKey} file');
      }
      _updateAvailable =
          file != null && isNewerVersion(feed.version, _currentVersion);
      return _updateAvailable;
    } catch (e) {
      debugPrint('Update check error: $e');
      _checkError = 'could not reach the update server';
      return false;
    } finally {
      client.close();
      _checking = false;
      notifyListeners();
    }
  }

  void notify() => notifyListeners();

  /// Download the installer to a temp directory.
  /// Does NOT run it — call installNow() or let installOnClose() handle it.
  Future<void> downloadUpdate() => _downloadUpdateImpl();

  /// Reject a download that cannot be a real installer: a truncated stream
  /// (received != Content-Length) or a body so small it is an error page,
  /// not a binary — every installer this app ships is tens of MB, so 1 MB
  /// is a generous floor. Returns the rejection reason, or null when valid.
  @visibleForTesting
  static String? validateInstallerDownload({
    required int receivedBytes,
    required int expectedBytes,
  }) {
    if (expectedBytes > 0 && receivedBytes != expectedBytes) {
      return 'installer download truncated '
          '($receivedBytes of $expectedBytes bytes)';
    }
    if (receivedBytes < 1024 * 1024) {
      return 'installer download implausibly small ($receivedBytes bytes)';
    }
    return null;
  }

  /// Run the update immediately and exit (or relaunch on Linux/macOS; on
  /// Android, hand it to the system installer).
  Future<void> installNow() => _installNowImpl();

  /// Run the pending update on app close.
  /// Call this from the window close handler.
  Future<void> installOnClose() => _installOnCloseImpl();
}
