// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Visual novel mode on the phone: the stage shows each figure the host
// lists, in the picture it names, the last speaker in front; the log panel
// grows to the full height and back; the global switch saves to the same
// setting the desktop uses; and a chat's own choice survives clearing its
// theme. Renders the real components; the host's answers are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { VisualNovelLog, VisualNovelStage, stageImageUrl } from './VisualNovelStage';
import { VisualNovelSettings } from './VisualNovelSettings';
import { ChatThemeSettings } from './ChatThemeSettings';
import type { ChatThemeOverrides } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const render = async (el: ReturnType<typeof createElement>) => {
  await act(async () => {
    root.render(el);
  });
};

describe('Visual novel stage', () => {
  it('shows each listed figure in the picture the host names, the speaker in front', async () => {
    const sprites = [
      { id: 'ada', name: 'Ada', speaking: false, v: 'neutral-1.png' },
      { id: 'bex', name: 'Bex', speaking: true, v: 'joy 2.png' },
    ];
    await render(createElement(VisualNovelStage, { sprites }));

    const figures = [...container.querySelectorAll('.vn-sprite')];
    expect(figures).toHaveLength(2);
    expect(figures[0].classList.contains('back')).toBe(true);
    expect(figures[1].classList.contains('back')).toBe(false);
    expect(figures[1].querySelector('img')?.getAttribute('src')).toBe(
      '/api/chat/stage/bex?v=joy%202.png',
    );
    expect(stageImageUrl(sprites[0])).toBe('/api/chat/stage/ada?v=neutral-1.png');
  });

  it('draws nothing when nobody has a picture', async () => {
    await render(createElement(VisualNovelStage, { sprites: [] }));
    expect(container.querySelector('[data-testid="vn-stage"]')).toBeNull();
  });

  it('the log handle grows the panel to the full height and back', async () => {
    let expanded = false;
    const draw = () =>
      render(
        createElement(
          VisualNovelLog,
          { expanded, onToggle: () => (expanded = !expanded) },
          createElement('div', { className: 'chat-messages' }, 'the chat'),
        ),
      );
    await draw();
    const handle = () => container.querySelector<HTMLButtonElement>('.vn-handle')!;
    expect(handle().getAttribute('aria-label')).toBe('Show the whole chat');

    await act(async () => handle().click());
    await draw();
    expect(container.querySelector('[data-testid="vn-log"]')?.classList.contains('expanded')).toBe(true);
    expect(handle().getAttribute('aria-label')).toBe('Show the stage');
  });
});

describe('Visual novel switches', () => {
  it('the global switch shows the desktop setting and saves to it', async () => {
    get.mockResolvedValue({ visualNovelMode: false });
    post.mockResolvedValue({});
    await render(createElement(VisualNovelSettings));
    const box = container.querySelector<HTMLInputElement>('input[aria-label="Visual novel mode"]')!;
    expect(box.checked).toBe(false);

    await act(async () => box.click());

    expect(post).toHaveBeenCalledWith('/api/settings', { visualNovelMode: true });
    expect(box.checked).toBe(true);
  });

  it("a chat's own choice is saved, and survives removing its theme", async () => {
    const saved: ChatThemeOverrides[] = [];
    await render(
      createElement(ChatThemeSettings, {
        overrides: { themeId: 'noir' },
        onSave: (o: ChatThemeOverrides) => saved.push(o),
      }),
    );
    const choice = container.querySelector<HTMLSelectElement>('[data-testid="chat-visual-novel"]')!;
    expect(choice.value).toBe('follow');

    await act(async () => {
      choice.value = 'on';
      choice.dispatchEvent(new Event('change', { bubbles: true }));
    });
    const remove = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Remove theme');
    if (remove) await act(async () => remove.click());
    const save = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Save theme')!;
    await act(async () => save.click());

    expect(saved.at(-1)?.visualNovel).toBe(true);
    expect(saved.at(-1)?.themeId ?? null).toBeNull();
  });
});
