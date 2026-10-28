// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app and the phone web app change layout at the same widths. The
// numbers live twice (Dart and TypeScript); this keeps them equal.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/layout/layout.dart';

double _tsConst(String source, String name) {
  final m = RegExp('const $name\\s*=\\s*(\\d+)').firstMatch(source);
  if (m == null) fail('$name not found in useBreakpoint.ts');
  return double.parse(m.group(1)!);
}

void main() {
  test('Dart breakpoints match web_ui/src/hooks/useBreakpoint.ts', () {
    final ts = File('web_ui/src/hooks/useBreakpoint.ts').readAsStringSync();
    expect(_tsConst(ts, 'TABLET_MIN'), kTabletMinWidth);
    expect(_tsConst(ts, 'DESKTOP_MIN'), kDesktopMinWidth);
  });
}
