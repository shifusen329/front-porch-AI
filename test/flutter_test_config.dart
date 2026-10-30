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

// flutter_test auto-discovers this file and runs [testExecutable] around every
// test in the package. We use it to make widget goldens deterministic:
//   * google_fonts must never hit the network in tests (it would fall back to
//     the Ahem box font and render differently than production);
//   * a real, committed font (Roboto) is loaded so text in widget goldens has
//     stable, cross-run glyph metrics.
// Pure logic / text-JSON golden tests are unaffected by this setup.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  _tempFoldersGoWithTheFile();
  // StorageService now reads the Tavily key from the native credential store
  // during startup. Use the package's official in-memory platform in every
  // test so unrelated suites never depend on a desktop keyring/plugin.
  FlutterSecureStorage.setMockInitialValues({});

  // Forbid any runtime font fetch; widget goldens rely solely on the bundled
  // font loaded below.
  GoogleFonts.config.allowRuntimeFetching = false;

  await _loadFont('Roboto', const [
    'test/golden/fonts/Roboto-Regular.ttf',
    'test/golden/fonts/Roboto-Bold.ttf',
  ]);
  // StoopCollapsible titles use GoogleFonts.fraunces (stoopDisplay). Tests
  // forbid runtime fetch, so register the bundled face under the family
  // names google_fonts asks for — otherwise the title paints as a tofu bar.
  await _loadFont('Fraunces', const [
    'test/golden/fonts/Fraunces-SemiBold.ttf',
  ]);
  await _loadFont('Fraunces-SemiBold', const [
    'test/golden/fonts/Fraunces-SemiBold.ttf',
  ]);

  await testMain();
}

/// Windows only: every temp folder a test file makes goes in one folder of
/// the file's own. Many suites write a fake multi-GB model by seeking to its
/// end; Linux and macOS store that as a sparse file, but NTFS allocates every
/// byte, and the folders the tests never delete filled the drive (1.1 TB on
/// 2026-10-30). Files a test still holds open can't be deleted when its
/// tests finish, so each file also sweeps what finished runs left: its
/// siblings' folders after 30 minutes (no test file runs that long, so one in
/// use is never touched) and loose `fpai*` test folders after a day.
void _tempFoldersGoWithTheFile() {
  if (!Platform.isWindows) return;
  final temp = Directory.systemTemp;
  _sweep(temp);
  // Short: the path a test builds under it must stay within MAX_PATH.
  final folder = temp.createTempSync('fpr');
  IOOverrides.global = _TempIn(folder);
  tearDownAll(() async {
    IOOverrides.global = null;
    try {
      await folder.delete(recursive: true);
    } on FileSystemException {
      // Something still holds a file; the next file's sweep takes it.
    }
  });
}

void _sweep(Directory temp) {
  final now = DateTime.now();
  final List<FileSystemEntity> entries;
  try {
    entries = temp.listSync(followLinks: false);
  } on FileSystemException {
    return;
  }
  for (final e in entries) {
    if (e is! Directory) continue;
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final keep = name.startsWith('fpr')
        ? const Duration(minutes: 30)
        : name.startsWith('fpai')
        ? const Duration(days: 1)
        : null;
    if (keep == null) continue;
    try {
      // On Windows `changed` is the creation time.
      if (now.difference(e.statSync().changed) > keep) {
        e.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // Another test file is sweeping it too, or it is still in use.
    }
  }
}

final class _TempIn extends IOOverrides {
  _TempIn(this.folder);
  final Directory folder;

  @override
  Directory getSystemTempDirectory() => folder;
}

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    }
  }
  await loader.load();
}
