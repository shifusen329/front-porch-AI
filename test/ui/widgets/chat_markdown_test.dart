// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Show markdown formatting in messages: the inline
// markdown rules (the phone web app's twin is chatMarkdown.test.ts), a chat
// bubble with the switch on and off, the switch itself, and the setting
// through the phone web app's /api/settings.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/chat_appearance_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

/// [text]'s runs as `[i a]waves`: b bold, i italic, s struck, c code; then
/// a for the action colour, d for dialogue.
String _shown(String text) => [
  for (final r in chatMarkdownRuns(text))
    () {
      final tags = [
        if (r.bold) 'b',
        if (r.italic) 'i',
        if (r.strike) 's',
        if (r.code) 'c',
        if (r.colour == StyledTokenType.action) 'a',
        if (r.colour == StyledTokenType.dialogue) 'd',
      ].join(' ');
      final piece = text.substring(r.start, r.end);
      return tags.isEmpty ? piece : '[$tags]$piece';
    }(),
].join('|');

String _plainOf(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText).first).text.toPlainText();

class _Llm extends FakeLLMProvider {
  final OpenRouterService remote = OpenRouterService();
  @override
  OpenRouterService get openRouterService => remote;
}

void main() {
  setupPathProviderMock();

  group('the rules', () {
    test('stars give italics and bold in the action colour', () {
      expect(_shown('*waves*'), '[i a]waves');
      expect(_shown('**finally**'), '[b a]finally');
      expect(_shown('***both***'), '[b i a]both');
      expect(_shown('She *smiles*.'), 'She |[i a]smiles|.');
    });

    test('underscores and tildes keep the colour around them', () {
      expect(_shown('__loud__ and _soft_'), '[b]loud| and |[i]soft');
      expect(_shown('~~gone~~'), '[s]gone');
      expect(_shown('snake_case_name'), 'snake_case_name');
    });

    test('nothing is rendered inside code', () {
      expect(_shown('run `*not italic*` now'), 'run |[c]*not italic*| now');
    });

    test('dialogue keeps its quotes and can hold emphasis', () {
      expect(_shown('"I *really* mean it"'), '[d]"I |[i d]really|[d] mean it"');
    });

    test('emphasis nests inside an action', () {
      expect(_shown('*a **b** c*'), '[i a]a |[b i a]b|[i a] c');
    });

    test('marks with no partner, a space inside or a line break stay', () {
      expect(_shown('*walks over'), '*walks over');
      expect(_shown('2 * 3 * 4'), '2 * 3 * 4');
      expect(_shown('*one\ntwo*'), '*one\ntwo*');
    });
  });

  group('a chat bubble', () {
    late StorageService storage;

    Future<void> pump(WidgetTester tester, String text) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        storage = StorageService();
        await storage.initialized;
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(body: StyledChatMessage(text: text, isUser: false)),
          ),
        ),
      );
    }

    testWidgets('shows the formatting without the marks, by default', (
      tester,
    ) async {
      await pump(tester, '*waves* and **grins**');
      expect(_plainOf(tester), 'waves and grins');
      final spans = <TextSpan>[];
      tester.widget<RichText>(find.byType(RichText).first).text.visitChildren((
        s,
      ) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      final waves = spans.firstWhere((s) => s.text == 'waves');
      final grins = spans.firstWhere((s) => s.text == 'grins');
      expect(waves.style?.fontStyle, FontStyle.italic);
      expect(grins.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('switched off, shows the message as written', (tester) async {
      await pump(tester, '*waves* and **grins**');
      await tester.runAsync(
        () => storage.expressionSettings.setChatMarkdown(false),
      );
      await tester.pump();
      expect(_plainOf(tester), '*waves* and **grins**');
    });
  });

  testWidgets('the switch in Settings → Appearance saves the choice', (
    tester,
  ) async {
    late StorageService storage;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      storage = StorageService();
      await storage.initialized;
    });
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ChatAppearanceSection()),
          ),
        ),
      ),
    );
    final tile = find.byKey(const ValueKey('chat-markdown'));
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pump();
    expect(storage.expressionSettings.chatMarkdown, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('chat_markdown'), isFalse);
  });

  group('the phone web app', () {
    late Directory root;
    late AppDatabase db;
    late StorageService storage;
    late Router router;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fpai chat markdown');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? root.path
                : null,
          );
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.initialized;
      router = Router();
      WebSettingsRoutes(
        WebServerDeps(
          storage: storage,
          db: db,
          auth: AuthService(db),
          settingsFacade: SettingsFacade(storage, _Llm()),
        ),
        router,
      );
    });

    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    Future<Map<String, dynamic>> call(String method, [Object? body]) async {
      final res = await router.call(
        shelf.Request(
          method,
          Uri.parse('http://localhost/api/settings'),
          headers: {'content-type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        ),
      );
      expect(res.statusCode, 200);
      return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    }

    test('reads and writes the setting through /api/settings', () async {
      expect((await call('GET'))['chatMarkdown'], isTrue);

      await call('POST', {'chatMarkdown': false});
      expect(storage.expressionSettings.chatMarkdown, isFalse);
      expect((await call('GET'))['chatMarkdown'], isFalse);
    });
  });
}
