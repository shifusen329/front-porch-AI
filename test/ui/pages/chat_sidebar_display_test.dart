// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Expression Images → Display in the chat: the sidebar portrait (the phone's
// Stats & story sheet draws the same widget at 160 px) shows the expression
// for Sidebar Only and Both, and the plain portrait for Background Only and
// None; the dimmed expression behind the chat shows for Background Only and
// Both. The visual novel stage shows expressions under every choice. A real
// ChatService over a real library; its one expression image is the one it
// resolves.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/pages/chat_expression_backdrop.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar_widgets.dart';

import 'home/home_page_harness.dart';

// A 1×1 PNG, so the pictures decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
);

void main() {
  late HomeRig rig;
  late CharacterCard mira;
  late File portrait;
  late File joy;

  Future<void> setUpRig(WidgetTester tester) async {
    rig = await HomeRig.build(tester);
    await tester.runAsync(() async {
      final avatars = rig.storage.characterAvatarDir('Mira');
      portrait = File(p.join(rig.root.path, 'portrait.png'))
        ..writeAsBytesSync(_png);
      joy = File(p.join(avatars.path, 'joy.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(_png);
      await rig.storage.expressionSettings.setExpressionEnabled(true);
    });
    mira = CharacterCard(
      name: 'Mira',
      imagePath: portrait.path,
      avatarImages: [
        AvatarImage(
          id: 'joy-1',
          characterId: 'mira',
          filename: 'joy.png',
          label: 'joy',
          displayOrder: 0,
          createdAt: DateTime(2026, 10, 31),
        ),
      ],
    );
  }

  Future<void> pump(WidgetTester tester, String display, Widget child) async {
    await tester.runAsync(
      () => rig.storage.expressionSettings.setExpressionDisplayMode(display),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: rig.storage),
          ChangeNotifierProvider<ChatService>.value(value: rig.chat),
          ChangeNotifierProvider<CharacterRepository>.value(
            value: rig.characters,
          ),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
  }

  Future<String?> sidebarShows(
    WidgetTester tester,
    String display,
    double width,
  ) async {
    await pump(
      tester,
      display,
      SizedBox(
        width: width,
        child: ChatSidebarPortrait(
          character: mira,
          isGroup: false,
          sidebarWidth: width,
          resolveCharImage: File.new,
        ),
      ),
    );
    final shown = tester
        .widget<CharacterPortrait>(find.byType(CharacterPortrait))
        .file;
    return shown == null ? null : p.normalize(shown.path);
  }

  Future<bool> backdropShows(WidgetTester tester, String display) async {
    await pump(
      tester,
      display,
      Stack(children: [ChatExpressionBackdrop(character: mira, novel: false)]),
    );
    return find.byKey(const ValueKey('expr_bg_joy-1')).evaluate().isNotEmpty;
  }

  for (final width in [300.0, 160.0]) {
    testWidgets('the sidebar at $width px follows Display', (tester) async {
      await setUpRig(tester);
      expect(
        await sidebarShows(tester, 'sidebar', width),
        p.normalize(joy.path),
      );
      expect(await sidebarShows(tester, 'both', width), p.normalize(joy.path));
      expect(
        await sidebarShows(tester, 'background', width),
        p.normalize(portrait.path),
      );
      expect(
        await sidebarShows(tester, 'none', width),
        p.normalize(portrait.path),
      );
    });
  }

  testWidgets('the dimmed expression behind the chat follows Display', (
    tester,
  ) async {
    await setUpRig(tester);
    expect(await backdropShows(tester, 'background'), isTrue);
    expect(await backdropShows(tester, 'both'), isTrue);
    expect(await backdropShows(tester, 'sidebar'), isFalse);
    expect(await backdropShows(tester, 'none'), isFalse);
  });

  testWidgets('an unknown Display is refused and changes nothing', (
    tester,
  ) async {
    await setUpRig(tester);
    final settings = rig.storage.expressionSettings;
    await tester.runAsync(() => settings.setExpressionDisplayMode('none'));
    Object? refused;
    await tester.runAsync(() async {
      try {
        await settings.setExpressionDisplayMode('sideways');
      } catch (e) {
        refused = e;
      }
    });
    expect(refused, isA<ArgumentError>());
    expect(settings.expressionDisplayMode, 'none');
  });

  // The phone web app's header picture and insight portrait load
  // /api/chat/expression-avatar; with no picture there they fall back to the
  // portrait, as the desktop sidebar does.
  testWidgets('the phone web app gets no expression picture under None', (
    tester,
  ) async {
    await setUpRig(tester);
    final facade = CharacterFacade(
      rig.db,
      rig.storage,
      rig.folders,
      rig.chat,
      rig.characters,
    );
    final settings = rig.storage.expressionSettings;
    File? sidebar;
    File? none;
    await tester.runAsync(() async {
      await rig.characters.addCharacter(mira);
      await rig.chat.setActiveCharacter(mira);
      await settings.setExpressionDisplayMode('sidebar');
      sidebar = facade.activeExpressionAvatarFile();
      await settings.setExpressionDisplayMode('none');
      none = facade.activeExpressionAvatarFile();
    });
    expect(p.normalize(sidebar!.path), p.normalize(joy.path));
    expect(none, isNull);
  });
}
