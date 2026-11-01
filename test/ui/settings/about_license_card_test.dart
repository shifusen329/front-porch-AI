// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → About & License: Source code opens this fork, the
// source of the build being run (AGPL §13), and license reports go to its
// issues.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/settings/tabs/general_tab/about_license_card.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  late List<String> opened;

  setUp(() {
    opened = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launch') {
            opened.add((call.arguments as Map)['url'] as String);
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('Source code and a license report open this fork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AboutLicenseCard())),
    );

    await tester.tap(find.text('Source code'));
    await tester.pump();
    await tester.tap(find.text('Report a license violation'));
    await tester.pump();

    expect(opened, [
      'https://github.com/shifusen329/front-porch-AI',
      'https://github.com/shifusen329/front-porch-AI/issues',
    ]);
  });
}
