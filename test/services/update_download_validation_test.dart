// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A BAD DOWNLOAD MUST NEVER BECOME "THE INSTALLER" (1.3 sweep, 2026-08-15).
//
// downloadUpdate() used to mark _downloadComplete on whatever bytes arrived —
// no HTTP status check, no length check. On Linux the install path then
// deleted the RUNNING AppImage before copying, so a 404 page or a truncated
// stream could uninstall the app outright. The download now requires
// HTTP 200 + validateInstallerDownload; the AppImage swap is copy-then-
// atomic-rename so a failed copy leaves the old app untouched (that ordering
// is Process.run plumbing, exercised only on a real Linux install — this
// suite pins the validation half).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/update/update.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('truncated download is rejected', () {
    expect(
      UpdateService.validateInstallerDownload(
        receivedBytes: 10 * 1024 * 1024,
        expectedBytes: 90 * 1024 * 1024,
      ),
      contains('truncated'),
    );
  });

  test(
    'tiny body (an HTML error page) is rejected even with matching length',
    () {
      expect(
        UpdateService.validateInstallerDownload(
          receivedBytes: 5 * 1024,
          expectedBytes: 5 * 1024,
        ),
        contains('implausibly small'),
      );
    },
  );

  test('a real installer passes', () {
    expect(
      UpdateService.validateInstallerDownload(
        receivedBytes: 90 * 1024 * 1024,
        expectedBytes: 90 * 1024 * 1024,
      ),
      isNull,
    );
    // Servers that omit Content-Length still pass on size alone.
    expect(
      UpdateService.validateInstallerDownload(
        receivedBytes: 90 * 1024 * 1024,
        expectedBytes: 0,
      ),
      isNull,
    );
  });

  // The update feed names each file's size and sha256; a download that is
  // not that file (a corrupted copy, an upload replaced mid-download) is
  // thrown away and the reason is kept for the dialog. A real listening
  // server serves the feed and a real 2 MB file.
  group('a download from the update server', () {
    const name = 'Front_Porch_AI_update_test.bin';
    final payload = List<int>.generate(
      2 * 1024 * 1024,
      (i) => (i * 31 + 7) & 0xff,
    );
    late HttpServer server;
    late String advertisedHash;

    setUp(() async {
      HttpOverrides.global = null;
      advertisedHash = sha256.convert(payload).toString();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final response = request.response;
        if (request.uri.path.endsWith('latest.json')) {
          response.write(
            jsonEncode({
              'version': '99.0.0',
              for (final key in UpdateFeed.platforms)
                key: {
                  'file': name,
                  'size': payload.length,
                  'sha256': advertisedHash,
                },
            }),
          );
        } else {
          response.add(payload);
        }
        response.close();
      });
      UpdateService.debugIsSupportedOverride = true;
      UpdateService.debugFeedUrlOverride =
          'http://${server.address.host}:${server.port}/app/latest.json';
    });

    tearDown(() async {
      UpdateService.debugIsSupportedOverride = null;
      UpdateService.debugFeedUrlOverride = null;
      await server.close(force: true);
      final left = File(p.join(Directory.systemTemp.path, name));
      if (left.existsSync()) left.deleteSync();
    });

    test('a file that does not match its checksum is thrown away', () async {
      advertisedHash = 'c' * 64;
      final service = UpdateService();
      expect(await service.checkForUpdate(), isTrue);

      await service.downloadUpdate();
      expect(service.downloadComplete, isFalse);
      expect(service.hasPendingInstaller, isFalse);
      expect(service.downloadError, contains('checksum'));
    });

    test('the file the feed describes is kept for install', () async {
      final service = UpdateService();
      expect(await service.checkForUpdate(), isTrue);

      await service.downloadUpdate();
      expect(service.downloadError, isNull);
      expect(service.downloadComplete, isTrue);
      expect(service.hasPendingInstaller, isTrue);
    });
  });
}
