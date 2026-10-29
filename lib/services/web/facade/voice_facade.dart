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

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/tts/openai_voice_list.dart';

/// Audio bytes plus the MIME type to serve them with.
typedef AudioPayload = ({Uint8List bytes, String contentType});

/// Web adapter for voice: text-to-speech that synthesizes to a file (without
/// any host-side playback — the browser plays it on the *client* device) and
/// speech-to-text over an uploaded mic recording. Thin over [TtsService] and
/// [SttService]; all engine selection / model handling stays in those services.
class VoiceFacade {
  VoiceFacade(this._tts, this._stt, this._storage);

  final TtsService _tts;
  final SttService _stt;
  final StorageService _storage;

  /// Capability snapshot for the web client to decide which controls to show.
  Map<String, dynamic> status() => {
    'ttsEnabled': _storage.ttsSettings.ttsEnabled,
    'ttsEngine': _storage.ttsSettings.ttsEngine,
    'sttEnabled': _storage.sttSettings.sttEnabled,
    'sttAvailable': _stt.isAvailable,
    // Additive (2026-08-14) for the web character editor's per-character
    // voice picker — an assigned voice overrides the global one, so the
    // browser needs both the choices and the global's name to label
    // "use the global voice". Older clients ignore the extra keys.
    'globalVoice': _storage.ttsSettings.ttsVoiceModel,
    // Additive (2026-10-28): the user's own voice and the narrator's ('' is
    // the global voice), and whether the user's messages are read as sent.
    'userVoice': _storage.ttsSettings.ttsUserVoice,
    'narratorVoice': _storage.ttsSettings.ttsNarratorVoice,
    'ttsAutoPlayUser': _storage.ttsSettings.ttsAutoPlayUser,
    'voices': _tts.activeVoices
        .map(
          (v) => {
            'id': v.id,
            'name': v.name,
            'gender': v.gender,
            'language': v.language,
          },
        )
        .toList(),
    // Additive (2026-10-27): an OpenAI-compatible server can publish its
    // own voices, and the web Settings card offers to read them again.
    'listsVoices':
        _storage.ttsSettings.ttsEngine == 'openai' &&
        isCustomOpenAiTtsUrl(_storage.ttsSettings.openaiTtsBaseUrl),
    // Additive (2026-10-27): the Local ONNX expression classifier's model,
    // and the labels it gives once downloaded (null before).
    'expressionEnabled': _storage.expressionSettings.expressionEnabled,
    'expressionMode': _storage.expressionSettings.expressionClassificationMode,
    'expressionModel': _storage.expressionSettings.expressionOnnxModel,
    'expressionModelDefault': kDefaultExpressionModel,
    'expressionModelLabels': _storage.expressionSettings.expressionModelLabels,
  };

  /// Reads the voices the OpenAI-compatible server publishes, as the
  /// desktop's Refresh does. `found` is how many it sent, or null for none.
  Future<Map<String, dynamic>> listVoices() async {
    final voices = await _tts.listEndpointVoices();
    return {...status(), 'found': voices?.length};
  }

  /// Persist the Voice & Media enable flags from the web Settings page so a
  /// remote/phone user can turn TTS/STT on without opening the desktop tab,
  /// Speak my messages with the user's and narrator's voices, and the
  /// expression classifier's model (`expressionModel`: an
  /// `owner/name` id, a huggingface.co link, or '' for the default). Throws
  /// [ArgumentError] when that names no model.
  Future<Map<String, dynamic>> apply(Map<String, dynamic> body) async {
    // First, so a model that is refused leaves the flags untouched too.
    final model = body['expressionModel'];
    if (model is String) {
      await _storage.expressionSettings.setExpressionOnnxModel(model);
    }
    final tts = body['ttsEnabled'];
    if (tts is bool) await _storage.ttsSettings.setTtsEnabled(tts);
    final speakMine = body['ttsAutoPlayUser'];
    if (speakMine is bool) {
      await _storage.ttsSettings.setTtsAutoPlayUser(speakMine);
    }
    final userVoice = body['userVoice'];
    if (userVoice is String) {
      await _storage.ttsSettings.setTtsUserVoice(userVoice.trim());
    }
    final narratorVoice = body['narratorVoice'];
    if (narratorVoice is String) {
      await _storage.ttsSettings.setTtsNarratorVoice(narratorVoice.trim());
    }
    final stt = body['sttEnabled'];
    if (stt is bool) await _storage.sttSettings.setSttEnabled(stt);
    return status();
  }

  /// Synthesize [text] to audio bytes (no host playback). Returns the bytes plus
  /// their MIME type, or null when TTS is off / produced nothing.
  Future<AudioPayload?> speak(String text, {String? voiceKey}) async {
    if (!_storage.ttsSettings.ttsEnabled || text.trim().isEmpty) return null;
    final file = await _tts.generateAudioFile(text, voiceKey: voiceKey);
    if (file == null || !file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    // ElevenLabs returns mp3; every other engine returns a (merged) WAV.
    final contentType = p.extension(file.path).toLowerCase() == '.mp3'
        ? 'audio/mpeg'
        : 'audio/wav';
    return (bytes: bytes, contentType: contentType);
  }

  /// Why the last [speak] had no audio, when the engine said (an
  /// OpenAI-compatible server's own reason).
  String? get lastSpeakFailure => _tts.lastEngineFailure;

  /// Transcribe uploaded mic audio recorded on the client device. [bytes] is the
  /// raw recording; [ext] is its container extension (e.g. `webm`, `wav`) so the
  /// temp file Whisper reads has a sensible suffix. Returns the text or null.
  Future<String?> transcribe(List<int> bytes, {String? ext}) async {
    if (!_stt.isAvailable || bytes.isEmpty) return null;
    final safeExt = (ext == null || ext.isEmpty)
        ? 'webm'
        : ext.replaceAll(RegExp(r'[^a-z0-9]'), '').toLowerCase();
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'fpai_web_stt_${bytes.length}_${bytes.hashCode}.$safeExt',
      ),
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      return await _stt.transcribeAudioFile(tmp.path);
    } finally {
      if (tmp.existsSync()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }
}
