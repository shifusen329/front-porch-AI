// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The debug log: what it keeps before it is on, the file it writes while it
// is on, turning over a full file, Clear, blanked secrets, and the hooks
// that send print, debugPrint and errors to it.

import 'dart:io';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/debug_log/debug_log.dart';

void main() {
  late Directory dir;
  var now = DateTime(2026, 10, 31, 11, 2, 3, 4);
  final made = <DebugLog>[];

  DebugLog newLog({int maxBytes = 5 * 1024 * 1024}) {
    final log = DebugLog(
      folder: () async => Directory(p.join(dir.path, 'logs')),
      clock: () => now,
      maxBytes: maxBytes,
    );
    made.add(log);
    return log;
  }

  File logFile(String name) => File(p.join(dir.path, 'logs', name));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai_debug_log_');
    now = DateTime(2026, 10, 31, 11, 2, 3, 4);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    // Windows will not delete a file a log still holds open.
    for (final log in made) {
      if (log.enabled) await log.setEnabled(false);
    }
    made.clear();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('the file', () {
    test(
      'a log that is off keeps lines in memory and writes no file',
      () async {
        final log = newLog();
        log.record('[Chat] sent');
        expect(log.enabled, isFalse);
        expect(await log.size(), 0);
        expect(await log.contents(), isEmpty);
        expect(await logFile(DebugLog.fileName).exists(), isFalse);
      },
    );

    test('turning it on writes a header, the lines from before, and the '
        'lines after, each with the time, and is remembered', () async {
      final log = newLog();
      log.record('[Chat] before');
      now = now.add(const Duration(seconds: 1));
      await log.setEnabled(true);
      log.record('[Chat] after');

      final text = await log.contents();
      final lines = text.trimRight().split('\n');
      expect(lines.first, startsWith('==== Front Porch AI '));
      expect(lines.first, contains('debug log turned on'));
      expect(lines[1], '2026-10-31 11:02:03.004  [Chat] before');
      expect(lines[2], '2026-10-31 11:02:04.004  [Chat] after');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(DebugLog.prefKey), isTrue);
    });

    test('at launch the file opens when the log was left on', () async {
      SharedPreferences.setMockInitialValues({DebugLog.prefKey: true});
      final log = newLog();
      log.record('[Startup] binding ready');
      await log.start();
      log.record('[DB] opened');

      expect(log.enabled, isTrue);
      final text = await log.contents();
      expect(text, contains('app started'));
      expect(
        text.indexOf('[Startup] binding ready'),
        lessThan(text.indexOf('[DB] opened')),
      );
    });

    test('at launch nothing is written when the log was left off', () async {
      final log = newLog();
      log.record('[Startup] binding ready');
      await log.start();
      expect(log.enabled, isFalse);
      expect(await logFile(DebugLog.fileName).exists(), isFalse);
    });

    test('turning it off stops writing and is remembered', () async {
      final log = newLog();
      await log.setEnabled(true);
      log.record('[Chat] kept');
      await log.setEnabled(false);
      log.record('[Chat] not kept');

      final text = await log.contents();
      expect(text, contains('[Chat] kept'));
      expect(text, contains('debug log turned off'));
      expect(text, isNot(contains('[Chat] not kept')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(DebugLog.prefKey), isFalse);
    });

    test('a message over several lines keeps them under one time', () async {
      final log = newLog();
      await log.setEnabled(true);
      log.record('[Uncaught] Bad state\n#0 main (a.dart:1)\n#1 run (b.dart:2)');
      final text = await log.contents();
      expect(
        text,
        contains(
          '2026-10-31 11:02:03.004  [Uncaught] Bad state\n'
          '    #0 main (a.dart:1)\n'
          '    #1 run (b.dart:2)\n',
        ),
      );
    });

    test('a full file becomes the .1 file and a new one starts', () async {
      final log = newLog(maxBytes: 600);
      await log.setEnabled(true);
      for (var i = 0; i < 40; i++) {
        log.record('[Line] number $i of the long run');
      }
      final text = await log.contents();

      expect(await logFile(DebugLog.olderFileName).exists(), isTrue);
      expect(await logFile(DebugLog.fileName).exists(), isTrue);
      expect(text, contains('continued from ${DebugLog.olderFileName}'));
      expect(text, contains('[Line] number 39 of the long run'));
      expect(text, isNot(contains('[Line] number 0 of the long run')));
      expect(await log.size(), lessThan(3 * 600));
    });

    test('a file that fills while the lines from before go in turns over '
        'once and keeps them all', () async {
      final log = newLog(maxBytes: 600);
      for (var i = 0; i < 40; i++) {
        log.record('[Line] number $i of the long run');
      }
      await log.setEnabled(true);

      final text = await log.contents();
      expect(text, contains('[Line] number 0 of the long run'));
      expect(text, contains('[Line] number 39 of the long run'));
    });

    test('Clear deletes the log and a log that is on starts again', () async {
      final log = newLog();
      await log.setEnabled(true);
      log.record('[Chat] old');
      await log.clear();
      log.record('[Chat] new');

      final text = await log.contents();
      expect(text, isNot(contains('[Chat] old')));
      expect(text, contains('log cleared'));
      expect(text, contains('[Chat] new'));
    });

    test('Clear on a log that is off leaves no file', () async {
      final log = newLog();
      await log.setEnabled(true);
      log.record('[Chat] old');
      await log.setEnabled(false);
      await log.clear();
      expect(await log.size(), 0);
      expect(await logFile(DebugLog.fileName).exists(), isFalse);
    });

    test(
      'a folder that cannot be made turns the log off and says why',
      () async {
        // A file where the folder should be.
        await File(p.join(dir.path, 'logs')).writeAsString('in the way');
        final log = newLog();
        await log.setEnabled(true);
        log.record('[Chat] after');

        expect(log.enabled, isFalse);
        expect(log.problem, isNotNull);
      },
    );
  });

  group('secrets', () {
    test('keys, tokens and passwords are blanked in the file; chat text '
        'stays', () async {
      final log = newLog();
      await log.setEnabled(true);
      log.record('[HTTP] Authorization: Bearer abcdefghij0123456789');
      log.record(
        '[Gemini] GET https://x.test/v1/models?key=AIzaSyA1234567890abcdefghijklmnopqrstu',
      );
      log.record(
        '[OpenRouter] body {"api_key": "sk-or-v1-0123456789abcdef", "model": "m"}',
      );
      log.record('[Stoop] {"password":"hunter22","email":"a@b.c"}');
      log.record('[xAI] key xai-ABCDEFGHIJKLMNOPQRSTUVWX failed');
      log.record('[Chat] Mara said: "the key is under the mat"');

      final text = await log.contents();
      for (final secret in [
        'abcdefghij0123456789',
        'AIzaSyA1234567890abcdefghijklmnopqrstu',
        'sk-or-v1-0123456789abcdef',
        'hunter22',
        'xai-ABCDEFGHIJKLMNOPQRSTUVWX',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(text, contains('Bearer $kRedacted'));
      expect(text, contains('"model": "m"'));
      expect(text, contains('the key is under the mat'));
    });
  });

  group('capture', () {
    late DebugLogTestHooks saved;
    setUp(() => saved = DebugLogTestHooks.save());
    tearDown(() => saved.restore());

    test('print and debugPrint each reach the log once, and the console '
        'still gets debugPrint', () async {
      final console = <String>[];
      // Like the real debugPrint, the console copy ends in print().
      debugPrint = (String? m, {int? wrapWidth}) {
        console.add(m ?? '');
        print(m);
      };
      final log = newLog();
      await log.setEnabled(true);

      installDebugLogHooks(log);
      runInDebugLogZone(log, () {
        print('[TTS] raw print');
        debugPrint('[Chat] debug print');
      });

      final text = await log.contents();
      expect('[TTS] raw print'.allMatches(text).length, 1);
      expect('[Chat] debug print'.allMatches(text).length, 1);
      expect(console, ['[Chat] debug print']);
    });

    test(
      'a framework error is recorded once, in full, and still reported',
      () async {
        final reported = <FlutterErrorDetails>[];
        FlutterError.onError = (details) {
          reported.add(details);
          debugPrint('console report of ${details.exception}');
        };
        debugPrint = (String? m, {int? wrapWidth}) {};
        final log = newLog();
        await log.setEnabled(true);
        installDebugLogHooks(log);

        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError('boom'),
            stack: StackTrace.fromString('#0 build (card.dart:12)'),
            context: ErrorDescription('while building the card'),
          ),
        );

        final text = await log.contents();
        expect(reported, hasLength(1));
        expect(
          text,
          contains(
            '[FlutterError] Bad state: boom (while building the card)\n'
            '    #0 build (card.dart:12)',
          ),
        );
        expect(text, isNot(contains('console report of')));
      },
    );

    test('an uncaught error is recorded and handed on', () async {
      final handed = <Object>[];
      PlatformDispatcher.instance.onError = (error, stack) {
        handed.add(error);
        return true;
      };
      final log = newLog();
      await log.setEnabled(true);
      installDebugLogHooks(log);

      final handled = PlatformDispatcher.instance.onError!(
        StateError('lost'),
        StackTrace.fromString('#0 later (timer.dart:3)'),
      );

      expect(handled, isTrue);
      expect(handed, hasLength(1));
      expect(
        await log.contents(),
        contains('[Uncaught] Bad state: lost\n    #0 later (timer.dart:3)'),
      );
    });

    test(
      'a harness that built the binding keeps its own zone and hooks',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final before = debugPrint;
        final log = newLog();
        await log.setEnabled(true);

        runWithDebugLog(log, () => print('[Harness] print'));

        expect(identical(debugPrint, before), isTrue);
        expect(await log.contents(), isNot(contains('[Harness] print')));
      },
    );
  });
}

/// The global hooks a capture test changes, so each test puts them back.
class DebugLogTestHooks {
  DebugLogTestHooks._(this._print, this._errors, this._uncaught);

  factory DebugLogTestHooks.save() => DebugLogTestHooks._(
    debugPrint,
    FlutterError.onError,
    PlatformDispatcher.instance.onError,
  );

  final DebugPrintCallback _print;
  final FlutterExceptionHandler? _errors;
  final ErrorCallback? _uncaught;

  void restore() {
    debugPrint = _print;
    FlutterError.onError = _errors;
    PlatformDispatcher.instance.onError = _uncaught;
  }
}
