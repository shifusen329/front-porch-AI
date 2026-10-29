// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Local ONNX expression classifier runs the Hugging Face model chosen in
// Settings. A model downloads into a folder of its own, its labels come from
// its own config.json (a fine-tune can add labels past go-emotions' 28), those
// labels reach the chat and the image pickers, and each model's labels are
// kept for when it is chosen again.
//
// Downloads go over real HTTP to a loopback server laid out like a Hugging
// Face repo, serving the real config.json of a fine-tune with ten extra labels
// (test/fixtures/emotion_classifier/custom_labels_config.json). The weights
// are never run here; the real model is classified in
// test/services/expression/onnx_emotion_e2e_test.dart.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/expression_classifier/expression_classifier.dart';
import 'package:front_porch_ai/services/expression/expression.dart';
import 'package:front_porch_ai/services/services.dart';

const _model = 'Shifusen/distilbert-go_emotions-nsfw';
const _config = 'test/fixtures/emotion_classifier/custom_labels_config.json';
const _vocab = 'test/fixtures/emotion_classifier/vocab.txt';

/// A loopback server laid out like huggingface.co: `/<repo>/resolve/main/…`.
class _Hub {
  _Hub._(this._server);
  final HttpServer _server;
  final Map<String, List<int>> files = {};
  final List<String> asked = [];

  static Future<_Hub> start() async {
    final saved = HttpOverrides.current;
    HttpOverrides.global = null; // flutter_test answers 400 to everything
    addTearDown(() => HttpOverrides.global = saved);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hub = _Hub._(server);
    server.listen((request) async {
      hub.asked.add(request.uri.path);
      final body = hub.files[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.contentLength = body.length;
        request.response.add(body);
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    return hub;
  }

  String get url => 'http://127.0.0.1:${_server.port}';

  /// Serves [repo] with the files a classifier download fetches. The
  /// weights are filler bytes past the downloader's 1 MB floor.
  void serveRepo(String repo) {
    final base = '/$repo/resolve/main';
    files['$base/vocab.txt'] = File(_vocab).readAsBytesSync();
    files['$base/config.json'] = File(_config).readAsBytesSync();
    files['$base/onnx/model.onnx'] = Uint8List(1024 * 1024 + 1);
  }
}

Future<StorageService> _storage() async {
  final docs = Directory.systemTemp.createTempSync('fpai_expr_model_');
  addTearDown(() => docs.deleteSync(recursive: true));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? docs.path
            : null,
      );
  final storage = StorageService();
  await storage.initialized;
  return storage;
}

/// Answers every classify with [label], to pin what the chat does with it.
class _FixedClassifier extends ExpressionClassifierService {
  _FixedClassifier(super.storage, this.label);
  final String label;

  @override
  Future<void> ensureInitialized({
    required String Function() getCurrentEmotion,
    required Future<String> Function(String unknownEmotion) reclassify,
  }) async {}

  @override
  Future<EmotionResult?> classify(String text) async =>
      EmotionResult(emotion: label, confidence: 0.9);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a chosen model downloads into its own folder, and its own labels '
    'reach the image pickers and come back when it is chosen again',
    () async {
      final hub = await _Hub.start();
      hub.serveRepo(_model);
      final storage = await _storage();
      final settings = storage.expressionSettings;
      await settings.setExpressionOnnxModel(
        'https://huggingface.co/$_model/tree/main',
      );
      expect(settings.expressionOnnxModel, _model);
      final service = ExpressionClassifierService(storage, hubBaseUrl: hub.url);
      expect(service.isModelCached, isFalse);

      expect(await service.triggerOnnxDownload(), isTrue);

      expect(hub.asked, [
        '/$_model/resolve/main/vocab.txt',
        '/$_model/resolve/main/config.json',
        '/$_model/resolve/main/onnx/model.onnx',
      ]);
      final folder = p.join(
        storage.rootPath!,
        'models',
        'emotion_classifiers',
        'Shifusen--distilbert-go_emotions-nsfw',
      );
      for (final name in ['model.onnx', 'vocab.txt', 'config.json']) {
        expect(File(p.join(folder, name)).existsSync(), isTrue, reason: name);
      }
      expect(service.modelReady, isTrue);
      expect(service.isModelCached, isTrue);
      expect(settings.expressionModelLabels, hasLength(38));
      expect(settings.expressionLabels, containsAll(['joy', 'cowgirl', 'bj']));

      await settings.setExpressionOnnxModel('');
      expect(settings.expressionOnnxModel, kDefaultExpressionModel);
      expect(service.modelReady, isFalse);
      expect(settings.expressionLabels, isNot(contains('cowgirl')));

      await settings.setExpressionOnnxModel(_model);
      expect(settings.expressionLabels, contains('cowgirl'));

      // And after a restart.
      final restarted = StorageService();
      await restarted.initialized;
      expect(restarted.expressionSettings.expressionOnnxModel, _model);
      expect(
        restarted.expressionSettings.expressionLabels,
        contains('cowgirl'),
      );
    },
  );

  test('a model already on disk names its labels when the classifier starts, '
      'with no download', () async {
    final hub = await _Hub.start();
    final storage = await _storage();
    await storage.expressionSettings.setExpressionOnnxModel(_model);
    await storage.expressionSettings.setExpressionClassificationMode('onnx');
    final files = ExpressionModelFiles(storage.rootPath!, _model);
    Directory(files.downloadDir).createSync(recursive: true);
    File(_config).copySync(files.config);
    File(_vocab).copySync(files.vocab);
    File(files.model).writeAsBytesSync(Uint8List(16));

    await ExpressionClassifierService(
      storage,
      hubBaseUrl: hub.url,
    ).ensureInitialized(
      getCurrentEmotion: () => 'neutral',
      reclassify: (_) async => 'neutral',
    );
    for (var i = 0; i < 50; i++) {
      if (storage.expressionSettings.expressionModelLabels != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(storage.expressionSettings.expressionLabels, contains('paizuri'));
    expect(hub.asked, isEmpty);
  });

  test('outputs past go-emotions\' 28 are named by the model\'s config, not '
      'read as neutral', () {
    final names = OnnxEmotionEngine.labelsFromConfig(
      File(_config).readAsStringSync(),
    )!;
    final logits = List<double>.filled(38, 0)..[29] = 9;

    expect(
      OnnxEmotionEngine.topScores(logits, names: names).first.$1,
      'cowgirl',
    );
    expect(
      OnnxEmotionEngine.labelsFromConfig('{"id2label": {"1": "a"}}'),
      isNull,
    );
  });

  test('the chat keeps a label the model adds, so images tagged with it '
      'show', () async {
    final storage = await _storage();
    String? notified;
    late final OnnxExpressionClassifier onnx;
    onnx = OnnxExpressionClassifier(
      onNotify: () => notified = 'yes',
      getStorageService: () => storage,
      getIsGenerating: () => false,
      getCharacterEmotion: () => 'aroused',
      getMessages: () => [
        ChatMessage(text: 'She climbs on top.', sender: 'Nia', isUser: false),
      ],
      getRealismEvalCancelled: () => false,
      onHandleRealismEvalCancelledDuringOnnx: () async {},
    )..setService(_FixedClassifier(storage, 'cowgirl'));

    await onnx.classify('aroused');

    expect(notified, 'yes');
    expect(
      onnx.currentLabel(
        'aroused',
        messageCount: 1,
        lastAiMsgText: 'She climbs on top.',
      ),
      'cowgirl',
    );
  });

  // The real fine-tune, end to end through the classifier service. Needs its
  // three files in one folder and the onnxruntime library on the search path:
  //   FP_EMOTION_TEST_MODEL_DIR=/path/with/model.onnx+vocab.txt+config.json
  final realDir = Platform.environment['FP_EMOTION_TEST_MODEL_DIR'];
  test(
    'the real fine-tune, chosen in Settings, gives its own labels',
    () async {
      final storage = await _storage();
      await storage.expressionSettings.setExpressionClassificationMode('onnx');
      await storage.expressionSettings.setExpressionOnnxModel(_model);
      final files = ExpressionModelFiles(storage.rootPath!, _model);
      Directory(files.downloadDir).createSync(recursive: true);
      for (final name in ['model.onnx', 'vocab.txt', 'config.json']) {
        File(p.join(realDir!, name)).copySync(p.join(files.downloadDir, name));
      }
      final service = ExpressionClassifierService(storage);
      await service.ensureInitialized(
        getCurrentEmotion: () => 'neutral',
        reclassify: (_) async => 'neutral',
      );

      Future<String> label(String text) async {
        final result = (await service.classify(text))!;
        final top = [
          for (final c in result.topCandidates) '${c.emotion} ${c.confidence}',
        ];
        // ignore: avoid_print
        print('$text -> $top');
        return result.emotion;
      }

      expect(
        await label('Thank you so much, that means the world to me.'),
        'gratitude',
      );
      final own = storage.expressionSettings.expressionLabels.skip(30);
      expect(
        await label('She climbs on top of him and rides him, facing him.'),
        isIn(own),
      );
    },
    skip: realDir == null ? 'FP_EMOTION_TEST_MODEL_DIR not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a model id that names no repo is refused and leaves the model',
    () async {
      final storage = await _storage();
      final settings = storage.expressionSettings;

      expect(
        () => settings.setExpressionOnnxModel('not a model'),
        throwsArgumentError,
      );
      expect(settings.expressionOnnxModel, kDefaultExpressionModel);
      expect(
        normalizeExpressionModel('https://huggingface.co/Shifusen'),
        isNull,
      );
    },
  );
  test('naming a model learns its own labels from config.json alone, in LLM '
      'mode, with no weights downloaded', () async {
    final hub = await _Hub.start();
    hub.serveRepo(_model);
    final storage = await _storage();
    final settings = storage.expressionSettings;
    expect(settings.expressionClassificationMode, 'llm');
    final service = ExpressionClassifierService(storage, hubBaseUrl: hub.url);
    service.learnModelLabels(); // the default model adds no labels
    expect(hub.asked, isEmpty);

    await settings.setExpressionOnnxModel(_model);
    service.learnModelLabels();
    for (var i = 0; i < 50; i++) {
      if (settings.expressionModelLabels != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(settings.expressionLabels, containsAll(['cowgirl', 'bj', 'joy']));
    expect(hub.asked, ['/$_model/resolve/main/config.json']);
    expect(service.isModelCached, isFalse, reason: 'the weights stay put');
    service.learnModelLabels();
    expect(hub.asked, hasLength(1), reason: 'once per model');
  });
}
