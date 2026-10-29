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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/update/update.dart';

// The update feed (latest.json) tools/publish_update.dart writes on the
// app's own server: what it reads, what it refuses, and how versions
// compare. This file used to pin the choice of a release out of GitHub's
// release list; the app no longer reads GitHub's releases, so that choice
// is gone and the feed's parsing is what decides what gets offered.

final _hash = 'a' * 64;
final _base = Uri.parse('https://example.test/app/latest.json');

Map<String, dynamic> _entry(String file) => {
  'file': file,
  'size': 2048,
  'sha256': _hash,
};

void main() {
  group('UpdateFeed.parse', () {
    test('reads each platform\'s file, resolved against the feed', () {
      final feed = UpdateFeed.parse({
        'version': 'v1.0.1',
        'notes': '- Updates from the porch',
        'windows': _entry('Front_Porch_AI_Setup_1.0.1.exe'),
        'android': {
          ..._entry('https://cdn.example.test/Front_Porch_AI_1.0.1.apk'),
          'versionCode': 1000100,
        },
      }, _base);

      expect(feed.version, '1.0.1');
      expect(feed.notes, '- Updates from the porch');
      final windows = feed.files['windows']!;
      expect(
        windows.url.toString(),
        'https://example.test/app/Front_Porch_AI_Setup_1.0.1.exe',
      );
      expect(windows.name, 'Front_Porch_AI_Setup_1.0.1.exe');
      expect(windows.size, 2048);
      expect(windows.sha256, _hash);
      expect(feed.files['android']!.url.host, 'cdn.example.test');
      expect(feed.files.containsKey('linux'), isFalse);
    });

    test(
      'a feed that is not whole is refused, never read as nothing newer',
      () {
        final bad = <Object?>[
          [],
          'latest',
          <String, dynamic>{},
          {'version': ''},
          {
            'version': '1.0.1',
            'windows': {'file': 'a.exe'},
          },
          {
            'version': '1.0.1',
            'windows': {'file': 'a.exe', 'size': 10, 'sha256': 'not-a-hash'},
          },
          {'version': '1.0.1', 'android': 'a.apk'},
        ];
        for (final json in bad) {
          expect(
            () => UpdateFeed.parse(json, _base),
            throwsFormatException,
            reason: '$json',
          );
        }
      },
    );

    test('a file name that would leave the download folder is refused', () {
      // The last path segment, decoded, becomes the downloaded file's name.
      for (final file in [
        '..%2F..%2Fshared_prefs%2Fprefs.xml',
        '..%5C..%5CFront_Porch_AI.exe',
        '..',
        'releases/',
      ]) {
        expect(
          () => UpdateFeed.parse({
            'version': '1.0.1',
            'android': _entry(file),
          }, _base),
          throwsFormatException,
          reason: file,
        );
      }
    });
  });

  test('isNewerVersion orders releases', () {
    expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.0.10', '1.0.9'), isTrue);
    expect(isNewerVersion('1.0.9', '1.0.10'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('v1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0-beta3'), isTrue);
    expect(isNewerVersion('1.0.0-beta3', '1.0.0'), isFalse);
    expect(isNewerVersion('0.9.8-beta10', '0.9.8-beta9'), isTrue);
    expect(
      isNewerVersion('nightly-rawhide.20260720.abc', 'rawhide.20260719.def'),
      isTrue,
    );
    expect(
      isNewerVersion('rawhide.20260718.abc', 'rawhide.20260719.def'),
      isFalse,
    );
  });
}
