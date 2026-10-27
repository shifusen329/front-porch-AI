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

import 'package:front_porch_ai/services/tts_voice_info.dart';

/// Voice lists published by OpenAI-compatible text-to-speech servers.
///
/// OpenAI documents its voices but serves no list. Servers that copy its API
/// often add `GET {base}/audio/voices`, in one of these shapes:
///
///     {"object": "list", "data": [{"voice_id": "willa", "name": "Willa"}]}
///     {"voices": ["af_bella", "am_adam"]}
///     [{"id": "willa", "name": "Willa", "gender": "female"}]
const kOpenAiTtsBaseUrl = 'https://api.openai.com/v1';

/// Whether [baseUrl] names a server other than OpenAI's own. Only those can
/// publish a voice list.
bool isCustomOpenAiTtsUrl(String baseUrl) {
  final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
  return host.isNotEmpty && host != 'api.openai.com';
}

/// Whether [a] and [b] name the same endpoint, ignoring a trailing slash.
bool sameOpenAiEndpoint(String a, String b) => _endpoint(a) == _endpoint(b);

String _endpoint(String url) => url.trim().replaceFirst(RegExp(r'/+$'), '');

/// Where [baseUrl] publishes its voice list.
Uri openAiVoiceListUri(String baseUrl) =>
    Uri.parse('${_endpoint(baseUrl)}/audio/voices');

/// Reads a voice list body in any of the shapes above. Entries without an id
/// are dropped, and so are repeats. A gender the server does not give stays
/// '' rather than being guessed.
List<TtsVoiceInfo> parseOpenAiVoiceList(Object? body) {
  final entries = switch (body) {
    {'data': final List<Object?> list} => list,
    {'voices': final List<Object?> list} => list,
    final List<Object?> list => list,
    _ => const <Object?>[],
  };
  final seen = <String>{};
  return [
    for (final entry in entries)
      if (_voiceFrom(entry) case final voice? when seen.add(voice.id)) voice,
  ];
}

TtsVoiceInfo? _voiceFrom(Object? entry) {
  final (id, name, gender) = switch (entry) {
    final String s => (s, s, ''),
    final Map<Object?, Object?> m => (
      '${m['voice_id'] ?? m['id'] ?? m['name'] ?? ''}',
      '${m['name'] ?? m['voice_id'] ?? m['id'] ?? ''}',
      '${m['gender'] ?? ''}',
    ),
    _ => ('', '', ''),
  };
  if (id.trim().isEmpty) return null;
  final g = gender.trim().toLowerCase();
  return TtsVoiceInfo(
    id: id.trim(),
    name: name.trim(),
    gender: g.startsWith('f')
        ? 'Female'
        : g.startsWith('m')
        ? 'Male'
        : '',
    language: '',
    engine: 'openai',
  );
}

/// The saved form of [voices], tagged with the endpoint that published them.
String encodeOpenAiVoiceList(String baseUrl, List<TtsVoiceInfo> voices) =>
    jsonEncode({
      'url': _endpoint(baseUrl),
      'voices': [
        for (final v in voices)
          {'id': v.id, 'name': v.name, 'gender': v.gender},
      ],
    });

/// Reads back what [encodeOpenAiVoiceList] wrote; null when [saved] is empty
/// or unreadable.
({String url, List<TtsVoiceInfo> voices})? decodeOpenAiVoiceList(String saved) {
  if (saved.isEmpty) return null;
  try {
    final body = jsonDecode(saved);
    if (body is! Map || body['url'] is! String) return null;
    final voices = parseOpenAiVoiceList(body);
    return voices.isEmpty ? null : (url: body['url'] as String, voices: voices);
  } on FormatException catch (e) {
    print('OpenAI TTS: saved voice list unreadable: $e');
    return null;
  }
}
