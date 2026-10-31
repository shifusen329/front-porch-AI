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

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';

import 'log_scrubber.dart';

/// Everything the app prints, with the time. The last [recentChars] of it is
/// kept in memory all the time, so turning the log on also keeps the latest
/// lines from before; while the log is on it goes to a file on this device
/// too (Settings → General → Troubleshooting).
///
/// The file is capped at [maxBytes]: past that it becomes the `.1` file and
/// a new one starts, so the log never holds more than twice that.
class DebugLog extends ChangeNotifier {
  DebugLog({
    required Future<Directory> Function() folder,
    DateTime Function()? clock,
    this.maxBytes = 5 * 1024 * 1024,
    this.recentChars = 256 * 1024,
  }) : _folder = folder,
       _now = clock ?? DateTime.now;

  /// The app's own log, in the app support folder: never the library, so
  /// library sync and backups leave it alone.
  static final DebugLog instance = DebugLog(
    folder: () async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'logs'),
    ),
  );

  static String get prefKey =>
      isPreRelease ? 'beta_debug_logging' : 'debug_logging';
  static String get fileName =>
      isPreRelease ? 'front_porch_beta.log' : 'front_porch.log';
  static String get olderFileName =>
      fileName.replaceFirst(RegExp(r'\.log$'), '.1.log');

  final Future<Directory> Function() _folder;
  final DateTime Function() _now;
  final int maxBytes;
  final int recentChars;

  final ListQueue<String> _recent = ListQueue();
  int _recentLength = 0;
  bool _enabled = false;
  IOSink? _sink;
  int _bytes = 0;
  // Lines that arrive while the file opens, flushes, turns over or clears:
  // an IOSink refuses writes during a flush.
  final List<String> _pending = [];
  bool _busy = false;
  // A full file waits for one turnover; lines after the cap go to the next
  // file, never into the one being moved aside.
  bool _turnoverDue = false;
  Future<void> _work = Future.value();
  String? _problem;

  bool get enabled => _enabled;

  /// Why the file could not be written, the last time it could not.
  String? get problem => _problem;

  /// Where the log files live.
  Future<String> folderPath() async => (await _folder()).path;

  /// Keeps [message] with the time, and writes it to the file while the log
  /// is on. Called for every line the app prints.
  void record(String message) {
    final line = _stamp(message);
    _recent.addLast(line);
    _recentLength += line.length;
    while (_recentLength > recentChars && _recent.length > 1) {
      _recentLength -= _recent.removeFirst().length;
    }
    if (!_enabled) return;
    final sink = _sink;
    if (sink == null || _busy || _turnoverDue) {
      _pending.add(line);
    } else {
      _write(sink, line);
    }
  }

  /// At launch: opens the file when the log was left on.
  Future<void> start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(prefKey) ?? false) await _turnOn('app started');
    } catch (e) {
      _console('[DebugLog] could not start: $e');
    }
  }

  /// Turns the log on or off and remembers it for the next launch.
  Future<void> setEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, on);
    if (on == _enabled) return;
    if (on) {
      await _turnOn('debug log turned on');
    } else {
      record('[DebugLog] debug log turned off');
      _enabled = false;
      await _serial(() => _close(takePending: true));
    }
    notifyListeners();
  }

  /// The log as one text, older file first, with every line recorded so
  /// far. Empty when there is none.
  Future<String> contents() async {
    final parts = <String>[];
    await _read((file) async => parts.add(await file.readAsString()));
    return parts.join();
  }

  /// How big the log files are together, in bytes.
  Future<int> size() async {
    var total = 0;
    await _read((file) async => total += await file.length());
    return total;
  }

  // Reads each log file that exists, oldest first, once the lines waiting
  // on a turnover are in. It runs in the queue, so no turnover moves a file
  // while it is being read, and a failed read leaves the log on.
  Future<void> _read(Future<void> Function(File file) each) async {
    while (true) {
      final work = _work;
      await work;
      if (identical(work, _work)) break;
    }
    Object? failure;
    await _serial(() async {
      await _flush();
      try {
        final dir = await _folder();
        for (final name in [olderFileName, fileName]) {
          final file = File(p.join(dir.path, name));
          if (await file.exists()) await each(file);
        }
      } catch (e) {
        failure = e;
      }
    });
    if (failure != null) throw failure!;
  }

  /// Deletes the log files and what is kept in memory. A log that is on
  /// starts again in a new file.
  Future<void> clear() async {
    _recent.clear();
    _recentLength = 0;
    await _serial(() async {
      await _close();
      final dir = await _folder();
      for (final name in [olderFileName, fileName]) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) await file.delete();
      }
      if (_enabled) await _open('log cleared', const []);
    });
    notifyListeners();
  }

  Future<void> _turnOn(String reason) async {
    // What happened before is written first; lines recorded from here on
    // wait in _pending until the file is open.
    final before = List.of(_recent);
    _enabled = true;
    await _serial(() => _open(reason, before));
  }

  Future<void> _serial(Future<void> Function() step) {
    final run = _work.then((_) async {
      _busy = true;
      try {
        await step();
      } catch (e) {
        _fail(e);
      } finally {
        _busy = false;
        final sink = _sink;
        if (sink != null) {
          var i = 0;
          while (i < _pending.length && !_turnoverDue) {
            _write(sink, _pending[i++]);
          }
          _pending.removeRange(0, i);
        } else if (!_enabled) {
          // Lines kept for a file that is closed for good. A log being
          // turned on keeps them for the file about to open.
          _pending.clear();
        }
      }
    });
    _work = run;
    return run;
  }

  Future<void> _open(String reason, List<String> before) async {
    final dir = await _folder();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    _bytes = await file.exists() ? await file.length() : 0;
    if (_bytes >= maxBytes) {
      await _turnOver(dir, file);
      _bytes = 0;
    }
    final sink = file.openWrite(mode: FileMode.append);
    sink.done.then<void>(
      (_) {},
      onError: (Object e) {
        if (identical(_sink, sink)) _fail(e);
      },
    );
    _sink = sink;
    _problem = null;
    _write(sink, _header(reason));
    for (final line in before) {
      _write(sink, line);
    }
  }

  Future<void> _flush() async {
    await _sink?.flush();
  }

  Future<void> _close({bool takePending = false}) async {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    if (takePending) {
      for (final line in _pending) {
        sink.writeln(scrubSecrets(line));
      }
      _pending.clear();
    }
    await sink.flush();
    await sink.close();
  }

  Future<void> _turnOver(Directory dir, File file) async {
    final older = File(p.join(dir.path, olderFileName));
    if (await older.exists()) await older.delete();
    await file.rename(older.path);
  }

  Future<void> _startNextFile() async {
    try {
      await _close();
      if (!_enabled) return;
      final dir = await _folder();
      await _turnOver(dir, File(p.join(dir.path, fileName)));
      await _open('continued from $olderFileName', const []);
    } finally {
      _turnoverDue = false;
    }
  }

  void _write(IOSink sink, String line) {
    final text = '${scrubSecrets(line)}\n';
    sink.write(text);
    _bytes += text.length;
    if (_bytes >= maxBytes && !_turnoverDue) {
      _turnoverDue = true;
      unawaited(_serial(_startNextFile));
    }
  }

  // The switch goes off rather than keep lines for a file that takes none;
  // the saved choice stays, so the next launch tries again.
  void _fail(Object e) {
    _sink = null;
    _enabled = false;
    _pending.clear();
    _problem = '$e';
    _console('[DebugLog] could not write the log: $e');
    notifyListeners();
  }

  String _stamp(String message) {
    final lines = message.split('\n');
    final head = '${_time(_now())}  ${lines.first}';
    if (lines.length == 1) return head;
    return [head, ...lines.skip(1).map((l) => '    $l')].join('\n');
  }

  String _header(String reason) {
    final mode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';
    return '==== Front Porch AI $appVersion · ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion} · $mode build · $reason · '
        '${_time(_now())} ====';
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  // A problem with the log itself goes to the console only: recording it
  // would ask the broken file to take another line.
  static void _console(String message) =>
      Zone.root.run(() => debugPrintThrottled(message));
}
