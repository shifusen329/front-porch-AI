// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Backend → Memory search, driven like a user: type a model
// server's URL, Load models, pick from a dropdown that holds only the
// server's embedding models, and see the engine come up. Then Clear and
// re-vectorize: a double-tapped confirm rebuilds once, every stored vector
// comes from the new model, and a model change after that warns that the
// stored vectors are another model's. Against a real loopback server
// (embedding_protocol_server); fits at 400 and 1440 wide.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory/memory.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/backend.dart';

import '../../helpers/double_tap.dart';
import '../../helpers/embedding_protocol_server.dart';

const _snowflake = 'snowflake-arctic-embed-l-v2.0:latest';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_mem_search_').path;
        }
        return null;
      });
}

/// Lets real I/O land, a frame at a time, until [done] or about 5 s.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'timed out waiting');
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  late EmbeddingProtocolServer server;
  late StorageService storage;
  late EmbeddingService emb;

  Future<void> boot(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    await tester.runAsync(() async {
      server = await EmbeddingProtocolServer.start(ollama: true);
      SharedPreferences.setMockInitialValues({...prefs});
      storage = StorageService();
      await storage.initialized;
      emb = EmbeddingService(storage);
    });
  }

  /// Unmounts, then closes the service's HTTP client, whose keep-alive
  /// timers would otherwise outlive the test.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    emb.dispose();
  }

  Widget app(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<StorageService>.value(value: storage),
      ChangeNotifierProvider<EmbeddingService>.value(value: emb),
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('type a server, load its models, pick one from the dropdown, '
      'and memory search is ready', (tester) async {
    await boot(tester);
    await tester.pumpWidget(app(const MemorySearchSection()));
    await tester.tap(find.text('Model server'));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('embedding-url-field')),
      server.url,
    );
    await tester.tap(find.byKey(const Key('embedding-load-models')));
    await _settle(tester, () => find.text('Pick one').evaluate().isNotEmpty);
    expect(storage.memorySettings.embeddingEndpointUrl, server.url);

    await tester.tap(find.byKey(const Key('embedding-model-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('qwen3:8b'), findsNothing, reason: 'a chat model');
    expect(find.text('nomic-embed-text-v1.5-F16:latest'), findsWidgets);
    await tester.tap(find.text(_snowflake).last);
    await _settle(tester, () => emb.isAvailable);
    await tester.pump();

    expect(storage.memorySettings.embeddingEndpointModel, _snowflake);
    expect(server.embedModels.last, _snowflake);
    expect(find.text('Memory engine ready'), findsOneWidget);
    expect(
      find.textContaining('${server.dims}-dimension vectors'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('clear and re-vectorize rebuilds once, then a model change warns '
      'the vectors are another model\'s', (tester) async {
    await boot(tester);
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(() => tester.runAsync(db.close));
    late VectorRebuilder rebuilder;
    await tester.runAsync(() async {
      final s = storage.memorySettings;
      await s.setEmbeddingProvider('endpoint');
      await s.setEmbeddingEndpointUrl(server.url);
      await s.setEmbeddingEndpointModel(_snowflake);
      await emb.checkAvailability();
      final old = Float32List.fromList(const [1, 1, 1, 1]).buffer.asUint8List();
      for (var i = 0; i < 20; i++) {
        await db
            .into(db.messageEmbeddings)
            .insert(
              MessageEmbeddingsCompanion.insert(
                id: 'w${i.toString().padLeft(2, '0')}',
                sessionId: 's1',
                positionStart: i * 5,
                positionEnd: i * 5 + 4,
                content: 'Bex: evening number $i',
                embedding: old,
                dimensions: 4,
              ),
            );
      }
      rebuilder = VectorRebuilder(embeddings: emb, db: () => db);
    });
    await tester.pumpWidget(
      app(VectorRebuildCard(rebuilder: rebuilder, embeddings: emb)),
    );
    await _settle(tester, () => rebuilder.counts != null);
    expect(find.textContaining('20 saved memories'), findsOneWidget);

    final requestsBefore = server.embedInputs.length;
    await tester.tap(find.byKey(const Key('vector-rebuild-button')));
    await tester.pumpAndSettle();
    await doubleTapNoFrame(tester, find.text('Re-vectorize'));
    await _settle(
      tester,
      () =>
          !rebuilder.running &&
          rebuilder.counts?.missing == 0 &&
          rebuilder.done > 0,
    );
    // 20 windows in batches of 16: two requests, from one rebuild.
    expect(server.embedInputs.length - requestsBefore, 2);
    final rows = await tester.runAsync(
      () => db.select(db.messageEmbeddings).get(),
    );
    expect(rows!.every((r) => r.dimensions == server.dims), isTrue);
    expect(find.byKey(const Key('vector-model-mismatch')), findsNothing);

    await tester.runAsync(
      () => storage.memorySettings.setEmbeddingEndpointModel(
        'nomic-embed-text-v1.5-F16:latest',
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('vector-model-mismatch')), findsOneWidget);
    await finish(tester);
  });

  for (final width in [400.0, 1440.0]) {
    testWidgets('the section fits at ${width.toInt()} wide', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await boot(tester);
      await tester.runAsync(() async {
        await storage.memorySettings.setEmbeddingEndpointUrl(server.url);
        await storage.memorySettings.setEmbeddingEndpointModel(_snowflake);
      });
      await tester.pumpWidget(app(const MemorySearchSection()));
      await _settle(tester, () => find.text(_snowflake).evaluate().isNotEmpty);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
}
