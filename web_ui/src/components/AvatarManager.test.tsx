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
let avatars: Item[] = [];
let uploadReply: () => Promise<unknown> = () => Promise.resolve({});

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
      post: () => Promise.resolve({ avatars }),
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

async function pickZip(name = 'sprites.zip') {
  const input = container.querySelector<HTMLInputElement>('input[accept=".zip,application/zip"]')!;
  Object.defineProperty(input, 'files', { value: [new File(['zip'], name)], configurable: true });
  act(() => void input.dispatchEvent(new Event('change', { bubbles: true })));
  await settle();
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
