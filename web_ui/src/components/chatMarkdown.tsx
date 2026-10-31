// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat messages with their inline markdown rendered (Settings → Appearance →
// Show markdown formatting in messages). The rules are the desktop's
// lib/ui/widgets/chat_markdown.dart; keep the two the same:
//
//  - `code` first, with nothing rendered inside it;
//  - ***both***, **bold** and *italic* in the action colour;
//  - __bold__, _italic_ (between words only) and ~~struck~~ in the colour
//    around them;
//  - "dialogue" keeps its quotes and its colour, and can hold any of these;
//  - a pair counts only when it hugs its text, so 2 * 3 * 4 keeps its stars.
// Spans carry plain text only; no HTML is injected.

import type { ReactNode } from 'react';
import { DIALOGUE_RE } from './rpText';

const BOLD = 1;
const ITALIC = 2;
const STRIKE = 4;
const CODE = 8;
const ACTION = 16;

const PASSES: [RegExp, number, number][] = [
  [/`[^`\n]+`/g, 1, CODE],
  [/\*\*\*(?!\s)[^*\n]+?(?<!\s)\*\*\*/g, 3, BOLD | ITALIC | ACTION],
  [/\*\*(?!\s)[^*\n]+?(?<!\s)\*\*/g, 2, BOLD | ACTION],
  [/(?<!\w)__(?!\s)[^_\n]+?(?<!\s)__(?!\w)/g, 2, BOLD],
  [/~~(?!\s)[^~\n]+?(?<!\s)~~/g, 2, STRIKE],
  [/\*(?!\s)[^*\n]+?(?<!\s)\*/g, 1, ITALIC | ACTION],
  [/(?<!\w)_(?!\s)[^_\n]+?(?<!\s)_(?!\w)/g, 1, ITALIC],
];

export interface MarkdownRun {
  start: number;
  end: number;
  colour: 'dialogue' | 'action' | null;
  bold: boolean;
  italic: boolean;
  strike: boolean;
  code: boolean;
}

/** The visible stretches of [text], as offsets into it; marks are left out. */
export function chatMarkdownRuns(text: string): MarkdownRun[] {
  const n = text.length;
  const hidden = new Array<boolean>(n).fill(false);
  const flags = new Array<number>(n).fill(0);
  // Marks already used (and code) become NUL, so a later pass can neither
  // reuse them nor see the marks inside code.
  const work = text.split('');
  for (const [re, marks, flag] of PASSES) {
    re.lastIndex = 0;
    for (const m of work.join('').matchAll(re)) {
      const start = m.index ?? 0;
      const end = start + m[0].length;
      for (let i = start; i < end; i++) {
        const inMarks = i < start + marks || i >= end - marks;
        if (inMarks) hidden[i] = true;
        else flags[i] |= flag;
        if (inMarks || flag === CODE) work[i] = '\u0000';
      }
    }
  }
  const dialogue = new Array<boolean>(n).fill(false);
  for (const m of text.matchAll(DIALOGUE_RE)) {
    const start = m.index ?? 0;
    for (let i = start; i < start + m[0].length; i++) dialogue[i] = true;
  }
  const colourAt = (i: number): MarkdownRun['colour'] =>
    flags[i] & CODE ? null : dialogue[i] ? 'dialogue' : flags[i] & ACTION ? 'action' : null;
  const styleAt = (i: number) => flags[i] & (BOLD | ITALIC | STRIKE | CODE);

  const runs: MarkdownRun[] = [];
  let i = 0;
  while (i < n) {
    if (hidden[i]) {
      i++;
      continue;
    }
    const start = i;
    const colour = colourAt(i);
    const style = styleAt(i);
    while (i < n && !hidden[i] && colourAt(i) === colour && styleAt(i) === style) i++;
    runs.push({
      start,
      end: i,
      colour,
      bold: (style & BOLD) !== 0,
      italic: (style & ITALIC) !== 0,
      strike: (style & STRIKE) !== 0,
      code: (style & CODE) !== 0,
    });
  }
  return runs;
}

/** [text] rendered; [mark] paints ⌘F hits at offsets into the caller's string. */
export function renderChatMarkdown(
  text: string,
  keyBase: string,
  mark?: (plain: string, key: string, offset: number) => ReactNode,
  baseOffset = 0,
): ReactNode[] {
  return chatMarkdownRuns(text).map((r) => {
    const key = `${keyBase}-${r.start}`;
    const plain = text.slice(r.start, r.end);
    const body = mark ? mark(plain, `${key}-m`, baseOffset + r.start) : plain;
    const classes = [
      r.colour === 'dialogue' ? 'md-dlg' : r.colour === 'action' ? 'md-act' : '',
      r.bold ? 'md-b' : '',
      r.italic ? 'md-i' : '',
      r.strike ? 'md-s' : '',
      r.code ? 'md-code' : '',
    ].filter(Boolean);
    return classes.length ? <span key={key} className={classes.join(' ')}>{body}</span> : <span key={key}>{body}</span>;
  });
}
