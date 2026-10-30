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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_store/character_row_codec.dart'
    show mediaFolderName;
import 'package:front_porch_ai/services/chat/chat.dart' show SceneBackdrop;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'scene_place_form.dart';
import 'scene_tile.dart';

/// Hands back a picked file's bytes, or null when cancelled.
typedef SceneBytesPicker = Future<Uint8List?> Function(BuildContext context);

/// Opens [character]'s Scenes: pictures of places the chat background
/// switches to. [chat] is the chat it was opened from, for "Now showing".
/// The pickers are the system file windows unless a test passes its own.
Future<void> openSceneLibrary(
  BuildContext context, {
  required CharacterCard character,
  required StorageService storage,
  ChatService? chat,
  SceneBytesPicker? pickImage,
  SceneBytesPicker? pickZip,
}) => showWarmDialogOf<void>(
  context,
  builder: (_) => SceneLibraryDialog(
    character: character,
    storage: storage,
    chat: chat,
    pickImage: pickImage ?? pickImageBytes,
    pickZip: pickZip ?? pickZipBytes,
  ),
);

class SceneLibraryDialog extends StatefulWidget {
  const SceneLibraryDialog({
    super.key,
    required this.character,
    required this.storage,
    required this.pickImage,
    required this.pickZip,
    this.chat,
  });

  final CharacterCard character;
  final StorageService storage;
  final ChatService? chat;
  final SceneBytesPicker pickImage;
  final SceneBytesPicker pickZip;

  @override
  State<SceneLibraryDialog> createState() => _SceneLibraryDialogState();
}

class _SceneLibraryDialogState extends State<SceneLibraryDialog> {
  late final _library = SceneLibrary(() => widget.storage.charactersDir);
  List<SceneImage> _scenes = const [];

  /// Set before the first await, so a second tap in the same frame does
  /// nothing.
  bool _acting = false;
  String? _note;
  bool _noteIsError = false;

  String get _name => widget.character.name;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final scenes = await _library.list(_name);
    if (mounted) setState(() => _scenes = scenes);
  }

  Future<void> _act(Future<String?> Function() job) async {
    if (_acting) return;
    _acting = true;
    String? note;
    var error = false;
    try {
      note = await job();
    } on FormatException catch (e) {
      (note, error) = (e.message, true);
    } on FileSystemException catch (e) {
      (note, error) = (
        "Couldn't change that picture (${e.osError?.message ?? e.message}). "
            'Close anything showing it and try again.',
        true,
      );
    } finally {
      _acting = false;
    }
    await _reload();
    if (mounted && note != null) {
      setState(() {
        _note = note;
        _noteIsError = error;
      });
    }
  }

  void _add() => _act(() async {
    final bytes = await widget.pickImage(context);
    if (bytes == null || !mounted) return null;
    final where = await askScenePlace(context, title: 'Where is this?');
    if (where == null) return null;
    final scene = await _library.add(
      _name,
      bytes,
      place: where.place,
      time: where.time,
    );
    return 'Added ${scene.place}.';
  });

  void _import() => _act(() async {
    final zip = await widget.pickZip(context);
    if (zip == null) return null;
    final (:added, :skipped) = await _library.importZip(_name, zip);
    if (added == 0) {
      throw const FormatException(
        'No picture in that ZIP is named for a place, like porch.png or '
        'porch-night.png.',
      );
    }
    return 'Added $added${skipped > 0 ? ', skipped $skipped' : ''}.';
  });

  void _edit(SceneImage scene) => _act(() async {
    final where = await askScenePlace(
      context,
      title: 'Rename picture',
      place: scene.place,
      time: scene.time,
    );
    if (where == null) return null;
    final moved = await _library.rename(
      _name,
      scene.name,
      place: where.place,
      time: where.time,
    );
    return moved == null ? null : 'Renamed to ${moved.place}.';
  });

  void _delete(SceneImage scene) => _act(() async {
    final yes = await _confirm(
      'Delete this picture?',
      'The ${scene.place} picture goes for good.',
    );
    if (!yes) return null;
    await _library.remove(_name, scene.name);
    return 'Deleted ${scene.place}.';
  });

  void _clear() => _act(() async {
    final yes = await _confirm(
      'Delete every scene picture?',
      'All ${_scenes.length} pictures of places for $_name go. Their '
          'expressions and looks stay.',
    );
    if (!yes) return null;
    return 'Deleted ${await _library.clear(_name)}.';
  });

  Future<bool> _confirm(String title, String body) async =>
      await showWarmDialog<bool>(
        context,
        title: title,
        destructive: true,
        icon: Icons.delete_outline_rounded,
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('scene-confirm-delete'),
            style: FilledButton.styleFrom(
              backgroundColor: StatusColors.dangerOf(context),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textTertiary(context);
    final chat = widget.chat;
    return WarmDialog(
      title: 'Scenes · $_name',
      icon: Icons.landscape_outlined,
      accent: AppColors.formAccentOf(context),
      width: 640,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pictures of places. With the Realism Engine on, the chat '
              'background switches to wherever $_name is. Name each picture '
              'for its place: porch, kitchen, living room.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
            ),
            if (chat != null) ...[
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: SceneBackdrop.of(chat, widget.storage),
                builder: (context, _) => Text(
                  _nowShowing(chat),
                  key: const ValueKey('scene-now-showing'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.formAccentOf(context),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) => GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: math.max(2, box.maxWidth ~/ 150),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  for (final s in _scenes)
                    SceneTile(
                      scene: s,
                      showing: _isShowing(s),
                      onEdit: () => _edit(s),
                      onDelete: () => _delete(s),
                    ),
                  GalleryAddTile(
                    key: const ValueKey('scene-add'),
                    label: 'Add picture',
                    onTap: _add,
                  ),
                  GalleryAddTile(
                    key: const ValueKey('scene-import-zip'),
                    label: 'Import ZIP',
                    onTap: _import,
                  ),
                ],
              ),
            ),
            if (_note != null) ...[
              const SizedBox(height: 10),
              Text(
                _note!,
                key: const ValueKey('scene-note'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: _noteIsError
                      ? StatusColors.dangerOf(context)
                      : AppColors.textSecondary(context),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_scenes.isNotEmpty)
          TextButton(
            key: const ValueKey('scene-clear'),
            onPressed: _clear,
            child: Text(
              'Clear all',
              style: TextStyle(color: StatusColors.dangerOf(context)),
            ),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  bool _isShowing(SceneImage s) {
    final chat = widget.chat;
    if (chat == null) return false;
    final shot = SceneBackdrop.of(chat, widget.storage).current;
    return shot != null &&
        shot.who == mediaFolderName(_name) &&
        shot.scene.name == s.name;
  }

  String _nowShowing(ChatService chat) {
    final backdrop = SceneBackdrop.of(chat, widget.storage);
    if (!chat.realismEnabled) {
      return 'Turn on the Realism Engine for this chat and the background '
          'follows these pictures.';
    }
    if (!backdrop.following) {
      return 'Scene backgrounds are off for this chat (UI Settings).';
    }
    final shot = backdrop.current;
    if (shot == null) {
      return "Showing the chat's own background until the story reaches one "
          'of these places.';
    }
    return 'Now showing: ${shot.scene.place} · '
        '${sceneTimeLabel(shot.time).toLowerCase()}';
  }
}
