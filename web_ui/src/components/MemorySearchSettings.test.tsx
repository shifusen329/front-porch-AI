// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Memory search on the phone: a saved server's embedding models fill the
// dropdown on open, picking one saves it, a typed URL is saved and listed
// with one request however fast Load is tapped, a server that cannot be
// listed says so, stored vectors from another model are flagged, and Clear
// and re-vectorize asks first, then shows progress until it is done.
// Renders the real component; the host's answers are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post },
  ApiError: class ApiError extends Error {},
}));

import { MemorySearchSettings, type MemorySearchSnapshot } from './MemorySearchSettings';

const SNOWFLAKE = 'snowflake-arctic-embed-l-v2.0:latest';
const NOMIC = 'nomic-embed-text-v1.5-F16:latest';

const snapshot = (over: Partial<MemorySearchSnapshot> = {}): MemorySearchSnapshot => ({
  provider: 'endpoint',
  endpointUrl: 'http://192.168.0.100:11434',
  endpointModel: SNOWFLAKE,
  hasApiKey: false,
  onDeviceModel: 'nomic-embed-text-v1.5',
  activeModel: `endpoint|${SNOWFLAKE}`,
  indexModel: `endpoint|${SNOWFLAKE}`,
  status: {
    available: true,
    configured: true,
    endpointHost: '192.168.0.100:11434',
    dimensions: 1024,
    indexMatches: true,
  },
  rebuild: { running: false, done: 0, total: 0, error: null, stored: 12, missing: 0 },
  ...over,
});

let container: HTMLDivElement;
let root: Root;

const $ = <T extends Element>(id: string) => container.querySelector<T>(`[data-testid="${id}"]`);

async function open(first: MemorySearchSnapshot, models: string[] = [NOMIC, SNOWFLAKE]) {
  get.mockResolvedValue(first);
  post.mockImplementation((path: string) =>
    Promise.resolve(path.endsWith('/models') ? { models } : first),
  );
  await act(async () => {
    root.render(createElement(MemorySearchSettings));
  });
}

async function type(el: HTMLInputElement, value: string) {
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(el: Element | null) {
  await act(async () => {
    (el as HTMLElement).click();
  });
}

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
  vi.useRealTimers();
});

describe('Memory search', () => {
  it('fills the dropdown with the saved server\'s models, and a pick is saved', async () => {
    await open(snapshot());
    const select = $<HTMLSelectElement>('memory-search-model')!;
    expect(Array.from(select.options).map((o) => o.value)).toEqual([NOMIC, SNOWFLAKE]);
    expect(select.value).toBe(SNOWFLAKE);
    expect($('memory-search-status')?.textContent).toContain('1024-dimension vectors');

    await act(async () => {
      select.value = NOMIC;
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(post).toHaveBeenCalledWith('/api/memory/embedding', {
      provider: 'endpoint',
      endpointModel: NOMIC,
    });
  });

  it('a typed server is saved and listed once however fast Load is tapped', async () => {
    await open(snapshot({ endpointUrl: '', endpointModel: '', status: { configured: false } }));
    expect(post).not.toHaveBeenCalled();
    await type($<HTMLInputElement>('memory-search-url')!, 'http://10.0.0.5:11434');

    const load = $('memory-search-load');
    await act(async () => {
      (load as HTMLElement).click();
      (load as HTMLElement).click();
    });

    const saves = post.mock.calls.filter(([path]) => path === '/api/memory/embedding');
    expect(saves).toEqual([
      ['/api/memory/embedding', { provider: 'endpoint', endpointUrl: 'http://10.0.0.5:11434' }],
    ]);
    expect(post.mock.calls.filter(([path]) => path.endsWith('/models'))).toHaveLength(1);
    expect(Array.from($<HTMLSelectElement>('memory-search-model')!.options).map((o) => o.value)).toContain(
      SNOWFLAKE,
    );
  });

  it('a server that cannot be listed says so', async () => {
    await open(snapshot({ endpointModel: '' }));
    post.mockImplementation((path: string) =>
      path.endsWith('/models') ? Promise.reject(new Error('down')) : Promise.resolve(snapshot()),
    );
    await click($('memory-search-load'));
    expect(container.querySelector('[role="alert"]')?.textContent).toContain('Could not list models');
  });

  it('flags vectors from another model, and re-vectorizes after asking', async () => {
    vi.useFakeTimers();
    await open(
      snapshot({
        indexModel: 'onDevice|nomic-embed-text-v1.5',
        status: { ...snapshot().status, indexMatches: false },
      }),
    );
    expect($('memory-search-mismatch')?.textContent).toContain('nomic-embed-text-v1.5');

    const running = snapshot({ rebuild: { running: true, done: 4, total: 12, stored: 12, missing: 8 } });
    post.mockResolvedValue(running);
    await click($('memory-search-rebuild'));
    expect(post).not.toHaveBeenCalledWith('/api/memory/embedding/rebuild', expect.anything());
    await click($('memory-search-rebuild-confirm'));
    expect(post).toHaveBeenCalledWith('/api/memory/embedding/rebuild', { mode: 'all' });
    expect(container.textContent).toContain('4 of 12');

    get.mockResolvedValue(snapshot());
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1600);
    });
    expect(container.textContent).not.toContain('4 of 12');
    expect($('memory-search-counts')?.textContent).toContain('12 saved memories');
  });
});
