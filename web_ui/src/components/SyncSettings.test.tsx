// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone web app's Settings → Sync card drives the desktop's library sync.
// Desktop twin: test/ui/settings/sync_tab_test.dart; the routes are pinned in
// test/services/web/sync_routes_test.dart over real HTTP.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { SyncStatus } from './SyncSettings';

const posts: { path: string; body: Record<string, unknown> }[] = [];
let status: SyncStatus;
let failGets = false;

vi.mock('../api/client', () => {
  class ApiError extends Error {}
  return {
    ApiError,
    api: {
      get: (path: string) => {
        if (path === '/api/auth/state') return Promise.resolve({ totpEnabled: false });
        if (failGets) return Promise.reject(new Error('server restarting'));
        return Promise.resolve(structuredClone(status));
      },
      post: (path: string, body: Record<string, unknown>) => {
        posts.push({ path, body });
        if (path === '/api/sync/test') return Promise.resolve({ ok: true, message: 'Connected.' });
        if (path === '/api/sync/send' || path === '/api/sync/get') {
          return Promise.resolve({ started: true });
        }
        return Promise.resolve(structuredClone(status));
      },
    },
  };
});

const { SyncSettings } = await import('./SyncSettings');

function base(): SyncStatus {
  return {
    disabled: false,
    configured: true,
    place: {
      kind: 'webdav',
      serverUrl: 'https://cloud.example.com/remote.php/dav/files/me/',
      username: 'me',
      folderName: 'Front Porch AI Sync',
      folderPath: '',
      passwordSaved: true,
    },
    deviceName: '',
    deviceNameShown: 'PORCH-PC',
    sendOnClose: false,
    checkOnStart: false,
    remote: {
      id: 's2',
      device: 'Phone',
      when: '21:40',
      summary: '12 characters · 340 chats · 1.2 GB',
      newer: true,
      earlier: [{ id: 's1', device: 'PORCH-PC', when: '2026-10-28 20:00' }],
    },
    remoteError: null,
    lastSync: { sent: true, when: '2026-10-28 20:00', device: 'PORCH-PC' },
    here: 'Nothing changed here.',
    undo: null,
    phase: 'idle',
    progress: { done: 0, total: 0 },
    needsRestart: null,
    outcome: null,
  };
}

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  posts.length = 0;
  status = base();
  failGets = false;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

async function settle(rounds = 4) {
  for (let i = 0; i < rounds; i++) {
    await act(async () => {
      await Promise.resolve();
    });
  }
}

async function render(pollMs = 5) {
  await act(async () => {
    root.render(createElement(SyncSettings, { pollMs }));
  });
  await settle();
}

const button = (name: string) =>
  [...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === name);
const wait = (ms: number) => act(() => new Promise((r) => setTimeout(r, ms)));

it('shows what is on the sync place and the earlier versions', async () => {
  await render();
  const text = container.textContent ?? '';
  expect(text).toContain("On the sync place: Phone's library, 21:40 · 12 characters · 340 chats · 1.2 GB");
  expect(text).toContain('newer than the desktop');
  expect(text).toContain('Sent 2026-10-28 20:00.');
  expect(text).toContain('Earlier versions on the sync place');
  expect(button('Get this one')).toBeTruthy();
});

it('a double tap on Send my library starts one send', async () => {
  await render();
  const send = button('Send my library')!;
  await act(async () => {
    send.click();
    send.click();
  });
  await settle();
  expect(posts.filter((p) => p.path === '/api/sync/send')).toHaveLength(1);
});

it('a send that meets a newer library asks: Get theirs first or Send mine anyway', async () => {
  status.outcome = {
    kind: 'sendConflict',
    otherLibrary: false,
    message: "Phone sent a library that this device hasn't got.",
    theirs: { id: 's2', device: 'Phone', when: '21:40' },
  };
  await render();
  expect(container.textContent).toContain("Phone sent a library that this device hasn't got.");
  await act(async () => button('Send mine anyway')!.click());
  await settle();
  expect(posts.at(-1)).toEqual({ path: '/api/sync/send', body: { overwrite: true } });
});

it('a Get with changes here asks Keep mine / Take theirs, then reloads once it is done', async () => {
  const reload = vi.fn();
  vi.spyOn(window, 'location', 'get').mockReturnValue({ ...window.location, reload });
  status.outcome = {
    kind: 'getReady',
    conflicts: true,
    summary: "Phone's library from 21:40: 12 characters · 340 chats · 1.2 GB.",
    changes: 'Changed here since the last sync: 1 chat (Porch night).',
  };
  await render();
  expect(container.textContent).toContain('Changed here since the last sync: 1 chat (Porch night).');
  expect(button('Keep mine')).toBeTruthy();

  status.phase = 'replacing';
  status.outcome = null;
  await act(async () => button('Take theirs')!.click());
  await settle();
  expect(posts.at(-1)?.path).toBe('/api/sync/get/apply');

  // The desktop's server restarts while the library is swapped.
  failGets = true;
  await wait(20);
  expect(container.textContent).toContain('Reconnecting to the desktop…');
  failGets = false;
  status.phase = 'idle';
  status.outcome = { kind: 'done', message: "Got Phone's library from 21:40." };
  await wait(20);
  await settle();
  expect(reload).toHaveBeenCalledTimes(1);
});

it('saving a new sync password asks for the web password first', async () => {
  await render();
  const field = container.querySelector<HTMLInputElement>('input[type="password"]')!;
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(field, 'new-app-password');
    field.dispatchEvent(new Event('input', { bubbles: true }));
  });
  expect(container.textContent).toContain('Saving a sync password needs your web login password.');
  expect(button('Save and test connection')!.disabled).toBe(true);
});
