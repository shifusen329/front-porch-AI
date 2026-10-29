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

part of 'update_service.dart';

/// Download the feed's file for this platform to a temp file.
extension UpdateServiceDownload on UpdateService {
  /// Download the installer to a temp directory.
  /// Does NOT run it — call installNow() or let installOnClose() handle it.
  Future<void> _downloadUpdateImpl() async {
    final target = _file;
    if (!UpdateService.isSupported || target == null || _downloading) {
      return;
    }

    _downloading = true;
    _downloadComplete = false;
    _downloadProgress = 0.0;
    _downloadError = null;
    notify();

    try {
      // The file's own name: its extension drives the install dispatch.
      final installerPath = p.join((await _downloadDir()).path, target.name);
      final file = File(installerPath);

      final request = http.Request('GET', target.url);
      final client = http.Client();
      try {
        final response = await client.send(request);
        // A 404/500 HTML error page must never become "the installer":
        // the Linux path deletes the RUNNING AppImage before copying, so a
        // garbage file that passed this point destroyed the install.
        if (response.statusCode != 200) {
          throw Exception('installer download HTTP ${response.statusCode}');
        }

        final totalBytes = response.contentLength ?? target.size;
        int receivedBytes = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              _downloadProgress = receivedBytes / totalBytes;
              notify();
            }
          }
        } finally {
          await sink.close();
        }

        final invalid = UpdateService.validateInstallerDownload(
          receivedBytes: receivedBytes,
          expectedBytes: totalBytes,
        );
        if (invalid != null) throw Exception(invalid);
        // The feed says what the file is; anything else (a captive portal's
        // page, a half-replaced upload, a corrupted copy) is thrown away.
        if (receivedBytes != target.size) {
          throw Exception(
            'installer download is $receivedBytes bytes, '
            'the update server says ${target.size}',
          );
        }
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != target.sha256) {
          throw Exception('installer download does not match its checksum');
        }

        _pendingInstallerPath = installerPath;
        _downloadComplete = true;
        _downloading = false;
        notify();
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Download error: $e');
      _downloadError = '$e'.replaceFirst('Exception: ', '');
      _downloading = false;
      _downloadProgress = 0.0;
      notify();
    }
  }

  /// Android hands the APK over through the FileProvider, which shares only
  /// the cache's `updates/` folder (android/app/src/main/res/xml).
  Future<Directory> _downloadDir() async {
    if (!Platform.isAndroid) return Directory.systemTemp;
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'updates'),
    );
    await dir.create(recursive: true);
    return dir;
  }
}
