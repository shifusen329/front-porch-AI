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

import 'package:flutter/foundation.dart';

import 'debug_log_store.dart';

/// Runs the app's [body] so that everything it prints and every error
/// nothing caught reach [log] as well as the console.
///
/// A test harness that built the Flutter binding first keeps its own zone:
/// starting the app in a new one there trips the binding's zone-mismatch
/// check. Release builds never track the binding type, so they always run
/// in the log's zone.
R runWithDebugLog<R>(DebugLog log, R Function() body) {
  if (BindingBase.debugBindingType() != null) return body();
  installDebugLogHooks(log);
  return runInDebugLogZone(log, body);
}

/// Runs [body] so that the `print` calls in it, and in everything it
/// starts, reach [log] as well as the console.
R runInDebugLogZone<R>(DebugLog log, R Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      log.record(line);
      parent.print(zone, line);
    },
  ),
);

/// Sends `debugPrint`, framework errors and uncaught errors to [log], and
/// still to wherever they went before. Returns what puts the old hooks back.
///
/// `debugPrint` is recorded when it is called, not when its throttle lets
/// the line out, and its console copy is printed in the root zone so the
/// zone in [runWithDebugLog] does not record it a second time. A framework
/// error is recorded in full here, so the console report it then makes is
/// not recorded again.
VoidCallback installDebugLogHooks(DebugLog log) {
  final console = debugPrint;
  final frameworkErrors = FlutterError.onError;
  final dispatcher = PlatformDispatcher.instance;
  final uncaught = dispatcher.onError;
  var reporting = false;

  debugPrint = (String? message, {int? wrapWidth}) {
    if (!reporting) log.record(message ?? 'null');
    Zone.root.run(() => console(message, wrapWidth: wrapWidth));
  };
  FlutterError.onError = (details) {
    final context = details.context?.toDescription();
    log.record(
      '[FlutterError] ${details.exceptionAsString()}'
      '${context == null || context.isEmpty ? '' : ' ($context)'}'
      '${details.stack == null ? '' : '\n${details.stack}'}',
    );
    reporting = true;
    try {
      frameworkErrors?.call(details);
    } finally {
      reporting = false;
    }
  };
  dispatcher.onError = (error, stack) {
    log.record('[Uncaught] $error\n$stack');
    return uncaught?.call(error, stack) ?? false;
  };
  return () {
    debugPrint = console;
    FlutterError.onError = frameworkErrors;
    dispatcher.onError = uncaught;
  };
}
