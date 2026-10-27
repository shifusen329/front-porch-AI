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
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/tts/openai_voice_list.dart';
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';

/// OpenAI TTS engine — cloud-based premium quality TTS.
///
/// Uses the OpenAI Audio API to generate speech.
/// Requires an API key.
class OpenAiTtsEngine implements TtsEngine {
  String apiKey;
  String model;
  String baseUrl;

  OpenAiTtsEngine({
    this.apiKey = '',
    this.model = 'tts-1',
    this.baseUrl = kOpenAiTtsBaseUrl,
  });
  static int _fileCounter = 0;

  /// The voices a custom endpoint published (see [fetchVoices]) and the
  /// endpoint they belong to. Another endpoint gets the built-in names.
  List<TtsVoiceInfo> _listed = const [];
  String _listedFor = '';

  /// The saved list [restoreListedVoices] last read, so an unchanged one is
  /// not decoded again on every use.
  String _restoredFrom = '';

  /// The published voices in their saved form; '' when there are none.
  String get savedVoiceList =>
      _listed.isEmpty ? '' : encodeOpenAiVoiceList(_listedFor, _listed);

  /// Takes back a list saved from [savedVoiceList].
  void restoreListedVoices(String saved) {
    if (saved == _restoredFrom) return;
    _restoredFrom = saved;
    final decoded = decodeOpenAiVoiceList(saved);
    _listed = decoded?.voices ?? const [];
    _listedFor = decoded?.url ?? '';
  }

  /// Asks a custom endpoint for its voices (`GET {baseUrl}/audio/voices`).
  /// Returns them, or null when [baseUrl] is OpenAI's own, the endpoint
  /// publishes no list, or it cannot be reached. The last good list stays in
  /// use on a failure.
  Future<List<TtsVoiceInfo>?> fetchVoices() async {
    final url = baseUrl;
    if (!isCustomOpenAiTtsUrl(url)) return null;
    final uri = openAiVoiceListUri(url);
    try {
      final response = await http
          .get(
            uri,
            headers: {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        print('OpenAI TTS voices: ${response.statusCode} from $uri');
        return null;
      }
      final voices = parseOpenAiVoiceList(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      if (voices.isEmpty) {
        print('OpenAI TTS voices: $uri listed no voices');
        return null;
      }
      _listed = voices;
      _listedFor = url;
      _restoredFrom = savedVoiceList;
      return voices;
    } catch (e) {
      print('OpenAI TTS voices error from $uri: $e');
      return null;
    }
  }

  @override
  String get engineName => 'OpenAI TTS';

  @override
  String get engineId => 'openai';

  @override
  Future<bool> get isAvailable async => apiKey.isNotEmpty;

  @override
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async =>
      true;

  @override
  Future<File?> generateAudio(
    String text,
    String voice,
    double speed, {
    void Function(double progress)? onProgress,
  }) async {
    if (apiKey.isEmpty) {
      print('OpenAI TTS: no API key configured');
      return null;
    }

    try {
      // Strip trailing slash from baseUrl to avoid double-slash
      final url = baseUrl.endsWith('/')
          ? '${baseUrl}audio/speech'
          : '$baseUrl/audio/speech';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body:
            '{"model":"$model","input":${_jsonEscape(text)},"voice":"$voice","response_format":"wav","speed":$speed}',
      );

      if (response.statusCode != 200) {
        print('OpenAI TTS error: ${response.statusCode} ${response.body}');
        return null;
      }

      // Write response body (WAV audio) to temp file
      final tempDir = Directory.systemTemp;
      _fileCounter++;
      final outputFile = File(
        p.join(
          tempDir.path,
          'openai_tts_${DateTime.now().millisecondsSinceEpoch}_$_fileCounter.wav',
        ),
      );
      await outputFile.writeAsBytes(response.bodyBytes);

      return outputFile;
    } catch (e) {
      print('OpenAI TTS error: $e');
      return null;
    }
  }

  /// JSON-escape a string value.
  String _jsonEscape(String text) {
    return '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"';
  }

  /// OpenAI's own endpoint gets its documented voices. Any other server gets
  /// only what it published: it may not know OpenAI's names at all.
  @override
  List<TtsVoiceInfo> get availableVoices {
    if (!isCustomOpenAiTtsUrl(baseUrl)) return _voices;
    return sameOpenAiEndpoint(_listedFor, baseUrl) ? _listed : const [];
  }

  static const _voices = [
    TtsVoiceInfo(
      id: 'alloy',
      name: 'Alloy',
      gender: 'Neutral',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'ash',
      name: 'Ash',
      gender: 'Male',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'ballad',
      name: 'Ballad',
      gender: 'Male',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'coral',
      name: 'Coral',
      gender: 'Female',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'echo',
      name: 'Echo',
      gender: 'Male',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'fable',
      name: 'Fable',
      gender: 'Male',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'onyx',
      name: 'Onyx',
      gender: 'Male',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'nova',
      name: 'Nova',
      gender: 'Female',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'sage',
      name: 'Sage',
      gender: 'Female',
      language: 'Multilingual',
      engine: 'openai',
    ),
    TtsVoiceInfo(
      id: 'shimmer',
      name: 'Shimmer',
      gender: 'Female',
      language: 'Multilingual',
      engine: 'openai',
    ),
  ];
}
