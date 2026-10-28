// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Memory search on a model server: the client speaks Ollama and the OpenAI
// API through one URL, lists only embedding models, gives queries and stored
// text the model's own prefixes, and Clear and re-vectorize replaces every
// stored vector (chat memories, Data Bank, Journal) with the current
// model's — refusing to clear when nothing can refill them, and resuming
// after a stop. Against a real loopback server (embedding_protocol_server)
// and, tagged `live`, against a real one named by EMBEDDING_LIVE_URL.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/embedding/native_embedding_engine.dart';
import 'package:front_porch_ai/services/embedding/remote_embedding_client.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory/memory.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/memory_search_facade.dart';

import '../../helpers/chat_db_teardown.dart';
import '../../helpers/embedding_protocol_server.dart';

const _snowflake = 'snowflake-arctic-embed-l-v2.0:latest';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_remote_emb_').path;
        }
        return null;
      });
}

Future<StorageService> _storage([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({...prefs});
  final storage = StorageService();
  await storage.initialized;
  return storage;
}

Future<EmbeddingService> _onServer(
  StorageService storage,
  EmbeddingProtocolServer server, {
  String model = _snowflake,
}) async {
  final s = storage.memorySettings;
  await s.setEmbeddingProvider(kEmbeddingEndpoint);
  await s.setEmbeddingEndpointUrl(server.url);
  await s.setEmbeddingEndpointModel(model);
  final emb = EmbeddingService(storage);
  await emb.checkAvailability();
  return emb;
}

List<double> _floats(Uint8List? bytes, int dims) =>
    bytes == null || dims == 0 ? const [] : bytesToVector(bytes, dims)!;

Uint8List _bytes(List<double> v) =>
    Float32List.fromList(v).buffer.asUint8List();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  group('RemoteEmbeddingClient', () {
    test('an Ollama server lists only its embedding models and embeds '
        'through /api/embed', () async {
      final server = await EmbeddingProtocolServer.start(ollama: true);
      addTearDown(server.close);
      final client = RemoteEmbeddingClient();

      final listed = await client.listModels(server.url);
      expect(listed.api, EmbeddingApi.ollama);
      expect(listed.models, [
        'nomic-embed-text-v1.5-F16:latest',
        _snowflake,
      ], reason: 'the chat model qwen3 is not an embedding model');

      // Pasted with /v1, as people copy it from a chat setup.
      final vectors = await client.embed(
        '${server.url}/v1',
        model: _snowflake,
        inputs: ['porch', 'swing'],
      );
      expect(server.embedModels.single, _snowflake);
      expect(vectors, [
        EmbeddingProtocolServer.vectorFor('porch', server.dims),
        EmbeddingProtocolServer.vectorFor('swing', server.dims),
      ]);
    });

    test('an OpenAI-compatible server lists embedding-looking ids and keeps '
        'input order', () async {
      final server = await EmbeddingProtocolServer.start(ollama: false);
      addTearDown(server.close);
      final client = RemoteEmbeddingClient();

      final listed = await client.listModels(server.url);
      expect(listed.api, EmbeddingApi.openAi);
      expect(listed.models, ['BAAI/bge-m3', 'text-embedding-3-small']);

      // The server answers last-first; the client orders by index. And a
      // pasted endpoint path still finds the base.
      final vectors = await client.embed(
        '${server.url}/embeddings',
        model: 'text-embedding-3-small',
        inputs: ['one', 'two', 'three'],
      );
      expect(vectors, [
        for (final t in ['one', 'two', 'three'])
          EmbeddingProtocolServer.vectorFor(t, server.dims),
      ]);
    });
  });

  group('EmbeddingService on a model server', () {
    test('a fresh install starts on a model server; one that set up the '
        'on-device model keeps it', () async {
      final freshStorage = await _storage();
      final fresh = EmbeddingService(freshStorage);
      // A machine with the on-device model already downloaded keeps it.
      if (NativeEmbeddingEngine.resolveModelFiles(freshStorage.rootPath) ==
          null) {
        expect(fresh.usesEndpoint, isTrue);
        expect(fresh.choice.isConfigured, isFalse);
        expect(fresh.choice.indexModel, '');
      }
      final consented = EmbeddingService(
        await _storage({'rag_setup_consented': true}),
      );
      expect(consented.usesEndpoint, isFalse);
      expect(
        consented.choice.indexModel,
        'onDevice|nomic-embed-text-v1.5',
        reason: 'vectors from before the setting are on-device ones',
      );
    });

    test(
      'stored text and search queries get the model\'s own prefixes',
      () async {
        final server = await EmbeddingProtocolServer.start(ollama: true);
        addTearDown(server.close);
        final storage = await _storage();
        final emb = await _onServer(storage, server);
        expect(emb.isAvailable, isTrue);
        expect(emb.dimensions, server.dims);

        expect(
          await emb.embed('the porch light'),
          EmbeddingProtocolServer.vectorFor('the porch light', server.dims),
        );
        await emb.embedQuery('what about the light?');
        expect(server.embedInputs.last, ['query: what about the light?']);
        expect(server.embedInputs[server.embedInputs.length - 2], [
          'the porch light',
        ], reason: 'arctic v2 stores passages bare');

        await storage.memorySettings.setEmbeddingEndpointModel(
          'nomic-embed-text-v1.5-F16:latest',
        );
        await emb.checkAvailability();
        await emb.embed('a memory');
        await emb.embedQuery('a search');
        expect(server.embedInputs.sublist(server.embedInputs.length - 2), [
          ['search_document: a memory'],
          ['search_query: a search'],
        ]);
      },
    );

    test('changing the model drops readiness until the new one answers, and '
        'marks the stored vectors as another model\'s', () async {
      final server = await EmbeddingProtocolServer.start(ollama: true);
      addTearDown(server.close);
      final storage = await _storage();
      final emb = await _onServer(storage, server);
      await emb.embed('first memory');
      expect(
        storage.memorySettings.embeddingIndexModel,
        'endpoint|$_snowflake',
      );
      expect(emb.choice.indexMatchesModel, isTrue);

      server.dims = 9;
      await storage.memorySettings.setEmbeddingEndpointModel(
        'nomic-embed-text-v1.5-F16:latest',
      );
      expect(emb.isAvailable, isFalse);
      expect(emb.choice.indexMatchesModel, isFalse);
      await emb.checkAvailability();
      expect(emb.isAvailable, isTrue);
      expect(emb.dimensions, 9);
    });

    test('a check asked for while one runs waits for its answer', () async {
      final server = await EmbeddingProtocolServer.start(ollama: true);
      final storage = await _storage();
      final s = storage.memorySettings;
      await s.setEmbeddingProvider(kEmbeddingEndpoint);
      await s.setEmbeddingEndpointUrl(server.url);
      await s.setEmbeddingEndpointModel(_snowflake);
      final emb = EmbeddingService(storage);
      server.answerDelay = const Duration(milliseconds: 300);

      final first = emb.checkAvailability();
      // "Check connection" right after saving the model.
      await emb.checkAvailability();
      expect(emb.isAvailable, isTrue);
      await first;
      expect(server.embedInputs, hasLength(1), reason: 'one check, shared');
    });

    test('an unreachable server says why and is not ready', () async {
      final server = await EmbeddingProtocolServer.start(ollama: false);
      final storage = await _storage();
      final emb = await _onServer(storage, server);
      expect(emb.isAvailable, isTrue);
      await server.close();
      await storage.memorySettings.setEmbeddingEndpointModel('BAAI/bge-m3');
      await emb.checkAvailability();
      expect(emb.isAvailable, isFalse);
      expect(emb.lastEngineError, isNotNull);
      expect(emb.statusSnapshot['configured'], isTrue);
    });
  });

  group('VectorRebuilder', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(sameIsolate: true));
    tearDown(() => db.close());

    Future<void> seed({int windows = 3}) async {
      final old = _bytes(const [0.5, 0.5, 0.5, 0.5]);
      for (var i = 0; i < windows; i++) {
        await db
            .into(db.messageEmbeddings)
            .insert(
              MessageEmbeddingsCompanion.insert(
                id: 'w${i.toString().padLeft(3, '0')}',
                sessionId: 's1',
                characterId: const Value('ada'),
                positionStart: i * 5,
                positionEnd: i * 5 + 4,
                content: 'Ada: window number $i on the porch',
                embedding: old,
                dimensions: 4,
              ),
            );
      }
      await db
          .into(db.dataBankEntries)
          .insert(
            DataBankEntriesCompanion.insert(
              id: 'd1',
              characterId: 'ada',
              title: 'Notes',
              content: 'Ada keeps bees behind the barn.',
              embedding: Value(old),
              dimensions: const Value(4),
            ),
          );
      await db
          .into(db.dataBankEntries)
          .insert(
            DataBankEntriesCompanion.insert(
              id: 'd2',
              characterId: 'ada',
              title: 'Never embedded',
              content: 'Ada hates thunder.',
            ),
          );
      await db
          .into(db.journalMemories)
          .insert(
            JournalMemoriesCompanion.insert(
              id: 'j1',
              sessionId: 's1',
              characterId: 'ada',
              content: 'You fixed my swing.',
              embedding: Value(old),
              dimensions: const Value(4),
            ),
          );
    }

    test('clear and re-vectorize replaces every vector with the current '
        'model\'s', () async {
      final server = await EmbeddingProtocolServer.start(ollama: true);
      addTearDown(server.close);
      final storage = await _storage();
      final emb = await _onServer(storage, server);
      await seed();
      final rebuilder = VectorRebuilder(embeddings: emb, db: () => db);
      expect((await rebuilder.refreshCounts()), (total: 6, missing: 1));

      expect(await rebuilder.rebuild(), isTrue, reason: '${rebuilder.error}');

      expect(await rebuilder.refreshCounts(), (total: 6, missing: 0));
      List<double> want(String text) =>
          EmbeddingProtocolServer.vectorFor(text, server.dims);
      for (final w in await db.select(db.messageEmbeddings).get()) {
        expect(
          _floats(w.embedding, w.dimensions),
          want(w.content),
          reason: w.id,
        );
      }
      for (final d in await db.select(db.dataBankEntries).get()) {
        expect(
          _floats(d.embedding, d.dimensions),
          want(d.content),
          reason: d.id,
        );
      }
      final card = await db.select(db.journalMemories).getSingle();
      expect(_floats(card.embedding, card.dimensions), want(card.content));
      expect(
        storage.memorySettings.embeddingIndexModel,
        'endpoint|$_snowflake',
      );
    });

    test(
      'a rebuild with no model to refill them keeps the old vectors',
      () async {
        final server = await EmbeddingProtocolServer.start(ollama: true);
        addTearDown(server.close);
        final storage = await _storage();
        final emb = await _onServer(storage, server);
        await seed();
        server.failing = true;
        // A new model must be checked first, and that check fails.
        await storage.memorySettings.setEmbeddingEndpointModel(
          'nomic-embed-text-v1.5-F16:latest',
        );
        final rebuilder = VectorRebuilder(embeddings: emb, db: () => db);

        expect(await rebuilder.rebuild(), isFalse);
        expect(rebuilder.error, isNotNull);
        expect(await rebuilder.refreshCounts(), (total: 6, missing: 1));
        final w = await db.select(db.messageEmbeddings).get();
        expect(w.every((r) => r.dimensions == 4), isTrue);
      },
    );

    test('a stopped rebuild resumes with Vectorize missing', () async {
      final server = await EmbeddingProtocolServer.start(ollama: false);
      addTearDown(server.close);
      final storage = await _storage();
      final emb = await _onServer(
        storage,
        server,
        model: 'text-embedding-3-small',
      );
      await seed(windows: 40);
      final rebuilder = VectorRebuilder(embeddings: emb, db: () => db);
      server.onEmbed = (inputs) {
        if (inputs.length > 1) rebuilder.cancel();
      };

      expect(await rebuilder.rebuild(), isFalse);
      final stopped = await rebuilder.refreshCounts();
      expect(stopped.missing, 43 - 16, reason: 'one batch of 16 was done');

      server.onEmbed = null;
      expect(await rebuilder.vectorizeMissing(), isTrue);
      expect(await rebuilder.refreshCounts(), (total: 43, missing: 0));
    });

    test('a second start while one runs is refused, so a double tap or two '
        'browsers rebuild once', () async {
      final server = await EmbeddingProtocolServer.start(ollama: true);
      final storage = await _storage();
      final emb = await _onServer(storage, server);
      await seed(windows: 20);
      final rebuilder = VectorRebuilder(embeddings: emb, db: () => db);
      final before = server.embedInputs.length;

      final first = rebuilder.rebuild();
      final second = rebuilder.vectorizeMissing();
      expect(await second, isFalse);
      expect(await first, isTrue, reason: '${rebuilder.error}');
      // 20 windows, 2 Data Bank entries and 1 card: two batches of 16 for
      // the windows, one each for the bank and the card.
      expect(server.embedInputs.length - before, 4);
    });
  });

  test('the web relay sets the server, key and model, lists models, checks '
      'and rebuilds, and never reads the key back', () async {
    final server = await EmbeddingProtocolServer.start(ollama: true);
    final storage = await _storage();
    final db = AppDatabase.forTesting(sameIsolate: true);
    final emb = EmbeddingService(storage);
    final chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    chat.setMemoryService(MemoryService(emb, storage, db));
    addTearDown(() => disposeChatThenCloseDb(chat, db));
    final relay = MemorySearchFacade(chat, storage);

    var snap = await relay.apply({
      'provider': 'endpoint',
      'endpointUrl': server.url,
      'apiKey': 'sk-porch',
    });
    expect(snap['hasApiKey'], isTrue);
    expect('$snap', isNot(contains('sk-porch')));
    expect((await relay.listModels({}))['models'], [
      'nomic-embed-text-v1.5-F16:latest',
      _snowflake,
    ]);
    expect(server.authorizations.last, 'Bearer sk-porch');
    expect(
      () => relay.apply({'provider': 'cloud'}),
      throwsA(isA<ArgumentError>()),
    );

    await relay.apply({'endpointModel': _snowflake});
    snap = await relay.check();
    expect((snap['status'] as Map)['available'], isTrue);
    expect((snap['status'] as Map)['dimensions'], server.dims);

    await db
        .into(db.journalMemories)
        .insert(
          JournalMemoriesCompanion.insert(
            id: 'j1',
            sessionId: 's1',
            characterId: 'ada',
            content: 'You fixed my swing.',
          ),
        );
    await relay.rebuild({'mode': 'all'});
    final rebuilder = chat.memoryService!.vectorRebuilder;
    while (rebuilder.running) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    snap = await relay.snapshot();
    expect(snap['rebuild'], containsPair('missing', 0));
    expect(snap['rebuild'], containsPair('stored', 1));
    expect(snap['indexModel'], 'endpoint|$_snowflake');
  });

  test('live: a real embedding server lists and embeds', () async {
    final url = Platform.environment['EMBEDDING_LIVE_URL'];
    if (url == null || url.isEmpty) {
      markTestSkipped('EMBEDDING_LIVE_URL is not set');
      return;
    }
    EmbeddingProtocolServer.allowRealHttp();
    final client = RemoteEmbeddingClient();
    final listed = await client.listModels(url);
    expect(listed.models, isNotEmpty);
    final model =
        Platform.environment['EMBEDDING_LIVE_MODEL'] ?? listed.models.first;
    final vectors = await client.embed(url, model: model, inputs: ['a', 'b']);
    expect(vectors, hasLength(2));
    expect(vectors.first, isNotEmpty);
    expect(vectors.first.length, vectors.last.length);
  }, tags: ['live']);
}
