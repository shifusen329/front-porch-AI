// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/ui/widgets/styled_text_tokenizer.dart';

/// One stretch of a chat message with markdown rendered: [start] and [end]
/// are offsets into the message, and the marks around it are left out.
/// [colour] is null for plain text. The phone web app's twin is
/// `web_ui/src/components/chatMarkdown.tsx`; keep the two the same.
typedef ChatMarkdownRun = ({
  int start,
  int end,
  StyledTokenType? colour,
  bool bold,
  bool italic,
  bool strike,
  bool code,
});

const _bold = 1, _italic = 2, _strike = 4, _code = 8, _action = 16;

/// The inline markdown chat replies use, one line at a time:
///
/// * `` `code` `` first, with nothing rendered inside it;
/// * `***both***`, `**bold**` and `*italic*` in the action colour (the
///   phone web app has always shown `**…**` that way);
/// * `__bold__` and `_italic_` (between words only, so `snake_case` stays)
///   and `~~struck~~` in the colour around them;
/// * "dialogue" keeps its quotes and its colour, and can hold any of these.
///
/// A mark with no partner on its line, or with a space inside it (`* a *`),
/// is shown as typed.
List<ChatMarkdownRun> chatMarkdownRuns(String text) {
  final hidden = List<bool>.filled(text.length, false);
  final flags = List<int>.filled(text.length, 0);
  // The marks already used become NUL here, so a later pattern can neither
  // reuse them nor see the marks inside code.
  final work = text.split('');

  void mark(String pattern, int open, int close, int flag) {
    for (final m in RegExp(pattern).allMatches(work.join())) {
      for (var i = m.start; i < m.end; i++) {
        final inMarks = i < m.start + open || i >= m.end - close;
        if (inMarks) {
          hidden[i] = true;
        } else {
          flags[i] |= flag;
        }
        if (inMarks || flag == _code) work[i] = '\u0000';
      }
    }
  }

  // A pair counts only when it hugs its text, so `2 * 3 * 4` keeps its stars.
  mark(r'`[^`\n]+`', 1, 1, _code);
  mark(r'\*\*\*(?!\s)[^*\n]+?(?<!\s)\*\*\*', 3, 3, _bold | _italic | _action);
  mark(r'\*\*(?!\s)[^*\n]+?(?<!\s)\*\*', 2, 2, _bold | _action);
  mark(r'(?<!\w)__(?!\s)[^_\n]+?(?<!\s)__(?!\w)', 2, 2, _bold);
  mark(r'~~(?!\s)[^~\n]+?(?<!\s)~~', 2, 2, _strike);
  mark(r'\*(?!\s)[^*\n]+?(?<!\s)\*', 1, 1, _italic | _action);
  mark(r'(?<!\w)_(?!\s)[^_\n]+?(?<!\s)_(?!\w)', 1, 1, _italic);

  final dialogue = List<bool>.filled(text.length, false);
  for (final d in scanDialogue(text, const [])) {
    for (var i = d.start; i < d.end; i++) {
      dialogue[i] = true;
    }
  }

  StyledTokenType? colourAt(int i) {
    if (flags[i] & _code != 0) return null;
    if (dialogue[i]) return StyledTokenType.dialogue;
    return flags[i] & _action != 0 ? StyledTokenType.action : null;
  }

  int styleAt(int i) => flags[i] & (_bold | _italic | _strike | _code);

  final runs = <ChatMarkdownRun>[];
  var i = 0;
  while (i < text.length) {
    if (hidden[i]) {
      i++;
      continue;
    }
    final start = i;
    final colour = colourAt(i);
    final style = styleAt(i);
    while (i < text.length &&
        !hidden[i] &&
        colourAt(i) == colour &&
        styleAt(i) == style) {
      i++;
    }
    runs.add((
      start: start,
      end: i,
      colour: colour,
      bold: style & _bold != 0,
      italic: style & _italic != 0,
      strike: style & _strike != 0,
      code: style & _code != 0,
    ));
  }
  return runs;
}
