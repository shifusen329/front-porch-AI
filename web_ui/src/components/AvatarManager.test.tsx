// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The character's expressions on the phone: the desktop's 40-expression
// counter (alternates don't count) and its "Import ZIP sprite pack", sent to
// the host's /avatars/zip, with the host's reasons shown when it refuses.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

type Item = { id: string; label: string; displayOrder: number; isPrime: boolean; isLook: boolean; isFavorite: boolean };
const item = (id: string, label: string, isLook = false): Item => ({
  id,
  label,
  displayOrder: 0,
  isPrime: false,
  isLook,
  isFavorite: false,
});

const uploads: string[] = [];
const posts: { path: string; body: unknown }[] = [];
let avatars: Item[] = [];
let uploadReply: () => Promise<unknown> = () => Promise.resolve({});
let postReply: (path: string) => Promise<unknown> = () => Promise.resolve({ avatars });

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
      get: () => Promise.resolve({ avatars }),
      post: (path: string, body: unknown) => {
        posts.push({ path, body });
        return postReply(path);
      },
      upload: (path: string) => {
        uploads.push(path);
        return uploadReply();
      },
    },
  };
});

const { AvatarManager } = await import('./AvatarManager');
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
  postReply = () => Promise.resolve({ avatars });
  avatars = [item('a', 'joy'), item('b', 'Joy'), item('c', 'anger'), item('d', '__look__', true)];
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
  act(() => root.render(createElement(AvatarManager, { characterId: 'c1' })));
  await settle();
}

async function chooseZip(name: string) {
  const input = container.querySelector<HTMLInputElement>('input[accept=".zip,application/zip"]')!;
  Object.defineProperty(input, 'files', { value: [new File(['zip'], name)], configurable: true });
  act(() => void input.dispatchEvent(new Event('change', { bubbles: true })));
  await settle();
}

const button = (text: string) =>
  [...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === text);

async function click(text: string) {
  const b = button(text);
  if (!b) throw new Error(`no button "${text}"`);
  act(() => b.click());
  await settle();
}

/** Picks a ZIP; with expressions already here, answers Add to these. */
async function pickZip(name = 'sprites.zip') {
  await chooseZip(name);
  if (button('Add to these')) await click('Add to these');
}

it('counts distinct expressions toward 40, not alternates or looks', async () => {
  await mount();
  expect(container.textContent).toContain('2/40 expressions · 3 images');
});

it('imports a ZIP sprite pack through the host and says what happened', async () => {
  uploadReply = () =>
    Promise.resolve({
      avatars: [...avatars, item('e', 'joy'), item('f', 'cowgirl')],
      added: 2,
      skipped: 1,
      unrecognized: 1,
    });
  await mount();
  await pickZip();

  expect(uploads).toEqual(['/api/characters/c1/avatars/zip']);
  expect(container.textContent).toContain('Imported 2 · 1 skipped (40 expressions) · 1 unrecognized');
  expect(container.textContent).toContain('3/40 expressions · 5 images');
});

it("shows the host's reason when it refuses, and a plain failure otherwise", async () => {
  uploadReply = () => Promise.reject(new ApiError(400, "That file isn't a ZIP sprite pack."));
  await mount();
  await pickZip('notes.zip');
  expect(container.querySelector('.error')?.textContent).toBe("That file isn't a ZIP sprite pack.");

  uploadReply = () => Promise.reject(new ApiError(500, 'stack trace'));
  await pickZip();
  expect(container.querySelector('.error')?.textContent).toBe('Action failed.');
});

it('Select all, then Delete N: one confirm, one post with every id, and Undo posts its batch', async () => {
  postReply = (path) =>
    Promise.resolve(
      path.endsWith('/avatars/delete')
        ? { avatars: [], undo: { batch: 'b1', count: 4, replaced: 0, seconds: 10 } }
        : { avatars },
    );
  await mount();
  await click('Select');
  await click('Select all');
  expect(container.textContent).toContain('4 selected');
  await click('Delete 4');
  expect(container.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('Delete 4 images?');

  const confirm = [...container.querySelectorAll('[role="dialog"] button')].find(
    (b) => b.textContent === 'Delete 4',
  ) as HTMLButtonElement;
  act(() => {
    confirm.click();
    confirm.click();
  });
  await settle();
  const deletes = posts.filter((p) => p.path === '/api/characters/c1/avatars/delete');
  expect(deletes).toHaveLength(1);
  expect(deletes[0].body).toEqual({ ids: ['a', 'b', 'c', 'd'] });
  expect(container.textContent).toContain('Deleted 4 images');

  await click('Undo');
  expect(posts.at(-1)).toEqual({ path: '/api/characters/c1/avatars/undo', body: { batch: 'b1' } });
});

it('Select every “joy” picks the alternates of the last emotion tapped', async () => {
  await mount();
  await click('Select');
  const joy = container.querySelector<HTMLElement>('[aria-label="Select joy"]')!;
  act(() => joy.click());
  await settle();
  await click('Select every “joy”');
  expect(container.textContent).toContain('2 selected');
});

it('with expressions here, a ZIP asks Add or Replace; Replace sends replace=1', async () => {
  uploadReply = () =>
    Promise.resolve({
      avatars: [item('e', 'joy')],
      added: 1,
      skipped: 0,
      unrecognized: 0,
      undo: { batch: 'b2', count: 3, replaced: 1, seconds: 10 },
    });
  await mount();
  await chooseZip('pack.zip');
  expect(uploads).toEqual([]);
  await click('Replace them');
  expect(uploads).toEqual(['/api/characters/c1/avatars/zip?replace=1']);
  expect(container.textContent).toContain('Replaced 3 expression images with 1 from the pack');
});

it('the single 🗑 asks first, and Cancel deletes nothing', async () => {
  await mount();
  const trash = container.querySelector<HTMLButtonElement>('button[title="Delete"]')!;
  act(() => trash.click());
  await settle();
  expect(container.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('Delete this image?');
  await click('Cancel');
  expect(posts.filter((p) => p.path.includes('delete'))).toEqual([]);
});
