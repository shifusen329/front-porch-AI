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

import 'package:front_porch_ai/services/scenes/scenes.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// A scene's place and time, as the form returns them.
typedef ScenePlace = ({String place, SceneTime? time});

/// What a time choice reads as.
String sceneTimeLabel(SceneTime? time) => switch (time) {
  null => 'Any time',
  SceneTime.morning => 'Morning',
  SceneTime.day => 'Day',
  SceneTime.evening => 'Evening',
  SceneTime.night => 'Night',
};

/// Asks where a picture is and when. Null when cancelled.
Future<ScenePlace?> askScenePlace(
  BuildContext context, {
  required String title,
  String place = '',
  SceneTime? time,
}) => showWarmDialogOf<ScenePlace>(
  context,
  builder: (_) => _ScenePlaceForm(title: title, place: place, time: time),
);

class _ScenePlaceForm extends StatefulWidget {
  const _ScenePlaceForm({
    required this.title,
    required this.place,
    required this.time,
  });

  final String title;
  final String place;
  final SceneTime? time;

  @override
  State<_ScenePlaceForm> createState() => _ScenePlaceFormState();
}

class _ScenePlaceFormState extends State<_ScenePlaceForm> {
  late final _place = TextEditingController(text: widget.place);
  late SceneTime? _time = widget.time;
  String? _problem;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  void _save() {
    final problem = scenePlaceProblem(_place.text);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop((place: _place.text.trim(), time: _time));
  }

  @override
  Widget build(BuildContext context) {
    return WarmDialog(
      title: widget.title,
      icon: Icons.landscape_outlined,
      accent: AppColors.formAccentOf(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('scene-place'),
            controller: _place,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Place',
              hintText: 'porch, kitchen, living room',
              errorText: _problem,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SceneTime?>(
            key: const ValueKey('scene-time'),
            initialValue: _time,
            decoration: const InputDecoration(labelText: 'Time of day'),
            items: [
              for (final t in [null, ...SceneTime.values])
                DropdownMenuItem(value: t, child: Text(sceneTimeLabel(t))),
            ],
            onChanged: (t) => setState(() => _time = t),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('scene-place-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
