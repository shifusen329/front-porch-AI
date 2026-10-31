// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

/// One textual-inversion embedding on the desk. Automatic1111 and ComfyUI
/// read an embedding from its name in the prompt, so each pick goes in the
/// prompt or, when [negative], in the negative prompt.
class ImageGenEmbedding {
  const ImageGenEmbedding(this.name, {required this.negative});

  /// A new pick. Names like `lazyneg`, `IllusN3g` or `badhandv4` are made
  /// for the negative prompt; the rest go in the prompt.
  factory ImageGenEmbedding.picked(String name) => ImageGenEmbedding(
    name.trim(),
    negative: RegExp(r'n[e3]g|bad', caseSensitive: false).hasMatch(name),
  );

  final String name;
  final bool negative;

  Map<String, Object> toJson() => {'name': name, 'negative': negative};

  /// Rows from the settings or the phone. A row without a `negative` is a
  /// new pick, a blank name is dropped and each name is kept once.
  static List<ImageGenEmbedding> fromRows(Iterable<Object?> rows) {
    final out = <ImageGenEmbedding>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = row['name']?.toString().trim() ?? '';
      if (name.isEmpty || out.any((e) => e.name == name)) continue;
      final negative = row['negative'];
      out.add(
        negative is bool
            ? ImageGenEmbedding(name, negative: negative)
            : ImageGenEmbedding.picked(name),
      );
    }
    return out;
  }

  static String encode(List<ImageGenEmbedding> picks) =>
      jsonEncode([for (final e in picks) e.toJson()]);

  static List<ImageGenEmbedding> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return fromRows(decoded);
    } on FormatException {
      // A bad value is no embeddings.
    }
    return const [];
  }
}

/// [prompt] and [negative] with each pick put first on its own side, in the
/// form the backend reads: the bare name for Automatic1111, `embedding:name`
/// for ComfyUI. A name already written there is not added twice.
({String prompt, String negative}) promptsWithEmbeddings(
  String prompt,
  String negative,
  List<ImageGenEmbedding> picks, {
  bool comfy = false,
}) {
  String lead(String text, bool negativeSide) {
    final names = [
      for (final e in picks)
        if (e.negative == negativeSide && !_mentions(text, e.name))
          comfy ? 'embedding:${e.name}' : e.name,
    ];
    final rest = text.trim();
    if (names.isEmpty) return text;
    return [...names, if (rest.isNotEmpty) rest].join(', ');
  }

  return (prompt: lead(prompt, false), negative: lead(negative, true));
}

bool _mentions(String text, String name) => RegExp(
  '(^|[\\s,(:])${RegExp.escape(name)}(?=\$|[\\s,:)])',
  caseSensitive: false,
).hasMatch(text);
