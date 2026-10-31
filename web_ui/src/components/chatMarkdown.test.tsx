// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Show markdown formatting in messages, in the phone web app: the same rules
// as the desktop's test/ui/widgets/chat_markdown_test.dart, a message with
// the switch on and off, and the Settings switch.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { chatMarkdownRuns } from './chatMarkdown';
import { MessageContent } from './MessageContent';
import { ChatMarkdownSettings } from './ChatMarkdownSettings';
import { setChatMarkdown } from '../hooks/useChatMarkdown';

/** [text]'s runs as `[i a]waves`, the desktop test's notation. */
function shown(text: string): string {
  return chatMarkdownRuns(text)
    .map((r) => {
      const tags = [
        r.bold && 'b',
        r.italic && 'i',
        r.strike && 's',
        r.code && 'c',
        r.colour === 'action' && 'a',
        r.colour === 'dialogue' && 'd',
      ]
        .filter(Boolean)
        .join(' ');
      const piece = text.slice(r.start, r.end);
      return tags ? `[${tags}]${piece}` : piece;
    })
    .join('|');
}

describe('the rules, as on the desktop', () => {
  it('stars give italics and bold in the action colour', () => {
    expect(shown('*waves*')).toBe('[i a]waves');
    expect(shown('**finally**')).toBe('[b a]finally');
    expect(shown('***both***')).toBe('[b i a]both');
    expect(shown('She *smiles*.')).toBe('She |[i a]smiles|.');
  });

  it('underscores and tildes keep the colour around them', () => {
    expect(shown('__loud__ and _soft_')).toBe('[b]loud| and |[i]soft');
    expect(shown('~~gone~~')).toBe('[s]gone');
    expect(shown('snake_case_name')).toBe('snake_case_name');
  });

  it('nothing is rendered inside code', () => {
    expect(shown('run `*not italic*` now')).toBe('run |[c]*not italic*| now');
  });

  it('dialogue keeps its quotes and can hold emphasis', () => {
    expect(shown('"I *really* mean it"')).toBe('[d]"I |[i d]really|[d] mean it"');
  });

  it('emphasis nests inside an action', () => {
    expect(shown('*a **b** c*')).toBe('[i a]a |[b i a]b|[i a] c');
  });

  it('marks with no partner, a space inside or a line break stay', () => {
    expect(shown('*walks over')).toBe('*walks over');
    expect(shown('2 * 3 * 4')).toBe('2 * 3 * 4');
    expect(shown('*one\ntwo*')).toBe('*one\ntwo*');
  });
});

describe('a message and the switch', () => {
  let container: HTMLDivElement;
  let root: Root;

  beforeEach(() => {
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    get.mockReset();
    post.mockReset();
    get.mockResolvedValue({ chatMarkdown: true });
    post.mockResolvedValue({});
    setChatMarkdown(true);
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  async function render(el: JSX.Element) {
    await act(async () => {
      root.render(el);
    });
  }

  const bubble = () => container.querySelector('.bubble')!;

  it('shows the formatting without the marks, by default', async () => {
    await render(<div className="bubble ai"><MessageContent text="*waves* and **grins**" /></div>);
    expect(bubble().textContent).toBe('waves and grins');
    expect(bubble().querySelector('.md-i.md-act')?.textContent).toBe('waves');
    expect(bubble().querySelector('.md-b.md-act')?.textContent).toBe('grins');
  });

  it('follows the desktop when the app says it is off', async () => {
    get.mockResolvedValue({ chatMarkdown: false });
    await render(<div className="bubble ai"><MessageContent text="*waves* and **grins**" /></div>);
    expect(bubble().textContent).toBe('*waves* and **grins**');
    expect(bubble().querySelector('.md-i, .md-b')).toBeNull();
  });

  it('the Settings switch saves the choice and messages follow at once', async () => {
    await render(
      <div>
        <ChatMarkdownSettings />
        <div className="bubble ai"><MessageContent text="*waves*" /></div>
      </div>,
    );
    const box = container.querySelector<HTMLInputElement>(
      'input[aria-label="Show markdown formatting in messages"]',
    )!;
    expect(box.checked).toBe(true);

    await act(async () => {
      box.click();
    });
    expect(post).toHaveBeenCalledTimes(1);
    expect(post).toHaveBeenCalledWith('/api/settings', { chatMarkdown: false });
    expect(box.checked).toBe(false);
    expect(bubble().textContent).toBe('*waves*');
  });
});
