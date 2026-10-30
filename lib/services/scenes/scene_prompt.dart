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

import 'dart:math' show sqrt;

import 'package:front_porch_ai/services/image_gen/image_gen.dart'
    show parseImageGenSize;

import 'scene_image.dart';

/// The most tags a painted place's prompt keeps, before the style.
const kMaxSceneTags = 40;

/// What every painted place opens with: a background with nobody in it.
const kSceneLeadTags = ['no humans', 'scenery'];

/// Kept out of a painted place, beside the user's own negative prompt.
const kSceneNegativeTags = [
  '1girl', '1boy', 'solo', 'person', 'people', 'humans', //
  'text', 'watermark', 'signature',
];

/// The tags that make a painted place look its time of day.
List<String> sceneTimeTags(SceneTime t) => switch (t) {
  SceneTime.morning => const ['morning'],
  SceneTime.day => const ['day'],
  SceneTime.evening => const ['evening', 'sunset'],
  SceneTime.night => const ['night'],
};

final _peopleTag = RegExp(
  r'^(\d+\+?(girl|boy|other)s?|solo|solo focus|person|people|man|men|woman|'
  r'women|girl|boy|couple|crowd|human|humans|character|looking at viewer|'
  r'multiple (girls|boys|people)|male focus|female focus)$',
);
final _bodyWord = RegExp(
  r'\b(hair|eyes?|breasts?|skin|face|hands?|legs?|smile|nude|naked|dress|'
  r'shirt|clothes|clothing)\b',
);
final _label = RegExp(
  r'^(tags|prompt|image prompt|output)\s*:\s*',
  caseSensitive: false,
);
final _fence = RegExp(r'^```[a-z]*\s*|\s*```$');

/// The side-lane prompt that turns the story's place into an image prompt
/// for an empty background: danbooru tags when [tags], else one paragraph.
/// [story] is the reply the place came from, already cleaned for pictures.
String scenePromptInstruction({
  required String place,
  required String stance,
  required SceneTime time,
  required String setting,
  required String story,
  required bool tags,
}) {
  final facts = [
    'Place: $place',
    if (stance.trim().isNotEmpty) 'Where the character is: ${stance.trim()}',
    'Time of day: ${time.name}',
    if (setting.trim().isNotEmpty) 'Setting: ${_cap(setting, 400)}',
    if (story.trim().isNotEmpty) 'What the story says:\n${_cap(story, 800)}',
  ].join('\n');
  final format = tags
      ? 'Write a flat, comma-separated list of danbooru-style tags. Begin '
            'with: no humans, scenery. Then the kind of place (indoors or '
            'outdoors, the room or the landscape), the things in it, the '
            'light for the time of day, the weather and the mood. No people, '
            'body parts, clothing, names or sentences. At most $kMaxSceneTags '
            'tags.'
      : 'Write ONE paragraph of plain descriptive English: the place, the '
            'things in it, the light for the time of day, the weather and the '
            'mood. The place is empty: no people, no names, no dialogue.';
  return 'You write image prompts for empty backgrounds: a place, with '
      'nobody in it.\n$format\n\n$facts\n\n'
      'Output ONLY the prompt. No explanations, no markdown, no extra lines.';
}

/// The model's tag list made safe for a background: its own lead, no people
/// or bodies or [names], the time of day it is (and no other), [place]
/// itself, at most [kMaxSceneTags], then [styleSuffix].
String cleanSceneTags(
  String raw, {
  required String place,
  required SceneTime time,
  List<String> names = const [],
  String styleSuffix = '',
}) {
  final text = raw.trim().replaceAll(_fence, '').replaceFirst(_label, '');
  final nameWords = [
    for (final n in names)
      if (n.trim().isNotEmpty)
        RegExp('\\b${RegExp.escape(n.trim().toLowerCase())}\\b'),
  ];
  final otherTimes = {
    for (final t in SceneTime.values)
      if (t != time) ...sceneTimeTags(t),
  }..removeAll(sceneTimeTags(time));
  final must = [place.trim().toLowerCase(), ...sceneTimeTags(time)];

  final seen = <String>{...kSceneLeadTags};
  final picked = <String>[];
  for (final part in text.split(RegExp(r'[,\n]'))) {
    final tag = part
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.;:]+$'), '');
    // A long piece is a sentence the model wrote instead of tags.
    if (tag.isEmpty || tag.split(' ').length > 5) continue;
    if (_peopleTag.hasMatch(tag) || _bodyWord.hasMatch(tag)) continue;
    if (otherTimes.contains(tag)) continue;
    if (nameWords.any((n) => n.hasMatch(tag))) continue;
    if (seen.add(tag)) picked.add(tag);
  }
  final missing = [
    for (final m in must)
      if (m.isNotEmpty && !picked.contains(m)) m,
  ];
  final room = kMaxSceneTags - kSceneLeadTags.length - missing.length;
  final prompt = [
    ...kSceneLeadTags,
    ...picked.take(room < 0 ? 0 : room),
    ...missing,
  ].join(', ');
  return styleSuffix.isEmpty ? prompt : '$prompt, $styleSuffix';
}

/// The model's paragraph made safe for a background: no [names], said to be
/// empty, then [styleSuffix].
String cleanSceneSentences(
  String raw, {
  List<String> names = const [],
  String styleSuffix = '',
}) {
  var text = raw.trim().replaceAll(_fence, '').replaceFirst(_label, '');
  for (final n in names) {
    if (n.trim().isEmpty) continue;
    text = text.replaceAll(
      RegExp(
        "\\b${RegExp.escape(n.trim())}(?:['’]s)?\\b",
        caseSensitive: false,
      ),
      '',
    );
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isNotEmpty && !RegExp(r'[.!?]$').hasMatch(text)) text = '$text.';
  if (!RegExp(r'\bno (people|one)\b', caseSensitive: false).hasMatch(text)) {
    text = text.isEmpty ? 'No people.' : '$text No people.';
  }
  return styleSuffix.isEmpty ? text : '$text $styleSuffix';
}

/// The prompt for [place] when no model wrote one.
String staticScenePrompt({
  required String place,
  required SceneTime time,
  required bool tags,
  String styleSuffix = '',
}) {
  if (tags) {
    return cleanSceneTags(
      '',
      place: place,
      time: time,
      styleSuffix: styleSuffix,
    );
  }
  final when = switch (time) {
    SceneTime.morning => 'in the morning light',
    SceneTime.day => 'in daylight',
    SceneTime.evening => 'at sunset',
    SceneTime.night => 'at night',
  };
  final text = 'An empty $place $when, with nobody in it. No people.';
  return styleSuffix.isEmpty ? text : '$text $styleSuffix';
}

/// The negative prompt for a painted place: the user's [configured] one,
/// and for tags the people a background must not have.
String sceneNegative(String configured, {required bool tags}) {
  if (!tags) return configured.trim();
  final seen = <String>{};
  return [
    for (final t in [...configured.split(','), ...kSceneNegativeTags])
      if (t.trim().isNotEmpty && seen.add(t.trim().toLowerCase())) t.trim(),
  ].join(', ');
}

/// The size to paint a place at: landscape, about the [configured] area, on
/// a [local] generator whose sizes are free. Null for a remote service,
/// whose sizes are its own list, so it keeps the configured one.
String? sceneSize(String configured, {required bool local}) {
  if (!local) return null;
  final (w, h) = parseImageGenSize(configured);
  if (w > h) return '${w}x$h';
  final area = w * h;
  final width = ((sqrt(area * 1.5) / 64).floor() * 64).clamp(256, 4096);
  final height = ((area / width / 64).round() * 64).clamp(256, 4096);
  return '${width}x$height';
}

String _cap(String text, int max) {
  final t = text.trim();
  return t.length <= max ? t : '${t.substring(0, max)}…';
}
