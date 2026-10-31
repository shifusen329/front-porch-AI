// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → Troubleshooting → Write a debug log, on a computer
// and on Android: the switch, View, Save a copy (once, however fast it is
// tapped), Clear, and the card at phone and wide widths.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/debug_log/debug_log.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/general_tab.dart';
import 'package:front_porch_ai/utils/utils.dart' show PickerPrefs, PlatformCaps;

import '../../helpers/double_tap.dart';
import '../../helpers/real_temp_dir.dart';

void main() {
  late Directory dir;
  late DebugLog log;

  setUp(() {
    dir = realTempDir('fpai_debug_card_');
    SharedPreferences.setMockInitialValues({});
    log = DebugLog(folder: () async => Directory(p.join(dir.path, 'logs')));
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      // A test that failed with its log still open; Windows keeps the file.
      debugPrint('debug_log_card_test: temp folder left behind: $e');
    }
  });

  // The card reads and writes real files, and each file step lands only
  // between frames here: pump until [done], or a few rounds when no
  // condition is given.
  Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
    for (var i = 0; i < 150 && !(done?.call() ?? i >= 10); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    if (done != null) expect(done(), isTrue);
  }

  bool shows(Finder finder) => finder.evaluate().isNotEmpty;

  // Each test ends with its log closed: Windows will not delete an open file.
  Future<void> closeLog(WidgetTester tester) async {
    var closed = false;
    log.setEnabled(false).then((_) => closed = true);
    await settle(tester, () => closed);
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    bool desktop = true,
  }) async {
    PlatformCaps.debugOverride = PlatformCaps(isDesktop: desktop);
    addTearDown(() => PlatformCaps.debugOverride = PlatformCaps.host());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: DebugLogCard(log: log),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> turnOn(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('debug-logging')));
    await settle(
      tester,
      () => shows(find.textContaining('${DebugLog.fileName} · ')),
    );
  }

  ActionChip chip(WidgetTester tester, String key) =>
      tester.widget<ActionChip>(find.byKey(ValueKey(key)));

  testWidgets('the switch turns the log on, remembers it, and the buttons '
      'wake up', (tester) async {
    await pumpCard(tester);
    expect(find.text('No log yet.'), findsOneWidget);
    expect(chip(tester, 'debug-log-save').onPressed, isNull);

    await turnOn(tester);

    expect(log.enabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DebugLog.prefKey), isTrue);
    expect(find.textContaining('${DebugLog.fileName} · '), findsOneWidget);
    for (final key in [
      'debug-log-view',
      'debug-log-save',
      'debug-log-folder',
      'debug-log-clear',
    ]) {
      expect(chip(tester, key).onPressed, isNotNull, reason: key);
    }
    await closeLog(tester);
  });

  testWidgets('Save a copy writes the whole log once, however fast it is '
      'tapped', (tester) async {
    final saves = <({Uint8List bytes, String? fileName})>[];
    PickerPrefs.testSaveFileOverride =
        ({
          required String category,
          required Uint8List bytes,
          String? dialogTitle,
          String? fileName,
          FileType? type,
          List<String>? allowedExtensions,
        }) async {
          saves.add((bytes: bytes, fileName: fileName));
          return p.join(dir.path, fileName ?? 'log.txt');
        };
    addTearDown(() => PickerPrefs.testSaveFileOverride = null);
    await pumpCard(tester);
    await turnOn(tester);
    log.record('[Chat] the reply never came');

    await doubleTapNoFrame(
      tester,
      find.byKey(const ValueKey('debug-log-save')),
    );
    await settle(tester, () => shows(find.textContaining('Saved the log as')));
    await settle(tester);

    expect(saves, hasLength(1));
    expect(
      utf8.decode(saves.single.bytes),
      contains('[Chat] the reply never came'),
    );
    expect(saves.single.fileName, matches(r'^front-porch-log-.*\.txt$'));
    await closeLog(tester);
  });

  testWidgets('View shows the newest lines and Copy is there', (tester) async {
    await pumpCard(tester);
    await turnOn(tester);
    log.record('[TTS] the voice server said no');

    await tester.tap(find.byKey(const ValueKey('debug-log-view')));
    await settle(tester, () => shows(find.byType(DebugLogText)));

    expect(find.text('Debug log'), findsOneWidget);
    expect(
      find.textContaining('[TTS] the voice server said no'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('debug-log-copy')), findsOneWidget);
    await closeLog(tester);
  });

  testWidgets('Clear empties the log and a log that is on starts again', (
    tester,
  ) async {
    await pumpCard(tester);
    await turnOn(tester);
    log.record('[Chat] before the clear');

    await tester.tap(find.byKey(const ValueKey('debug-log-clear')));
    await settle(tester, () => shows(find.text('The debug log is cleared.')));

    String? text;
    log.contents().then((t) => text = t);
    await settle(tester, () => text != null);
    expect(text, isNot(contains('[Chat] before the clear')));
    expect(text, contains('log cleared'));
    await closeLog(tester);
  });

  testWidgets('on Android there is no folder to open and no path', (
    tester,
  ) async {
    await pumpCard(tester, size: const Size(400, 800), desktop: false);
    await turnOn(tester);

    expect(find.byKey(const ValueKey('debug-log-folder')), findsNothing);
    expect(find.textContaining(dir.path), findsNothing);
    expect(chip(tester, 'debug-log-save').onPressed, isNotNull);
    await closeLog(tester);
  });

  for (final size in const [Size(400, 800), Size(1440, 900), Size(800, 420)]) {
    testWidgets('the card and the viewer fit at ${size.width.toInt()}x'
        '${size.height.toInt()}', (tester) async {
      await pumpCard(tester, size: size);
      await turnOn(tester);
      // More than the viewer's height, with lines wider than a phone.
      for (var i = 0; i < 40; i++) {
        log.record('[Line] $i ${'a long run of words ' * 12}');
      }
      await tester.tap(find.byKey(const ValueKey('debug-log-view')));
      await settle(tester, () => shows(find.byType(DebugLogText)));

      expect(tester.takeException(), isNull);
      await closeLog(tester);
    });
  }
}
