// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// On a phone the app draws behind the status and navigation bars. Their
// icons must follow the app's own light/dark (it picks its own theme), or
// dark icons vanish on Porch dark — the bars are transparent either way.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/app/app.dart';

SystemUiOverlayStyle _publishedBy(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    )
    .value;

void main() {
  for (final (brightness, icons) in [
    (Brightness.dark, Brightness.light),
    (Brightness.light, Brightness.dark),
  ]) {
    testWidgets('a ${brightness.name} app gets ${icons.name} system-bar '
        'icons over transparent bars', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => PhoneSystemBars(child: child!),
          home: const SizedBox(),
        ),
      );

      final style = _publishedBy(tester);
      expect(style.statusBarIconBrightness, icons);
      expect(style.systemNavigationBarIconBrightness, icons);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
    });
  }
}
