// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_provider_bar.dart';
import 'package:front_porch_ai/utils/utils.dart';

void main() {
  testWidgets('one row of hosts; oMLX omitted unless showOmlx', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteProviderBar(
            selected: RemoteProviderKind.openRouter,
            onSelected: _noop,
          ),
        ),
      ),
    );

    expect(find.text('KoboldCpp'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Nano-GPT'), findsOneWidget);
    expect(find.text('LM Studio'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('oMLX'), findsNothing);
    expect(find.text('Local'), findsNothing);
    expect(find.text('Remote API'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteProviderBar(
            selected: RemoteProviderKind.omlx,
            showOmlx: true,
            onSelected: _noop,
          ),
        ),
      ),
    );
    expect(find.text('oMLX'), findsOneWidget);
  });

  testWidgets('a phone offers REST hosts only: no KoboldCpp, no LM Studio', (
    tester,
  ) async {
    PlatformCaps.debugOverride = const PlatformCaps(isDesktop: false);
    addTearDown(() => PlatformCaps.debugOverride = PlatformCaps.host());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteProviderBar(
            selected: RemoteProviderKind.openRouter,
            showOmlx: true,
            onSelected: _noop,
          ),
        ),
      ),
    );

    expect(find.text('KoboldCpp'), findsNothing);
    expect(find.text('LM Studio'), findsNothing);
    expect(find.text('oMLX'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Nano-GPT'), findsOneWidget);
    expect(find.text('xAI'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
  });
}

void _noop(RemoteProviderKind _) {}
