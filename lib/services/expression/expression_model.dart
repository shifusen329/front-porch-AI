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

import 'package:path/path.dart' as p;

/// The Hugging Face model the ONNX expression classifier runs when none is
/// chosen: go-emotions DistilBERT, 28 labels.
const kDefaultExpressionModel =
    'Cohee/distilbert-base-uncased-go-emotions-onnx';

const kHuggingFaceBase = 'https://huggingface.co';

final _repoId = RegExp(r'^[A-Za-z0-9][\w.-]*/[A-Za-z0-9][\w.-]*$');

/// The `owner/name` repo id in [input] — typed as is, or a pasted
/// huggingface.co link — or null when it names no repo.
String? normalizeExpressionModel(String input) {
  var s = input.trim();
  final link = RegExp(
    r'^https?://(?:www\.)?huggingface\.co/',
  ).firstMatch(s.toLowerCase());
  if (link != null) {
    final parts = s.substring(link.end).split('/');
    if (parts.length < 2) return null;
    s = '${parts[0]}/${parts[1]}';
  }
  return _repoId.hasMatch(s) ? s : null;
}

/// Where a classifier model's files live under the library root.
///
/// The default model keeps the folder it always had: files in `native/`,
/// or the Hugging Face hub cache the retired Python sidecar built. Any other
/// model gets a folder of its own, so two models never share a file.
class ExpressionModelFiles {
  ExpressionModelFiles(this.rootPath, this.repoId);

  final String rootPath;
  final String repoId;

  bool get isDefault => repoId == kDefaultExpressionModel;

  /// Searched for the default model's legacy hub cache.
  String get cacheDir => isDefault
      ? p.join(rootPath, 'models', 'emotion_classifier')
      : p.join(
          rootPath,
          'models',
          'emotion_classifiers',
          repoId.replaceAll('/', '--'),
        );

  /// Where a download writes model.onnx, vocab.txt and config.json.
  String get downloadDir => isDefault ? p.join(cacheDir, 'native') : cacheDir;

  String get model => p.join(downloadDir, 'model.onnx');
  String get vocab => p.join(downloadDir, 'vocab.txt');
  String get config => p.join(downloadDir, 'config.json');
}
