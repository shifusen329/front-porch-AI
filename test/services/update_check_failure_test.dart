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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/update/update.dart';
import 'package:front_porch_ai/services/update_service.dart';

// Regression coverage for the in-app updater claiming "You are up to date"
// when the update server is down. A failed check used to return false
// exactly like a successful "nothing newer" check, so the UI could not tell
// them apart. The KoboldCpp and OpenCode updaters already say "check failed"
// here; this one must expose the failure through [UpdateService.checkError].
// The check reads the feed tools/publish_update.dart writes (it used to read
// GitHub's release list, which is why these cases changed shape).
//
// Every case talks real HTTP to a real listening server the test controls.

String _feed(String version, {bool withFiles = true}) => jsonEncode({
  'version': version,
  'notes': '- Updates from the porch',
  if (withFiles)
    for (final key in UpdateFeed.platforms)
      key: {
        'file': 'Front_Porch_AI_$version.bin',
        'size': 4096,
        'sha256': 'b' * 64,
      },
});

void main() {
  late HttpServer server;
  late int status;
  late String body;

  setUp(() async {
    // flutter_test answers every request with a canned 400; this suite needs
    // the real HTTP stack against the real server below.
    HttpOverrides.global = null;
    status = 200;
    body = _feed(appVersion);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = status
        ..write(body)
        ..close();
    });
    UpdateService.debugIsSupportedOverride = true;
    UpdateService.debugFeedUrlOverride =
        'http://${server.address.host}:${server.port}/app/latest.json';
  });

  tearDown(() async {
    UpdateService.debugIsSupportedOverride = null;
    UpdateService.debugFeedUrlOverride = null;
    await server.close(force: true);
  });

  test('a server 5xx is reported as a failed check, not up to date', () async {
    status = 503;
    body = 'unicorn';
    final service = UpdateService();

    expect(await service.checkForUpdate(), isFalse);
    expect(service.checkError, contains('503'));
    expect(service.checking, isFalse);
  });

  test('an unreachable host is reported as a failed check', () async {
    await server.close(force: true);
    final service = UpdateService();

    expect(await service.checkForUpdate(), isFalse);
    expect(service.checkError, isNotNull);
  });

  test('a reply that is not a feed is a failed check', () async {
    for (final garbled in [
      '[]',
      jsonEncode({'message': 'Server Error'}),
    ]) {
      body = garbled;
      final service = UpdateService();

      expect(await service.checkForUpdate(), isFalse, reason: garbled);
      expect(service.checkError, isNotNull, reason: garbled);
    }
  });

  test('a good reply with nothing newer clears a previous failure', () async {
    status = 502;
    final service = UpdateService();
    await service.checkForUpdate();
    expect(service.checkError, isNotNull);

    status = 200;
    expect(await service.checkForUpdate(), isFalse);
    expect(service.checkError, isNull);
    expect(service.updateAvailable, isFalse);
  });

  test('a newer version with a file for this platform is offered', () async {
    body = _feed('99.0.0');
    final service = UpdateService();

    expect(await service.checkForUpdate(), isTrue);
    expect(service.updateAvailable, isTrue);
    expect(service.latestVersion, '99.0.0');
    expect(service.releaseNotes, '- Updates from the porch');
    expect(service.checkError, isNull);
  });

  test(
    'a newer version with no file for this platform is not offered',
    () async {
      body = _feed('99.0.0', withFiles: false);
      final service = UpdateService();

      expect(await service.checkForUpdate(), isFalse);
      expect(service.updateAvailable, isFalse);
      expect(service.checkError, isNull);
    },
  );
}
