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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/embedding/embedding_model_choice.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory/memory.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/rag_engine_card.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'vector_rebuild_card.dart';

/// Settings → Backend → Memory search: which embedding model turns saved
/// memories into vectors — a model server (Ollama or OpenAI-compatible,
/// with its embedding models in a dropdown) or the on-device model — plus
/// the engine's status and Clear and re-vectorize.
class MemorySearchSection extends StatelessWidget {
  const MemorySearchSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Tab tests pump without the memory services; this package's Provider
    // has no maybeOf.
    final EmbeddingService emb;
    try {
      emb = Provider.of<EmbeddingService>(context);
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    VectorRebuilder? rebuilder;
    try {
      rebuilder = Provider.of<ChatService>(
        context,
        listen: false,
      ).memoryService?.vectorRebuilder;
    } on ProviderNotFoundException {
      rebuilder = null;
    }
    return _MemorySearchBody(embeddings: emb, rebuilder: rebuilder);
  }
}

class _MemorySearchBody extends StatefulWidget {
  const _MemorySearchBody({required this.embeddings, this.rebuilder});

  final EmbeddingService embeddings;
  final VectorRebuilder? rebuilder;

  @override
  State<_MemorySearchBody> createState() => _MemorySearchBodyState();
}

class _MemorySearchBodyState extends State<_MemorySearchBody> {
  late final TextEditingController _url;
  final _key = TextEditingController();
  List<String> _models = const [];
  bool _listing = false;
  String? _listError;

  @override
  void initState() {
    super.initState();
    final emb = widget.embeddings;
    _url = TextEditingController(text: emb.endpointUrl);
    if (emb.usesEndpoint && emb.endpointUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadModels();
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  MemorySettings get _settings => context.read<StorageService>().memorySettings;

  Future<void> _pinEndpoint() async {
    if (_settings.embeddingProvider != kEmbeddingEndpoint) {
      await _settings.setEmbeddingProvider(kEmbeddingEndpoint);
    }
  }

  /// Saves the URL (and a typed key) and reads the server's models.
  Future<void> _saveServer() async {
    final storage = context.read<StorageService>();
    final url = _url.text.trim();
    await _pinEndpoint();
    if (url != _settings.embeddingEndpointUrl) {
      await _settings.setEmbeddingEndpointUrl(url);
    }
    final key = _key.text.trim();
    if (key.isNotEmpty && url.isNotEmpty) {
      await storage.backendSettings.setRemoteApiKeyFor(url, key);
      _key.clear();
    }
    await _loadModels();
  }

  Future<void> _loadModels() async {
    final emb = widget.embeddings;
    final url = _url.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _listing = true;
      _listError = null;
    });
    try {
      final models = await emb.listEndpointModels(url);
      if (!mounted) return;
      setState(() {
        _models = models;
        _listError = models.isEmpty ? 'This server lists no models.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _models = const [];
        _listError = 'Could not list models: $e';
      });
    } finally {
      if (mounted) setState(() => _listing = false);
    }
  }

  Future<void> _pickModel(String? model) async {
    if (model == null) return;
    final emb = widget.embeddings;
    await _pinEndpoint();
    await _settings.setEmbeddingEndpointModel(model);
    await emb.checkAvailability();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final emb = widget.embeddings;
    final rebuilder = widget.rebuilder;
    final muted = AppColors.textTertiary(context);
    final endpoint = emb.usesEndpoint;
    final hasKey = storage.backendSettings
        .remoteApiKeyFor(_url.text.trim())
        .isNotEmpty;
    final current = emb.endpointModel;
    final choices = [
      if (current.isNotEmpty && !_models.contains(current)) current,
      ..._models,
    ];

    return Column(
      key: const Key('memory-search-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Divider(color: AppColors.borderOf(context)),
        const SizedBox(height: 12),
        const SectionHeader('Memory search'),
        const SizedBox(height: 4),
        Text(
          'The embedding model that turns saved memories, Journal cards and '
          'Data Bank entries into vectors, so each reply can find the old '
          'moments that matter. Used when Memory (RAG) is on.',
          style: TextStyle(fontSize: 12, height: 1.4, color: muted),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: kEmbeddingEndpoint,
              icon: Icon(Icons.dns_outlined, size: 16),
              label: Text('Model server'),
            ),
            ButtonSegment(
              value: kEmbeddingOnDevice,
              icon: Icon(Icons.memory, size: 16),
              label: Text('On this device'),
            ),
          ],
          selected: {endpoint ? kEmbeddingEndpoint : kEmbeddingOnDevice},
          onSelectionChanged: (s) => _settings.setEmbeddingProvider(s.first),
        ),
        const SizedBox(height: 12),
        if (endpoint) ...[
          TextField(
            key: const Key('embedding-url-field'),
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText:
                  'http://192.168.0.100:11434 or https://api.openai.com/v1',
              helperText: 'Ollama, or any OpenAI-compatible server.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _saveServer(),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('embedding-key-field'),
            controller: _key,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'API key (optional)',
              hintText: hasKey
                  ? 'Saved — type a new one to replace it'
                  : 'Not needed for Ollama on your own network',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _saveServer(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Embedding model',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('embedding-model-dropdown'),
                      value: current.isEmpty ? null : current,
                      isExpanded: true,
                      hint: Text(
                        choices.isEmpty
                            ? 'Load the server\'s models first'
                            : 'Pick one',
                      ),
                      items: [
                        for (final m in choices)
                          DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: choices.isEmpty ? null : _pickModel,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Save the server and load its models',
                child: OutlinedButton.icon(
                  key: const Key('embedding-load-models'),
                  onPressed: _listing ? null : _saveServer,
                  icon: _listing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: const Text('Load models'),
                ),
              ),
            ],
          ),
          if (_listError != null) ...[
            const SizedBox(height: 6),
            Text(
              _listError!,
              style: TextStyle(
                fontSize: 12,
                color: StatusColors.dangerOf(context),
              ),
            ),
          ],
        ] else
          Text(
            '${EmbeddingModelChoice.onDeviceModel}, a one-time ~550 MB download '
            'that runs on this device. Nothing leaves it.',
            style: TextStyle(fontSize: 12, height: 1.4, color: muted),
          ),
        const SizedBox(height: 12),
        RagEngineCard(accent: AppColors.porchAmberOf(context)),
        if (rebuilder != null)
          VectorRebuildCard(rebuilder: rebuilder, embeddings: emb),
      ],
    );
  }
}
