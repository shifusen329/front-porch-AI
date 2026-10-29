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

// With Expression Images on, the Realism Engine's emotion judge must choose
// one expression label. A fine-tuned expression classifier adds labels of
// its own (ExpressionSettings.expressionLabels); the judge is offered them
// too, on the separate-call path and on one-shot alike, so LLM mode can show
// the pictures tagged with them. A real ChatService against the loopback
// backend the other chat tests use.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _modelOwn = ['cowgirl', 'missionary'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'expression_enabled': true,
    });
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(
      replyPieces: ['She leans on the porch rail ', 'and smiles.'],
    );
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
    // What reading the installed model's config.json records.
    final expression = storage.expressionSettings;
    await expression.setExpressionModelLabels(expression.expressionOnnxModel, [
      'joy',
      ..._modelOwn,
    ]);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Label Tester',
        description: 'Exists only inside the expression-label test.',
        firstMessage: 'Welcome to the porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-labels',
    );
    await _drain();
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  for (final mode in [OneShotMode.off, OneShotMode.on]) {
    test("${mode.name}: the emotion judge is offered the classifier model's "
        'own labels', () async {
      await storage.realismSettings.setOneShotMode(mode);
      await chat.sendMessage('I bring you a cup of tea.');
      await _drain();

      final constrained = backend.evalBodies.where(
        (b) => b.contains('EXACTLY ONE of these labels'),
      );
      expect(constrained, isNotEmpty, reason: 'the emotion judge ran');
      for (final body in constrained) {
        for (final label in [..._modelOwn, 'affection']) {
          expect(body, contains(label), reason: '$label offered');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test("the fallback call's tool offers the labels it is given", () {
    final tool = expressionEvalTools(['joy', ..._modelOwn]).single;
    final label =
        (tool['function'] as Map)['parameters']['properties']['label'] as Map;
    expect(label['enum'], ['joy', ..._modelOwn]);
    expect(
      (kExpressionEvalTools.single['function']
          as Map)['parameters']['properties']['label']['enum'],
      isNot(contains('cowgirl')),
    );
  });
}
