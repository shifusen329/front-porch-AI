// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Scene backgrounds on the phone. SceneManager adds a picture with its
// place and time, renames, deletes, clears and imports a ZIP through the
// host, one post per tap however fast. SceneBackdrop cross-fades the chat
// background to the host's scene and back. ChatThemeSettings keeps the
// chat's scene choice when the theme is cleared and says what shows.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

type Scene = { name: string; place: string; time: string | null; alt: number };
const scene = (name: string, place: string, time: string | null = null): Scene => ({
  name,
  place,
  time,
  alt: 0,
});

const uploads: string[] = [];
const posts: { path: string; body: unknown }[] = [];
let scenes: Scene[] = [];
let uploadReply: () => Promise<unknown> = () => Promise.resolve({ scenes });

vi.mock('../api/client', () => {
  class ApiError extends Error {
    status: number;
    constructor(status: number, message: string) {
      super(message);
      this.status = status;
    }
  }
  return {
    ApiError,
    api: {
      get: () => Promise.resolve({ scenes }),
      post: (path: string, body: unknown) => {
        posts.push({ path, body });
        return Promise.resolve({ scenes });
      },
      upload: (path: string) => {
        uploads.push(path);
        return uploadReply();
      },
    },
  };
});

const { SceneManager } = await import('./SceneManager');
const { SceneBackdrop } = await import('./SceneBackdrop');
const { ChatThemeSettings } = await import('./ChatThemeSettings');
const { ApiError } = (await import('../api/client')) as unknown as {
  ApiError: new (status: number, message: string) => Error;
};

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  uploads.length = 0;
  posts.length = 0;
  scenes = [scene('porch.png', 'porch'), scene('porch-night.png', 'porch', 'night')];
  uploadReply = () => Promise.resolve({ scenes });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const settle = () =>
  act(async () => {
    for (let i = 0; i < 5; i++) await Promise.resolve();
  });

async function mount() {
  act(() => root.render(createElement(SceneManager, { characterId: 'c1' })));
  await settle();
}

const button = (text: string) =>
  [...container.querySelectorAll('button')].find(
    (b) => b.textContent?.trim() === text || b.getAttribute('aria-label') === text,
  );

async function click(text: string) {
  const b = button(text);
  if (!b) throw new Error(`no button "${text}"`);
  act(() => b.click());
  await settle();
}

/** Two clicks with no render between them. */
async function doubleTap(text: string) {
  const b = button(text);
  if (!b) throw new Error(`no button "${text}"`);
  act(() => {
    b.click();
    b.click();
  });
  await settle();
}

async function choose(testId: string, name: string) {
  const input = container.querySelector<HTMLInputElement>(`[data-testid="${testId}"]`)!;
  Object.defineProperty(input, 'files', { value: [new File(['x'], name)], configurable: true });
  act(() => void input.dispatchEvent(new Event('change', { bubbles: true })));
  await settle();
}

function type(input: HTMLInputElement | HTMLSelectElement, value: string) {
  const proto = input instanceof HTMLSelectElement ? HTMLSelectElement : HTMLInputElement;
  Object.getOwnPropertyDescriptor(proto.prototype, 'value')!.set!.call(input, value);
  act(() => void input.dispatchEvent(new Event(input instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true })));
}

it('lists the scenes and adds a picture with its place and time, once', async () => {
  await mount();
  expect(container.textContent).toContain('porch · night');

  await choose('scene-image-input', 'veranda.jpg');
  type(container.querySelector<HTMLInputElement>('.modal input')!, 'Living Room');
  type(container.querySelector<HTMLSelectElement>('.modal select')!, 'evening');
  await doubleTap('Save');

  expect(uploads).toEqual(['/api/characters/c1/scenes?place=Living%20Room&time=evening']);
  expect(container.textContent).toContain('Added living room.');
});

it('renames, deletes and clears through the host', async () => {
  await mount();
  await click('Rename porch · night');
  type(container.querySelector<HTMLInputElement>('.modal input')!, 'veranda');
  type(container.querySelector<HTMLSelectElement>('.modal select')!, '');
  await click('Save');
  expect(posts).toEqual([
    {
      path: '/api/characters/c1/scenes/rename',
      body: { name: 'porch-night.png', place: 'veranda', time: null },
    },
  ]);

  posts.length = 0;
  await click('Delete porch');
  expect(container.textContent).toContain('The porch picture goes for good.');
  await doubleTap('Delete');
  expect(posts).toEqual([{ path: '/api/characters/c1/scenes/delete', body: { name: 'porch.png' } }]);

  posts.length = 0;
  await click('Clear all');
  await click('Delete');
  expect(posts).toEqual([{ path: '/api/characters/c1/scenes/delete', body: { clear: true } }]);
});

it("imports a ZIP and shows the host's reason when it refuses", async () => {
  uploadReply = () => Promise.resolve({ scenes, added: 2, skipped: 1 });
  await mount();
  await choose('scene-zip-input', 'places.zip');
  expect(uploads).toEqual(['/api/characters/c1/scenes/zip']);
  expect(container.textContent).toContain('Added 2, skipped 1.');

  uploadReply = () => Promise.reject(new ApiError(400, 'That file is not a ZIP.'));
  await choose('scene-zip-input', 'notes.zip');
  expect(container.querySelector('.error')?.textContent).toBe('That file is not a ZIP.');
});

const porch = { who: 'Mabel', v: 'porch.png', place: 'porch', time: 'day' };
const kitchen = { who: 'Mabel', v: 'kitchen.png', place: 'kitchen', time: 'day' };
const layers = () =>
  [...container.querySelectorAll<HTMLElement>('.chat-scene-layer')].map(
    (l) => `${l.dataset.scene}${l.classList.contains('leaving') ? ' (leaving)' : ''}`,
  );

/** A layer's fade ends (React may listen for the prefixed name). */
function fadeEnds(el: Element) {
  act(() => {
    for (const name of ['animationend', 'webkitAnimationEnd']) {
      el.dispatchEvent(new Event(name, { bubbles: true }));
    }
  });
}

async function showScene(s: typeof porch | null) {
  act(() =>
    root.render(
      createElement('div', { className: 'chat-view' }, createElement(SceneBackdrop, { scene: s })),
    ),
  );
  await settle();
}

it('cross-fades the chat background to the scene and back', async () => {
  await showScene(porch);
  expect(layers()).toEqual(['Mabel/porch.png']);
  expect(container.querySelector('.chat-view')!.classList.contains('has-scene')).toBe(true);
  expect(container.querySelector<HTMLElement>('.chat-scene-layer')!.style.backgroundImage).toContain(
    '/api/chat/scene/image?who=Mabel&v=porch.png',
  );

  // The porch stays under the kitchen until the kitchen has faded in.
  await showScene(kitchen);
  expect(layers()).toEqual(['Mabel/porch.png', 'Mabel/kitchen.png']);
  const fresh = container.querySelector('[data-scene="Mabel/kitchen.png"]')!;
  fadeEnds(fresh);
  expect(layers()).toEqual(['Mabel/kitchen.png']);

  await showScene(null);
  expect(layers()).toEqual(['Mabel/kitchen.png (leaving)']);
  fadeEnds(container.querySelector('.chat-scene-layer')!);
  expect(layers()).toEqual([]);
  expect(container.querySelector('.chat-view')!.classList.contains('has-scene')).toBe(false);
});

it('with reduced motion, the scene goes at once', async () => {
  const before = window.matchMedia;
  window.matchMedia = ((q: string) => ({ matches: q.includes('reduce') })) as typeof window.matchMedia;
  try {
    await showScene(porch);
    await showScene(null);
    expect(layers()).toEqual([]);
  } finally {
    window.matchMedia = before;
  }
});

it("keeps the chat's scene choice when the theme is cleared, and says what shows", async () => {
  let saved: unknown = null;
  act(() =>
    root.render(
      createElement(ChatThemeSettings, {
        overrides: { themeId: 'noir', followScene: false, visualNovel: true },
        onSave: (o: unknown) => (saved = o),
        scene: { who: 'Mabel', v: 'porch-night.png', place: 'porch', time: 'night' },
      }),
    ),
  );
  await settle();
  expect(container.querySelector('[data-testid="scene-now-showing"]')?.textContent).toBe(
    'Now showing: porch · night',
  );
  const select = container.querySelector<HTMLSelectElement>('[data-testid="chat-follow-scene"]')!;
  expect(select.value).toBe('off');

  await click('Remove theme');
  await click('Save theme');
  expect(saved).toEqual({ visualNovel: true, followScene: false });

  type(container.querySelector<HTMLSelectElement>('[data-testid="chat-follow-scene"]')!, 'follow');
  await click('Save theme');
  expect(saved).toEqual({ visualNovel: true, followScene: null });
});

it('the painting switch reads and saves its own setting, and says when it could not', async () => {
  const { SceneBackgroundSettings } = await import('./SceneBackgroundSettings');
  const client = (await import('../api/client')) as unknown as {
    api: { get: (path: string) => Promise<unknown>; post: (path: string, body: unknown) => Promise<unknown> };
  };
  const get = vi
    .spyOn(client.api, 'get')
    .mockResolvedValueOnce({ sceneBackgrounds: true, scenePainting: false });
  act(() => root.render(createElement(SceneBackgroundSettings)));
  await settle();
  const box = (label: string) =>
    container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`)!;
  const painting = box('Paint missing places with the image generator');
  expect(painting.checked).toBe(false);
  expect(box('Backgrounds follow the scene').checked).toBe(true);

  act(() => painting.click());
  await settle();
  expect(posts).toEqual([{ path: '/api/settings', body: { scenePainting: true } }]);
  expect(painting.checked).toBe(true);

  const post = vi.spyOn(client.api, 'post').mockRejectedValueOnce(new Error('down'));
  act(() => painting.click());
  await settle();
  expect(painting.checked).toBe(true);
  expect(container.querySelector('[role="alert"]')?.textContent).toContain('could not be saved');
  get.mockRestore();
  post.mockRestore();
});

it('says which place is being painted, or why it could not be', async () => {
  const show = (painting: { place: string; time: string } | null, sceneProblem: string | null) =>
    act(() =>
      root.render(
        createElement(ChatThemeSettings, {
          overrides: null,
          onSave: () => {},
          scene: null,
          painting,
          sceneProblem,
        }),
      ),
    );
  show({ place: 'kitchen', time: 'night' }, null);
  await settle();
  expect(container.querySelector('[data-testid="scene-painting"]')?.textContent).toBe(
    'Painting the kitchen · night…',
  );

  show(null, "Couldn't paint the kitchen: out of memory");
  await settle();
  expect(container.querySelector('[data-testid="scene-painting"]')).toBeNull();
  expect(container.querySelector('[data-testid="scene-problem"]')?.textContent).toBe(
    "Couldn't paint the kitchen: out of memory",
  );
});
