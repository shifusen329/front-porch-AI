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

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/expression/expression.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'settings_base.dart';

/// Expression images / avatar classification + display settings.
///
/// Lifted Stage 7.
class ExpressionSettings with SettingsBase {
  ExpressionPromptRules _promptRules = ExpressionPromptRules();
  ExpressionPromptRules get expressionPromptRules => _promptRules;
  Future<void> setExpressionPromptRules(ExpressionPromptRules value) async {
    final copy = value.copy();
    final preferences = prefs;
    if (preferences == null ||
        !await preferences.setString(
          k('expression_prompt_rules'),
          jsonEncode(copy.toJson()),
        )) {
      throw StateError('Prompt defaults could not be saved.');
    }
    _promptRules = copy;
    notify();
  }

  bool _expressionEnabled = false;
  String _expressionClassificationMode = 'llm'; // 'llm', 'onnx', 'manual'
  String _expressionDisplayMode = 'sidebar'; // 'sidebar', 'background', 'both'
  bool _expressionRerollSame = false;
  String _expressionFallback = 'neutral'; // 'neutral', 'prime', 'none', 'emoji'
  bool _expressionEmojiBurst = false;
  double _expressionEmojiBurstSize = 28.0; // particle base font size (12–60)
  String _expressionOnnxModel = kDefaultExpressionModel;

  // Settings → Appearance → Visual novel mode: characters on stage, the
  // chat log in a panel over them. A chat can overrule it
  // (ChatThemeOverrides.visualNovel).
  bool _visualNovelMode = false;

  // Settings → Appearance: the chat background follows the place the Realism
  // Engine reports, when the character has a picture of it. On by default;
  // nothing changes until a character has scenes. A chat can overrule it
  // (ChatThemeOverrides.followScene).
  bool _sceneBackgrounds = true;

  /// Each downloaded classifier model's labels, by model id.
  Map<String, List<String>> _modelLabels = {};

  bool get expressionEnabled => _expressionEnabled;
  String get expressionClassificationMode => _expressionClassificationMode;
  String get expressionDisplayMode => _expressionDisplayMode;
  bool get expressionRerollSame => _expressionRerollSame;
  String get expressionFallback => _expressionFallback;
  bool get expressionEmojiBurst => _expressionEmojiBurst;
  double get expressionEmojiBurstSize => _expressionEmojiBurstSize;
  bool get visualNovelMode => _visualNovelMode;
  bool get sceneBackgrounds => _sceneBackgrounds;

  /// The Hugging Face model (`owner/name`) the ONNX classifier runs.
  String get expressionOnnxModel => _expressionOnnxModel;

  /// The labels the ONNX model in use gives, once it is on disk; null before.
  List<String>? get expressionModelLabels => _modelLabels[_expressionOnnxModel];

  /// Every label an expression image can carry: the standard set, then any
  /// the ONNX model in use adds (a fine-tune with labels of its own).
  List<String> get expressionLabels => [
    ...EmotionLabels.all,
    for (final label in expressionModelLabels ?? const <String>[])
      if (!EmotionLabels.all.contains(label)) label,
  ];

  void load() {
    _promptRules = ExpressionPromptRules();
    try {
      final stored = prefs?.getString(k('expression_prompt_rules'));
      if (stored != null) {
        _promptRules = ExpressionPromptRules.fromJson(jsonDecode(stored));
      }
    } catch (e) {
      debugPrint('[ExpressionPack] Invalid saved prompt rules: $e');
    }
    _expressionEnabled = prefs?.getBool(k('expression_enabled')) ?? false;
    _expressionClassificationMode =
        prefs?.getString(k('expression_classification_mode')) ?? 'llm';
    _expressionDisplayMode =
        prefs?.getString(k('expression_display_mode')) ?? 'sidebar';
    _expressionRerollSame =
        prefs?.getBool(k('expression_reroll_same')) ?? false;
    _visualNovelMode = prefs?.getBool(k('visual_novel_mode')) ?? false;
    _sceneBackgrounds = prefs?.getBool(k('scene_backgrounds')) ?? true;
    _expressionFallback =
        prefs?.getString(k('expression_fallback')) ?? 'neutral';
    _expressionEmojiBurst =
        prefs?.getBool(k('expression_emoji_burst')) ?? false;
    _expressionEmojiBurstSize =
        (prefs?.getDouble(k('expression_emoji_burst_size')) ?? 28.0).clamp(
          12.0,
          60.0,
        );
    _expressionOnnxModel =
        normalizeExpressionModel(
          prefs?.getString(k('expression_onnx_model')) ?? '',
        ) ??
        kDefaultExpressionModel;
    _modelLabels = {};
    try {
      final stored = prefs?.getString(k('expression_model_labels'));
      if (stored != null) {
        for (final MapEntry(:key, :value)
            in (jsonDecode(stored) as Map<String, dynamic>).entries) {
          _modelLabels[key] = [for (final l in value as List) '$l'];
        }
      }
    } catch (e) {
      debugPrint('[Expression] Invalid saved model labels: $e');
    }
  }

  Future<void> setExpressionEnabled(bool value) async {
    _expressionEnabled = value;
    await prefs?.setBool(k('expression_enabled'), value);
    notify();
  }

  Future<void> setExpressionClassificationMode(String value) async {
    _expressionClassificationMode = value;
    await prefs?.setString(k('expression_classification_mode'), value);
    notify();
  }

  Future<void> setExpressionDisplayMode(String value) async {
    _expressionDisplayMode = value;
    await prefs?.setString(k('expression_display_mode'), value);
    notify();
  }

  Future<void> setVisualNovelMode(bool value) async {
    _visualNovelMode = value;
    await prefs?.setBool(k('visual_novel_mode'), value);
    notify();
  }

  Future<void> setSceneBackgrounds(bool value) async {
    _sceneBackgrounds = value;
    await prefs?.setBool(k('scene_backgrounds'), value);
    notify();
  }

  Future<void> setExpressionRerollSame(bool value) async {
    _expressionRerollSame = value;
    await prefs?.setBool(k('expression_reroll_same'), value);
    notify();
  }

  Future<void> setExpressionFallback(String value) async {
    _expressionFallback = value;
    await prefs?.setString(k('expression_fallback'), value);
    notify();
  }

  Future<void> setExpressionEmojiBurst(bool value) async {
    _expressionEmojiBurst = value;
    await prefs?.setBool(k('expression_emoji_burst'), value);
    notify();
  }

  /// Sets the ONNX classifier model from an `owner/name` id or a
  /// huggingface.co link; empty goes back to the default. Throws
  /// [ArgumentError] for anything else.
  Future<void> setExpressionOnnxModel(String value) async {
    final model = value.trim().isEmpty
        ? kDefaultExpressionModel
        : normalizeExpressionModel(value);
    if (model == null) {
      throw ArgumentError.value(value, 'value', 'not a Hugging Face model id');
    }
    if (model == _expressionOnnxModel) return;
    _expressionOnnxModel = model;
    await prefs?.setString(k('expression_onnx_model'), model);
    notify();
  }

  /// Records the labels [model] gives, read from its config.json.
  Future<void> setExpressionModelLabels(
    String model,
    List<String> labels,
  ) async {
    if (listEquals(_modelLabels[model], labels)) return;
    _modelLabels = {..._modelLabels, model: List.unmodifiable(labels)};
    await prefs?.setString(
      k('expression_model_labels'),
      jsonEncode(_modelLabels),
    );
    notify();
  }

  Future<void> setExpressionEmojiBurstSize(double value) async {
    _expressionEmojiBurstSize = value.clamp(12.0, 60.0);
    await prefs?.setDouble(
      k('expression_emoji_burst_size'),
      _expressionEmojiBurstSize,
    );
    notify();
  }
}
