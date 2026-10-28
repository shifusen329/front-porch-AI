// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// A real loopback HTTP server in the place of a self-hosted OpenAI-compatible
/// speech server (an omnivoice box on the LAN). It answers
/// `POST /v1/audio/speech` the way that server does, its error bodies copied
/// from it: no API key needed; any model but [model] is a 400 naming the
/// supported one; a voice it does not have is a 404; otherwise a real WAV
/// (16-bit mono silence). Every request is recorded.
class SpeechServer {
  SpeechServer._(this._server);

  final HttpServer _server;

  static const model = 'omnivoice';
  static const voices = {'aisha'};

  final List<({String? authorization, Map<String, dynamic> body})> requests =
      [];

  static Future<SpeechServer> start() async {
    // flutter_test swaps in a client that answers 400 to everything.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final host = SpeechServer._(server);
    server.listen(host._answer);
    addTearDown(() => server.close(force: true));
    return host;
  }

  /// What a user would type as the API base URL.
  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> _answer(HttpRequest request) async {
    final res = request.response;
    if (request.method != 'POST' || request.uri.path != '/v1/audio/speech') {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    final body =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
    requests.add((
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      body: body,
    ));
    final asked = body['model'];
    final voice = body['voice'];
    if (asked != model) {
      res.statusCode = HttpStatus.badRequest;
      res.headers.contentType = ContentType.json;
      res.write(
        jsonEncode({
          'detail': "Unsupported model '$asked'. Supported: $model.",
        }),
      );
    } else if (!voices.contains(voice)) {
      res.statusCode = HttpStatus.notFound;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'detail': "Voice '$voice' not found."}));
    } else {
      res.headers.contentType = ContentType('audio', 'wav');
      res.add(_silentWav(2400));
    }
    await res.close();
  }

  /// A PCM WAV of [samples] silent 16-bit mono samples at 24 kHz.
  static Uint8List _silentWav(int samples) {
    final data = samples * 2;
    final b = ByteData(44 + data);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + data, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, 24000, Endian.little);
    b.setUint32(28, 48000, Endian.little); // byte rate
    b.setUint16(32, 2, Endian.little); // block align
    b.setUint16(34, 16, Endian.little); // bits
    ascii(36, 'data');
    b.setUint32(40, data, Endian.little);
    return b.buffer.asUint8List();
  }
}
