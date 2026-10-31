// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Advanced → Debug log on the phone: the host's switch, View,
// Download a copy (once, however fast it is tapped) and Clear, as the
// desktop's Troubleshooting card has them.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posted: { path: string; body: unknown }[] = [];
const fetched: string[] = [];
const downloads: string[] = [];
let status: Record<string, unknown> = {};
let logText = '';

vi.mock('../api/client', () => ({
  ApiError: class extends Error {},
  api: {
    get: () => Promise.resolve(status),
    post: (path: string, body: unknown) => {
      posted.push({ path, body });
      if (path === '/api/debug-log/clear') {
        logText = '==== log cleared ====\n';
        status = { ...status, bytes: logText.length };
      } else {
        const enabled = (body as { enabled: boolean }).enabled;
        if (enabled && logText === '') logText = '==== debug log turned on ====\n';
        status = { ...status, enabled, bytes: logText.length };
      }
      return Promise.resolve(status);
    },
    getForBlob: (path: string) => {
      fetched.push(path);
      return Promise.resolve(new Blob([logText], { type: 'text/plain' }));
    },
  },
}));

vi.mock('../pages/story/storyUtil', () => ({
  downloadBlob: (_blob: Blob, name: string) => downloads.push(name),
}));

const { DebugLogSettings, debugLogTail, DEBUG_LOG_VIEW_CHARS } = await import('./DebugLogSettings');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  posted.length = 0;
  fetched.length = 0;
  downloads.length = 0;
  logText = '';
  status = { enabled: false, bytes: 0, fileName: 'front_porch.log', problem: null };
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const q = <T extends HTMLElement>(id: string) => container.querySelector<T>(`[data-testid="${id}"]`)!;

async function open() {
  await act(async () => {
    root.render(createElement(DebugLogSettings));
  });
}

it('turns the host log on once and wakes the buttons', async () => {
  await open();
  expect(q<HTMLInputElement>('debug-logging').checked).toBe(false);
  expect(q('debug-log-size').textContent).toBe('No log yet.');
  expect(q<HTMLButtonElement>('debug-log-download').disabled).toBe(true);

  await act(async () => q<HTMLInputElement>('debug-logging').click());

  expect(posted).toEqual([{ path: '/api/debug-log', body: { enabled: true } }]);
  expect(q<HTMLInputElement>('debug-logging').checked).toBe(true);
  expect(q('debug-log-size').textContent).toMatch(/^front_porch\.log · \d+ B$/);
  expect(q<HTMLButtonElement>('debug-log-download').disabled).toBe(false);
});

it('downloads one copy however fast it is tapped, named as the desktop names it', async () => {
  status = { ...status, enabled: true, bytes: 40 };
  logText = '2026-10-31 11:02:03.004  [Chat] the reply never came\n';
  await open();

  await act(async () => {
    q<HTMLButtonElement>('debug-log-download').click();
    q<HTMLButtonElement>('debug-log-download').click();
  });

  expect(fetched).toEqual(['/api/debug-log/file']);
  expect(downloads).toHaveLength(1);
  expect(downloads[0]).toMatch(/^front-porch-log-\d{4}-\d{2}-\d{2}-\d{4}\.txt$/);
});

it('View shows the log and Hide puts it away', async () => {
  status = { ...status, enabled: true, bytes: 40 };
  logText = '2026-10-31 11:02:03.004  [TTS] the voice server said no\n';
  await open();

  await act(async () => q<HTMLButtonElement>('debug-log-view').click());
  expect(q('debug-log-text').textContent).toContain('[TTS] the voice server said no');
  expect(q('debug-log-view').textContent).toBe('Hide');

  await act(async () => q<HTMLButtonElement>('debug-log-view').click());
  expect(container.querySelector('[data-testid="debug-log-text"]')).toBeNull();
});

it('Clear asks the host to clear the log', async () => {
  status = { ...status, enabled: true, bytes: 40 };
  logText = 'old lines\n';
  await open();

  await act(async () => q<HTMLButtonElement>('debug-log-clear').click());

  expect(posted).toEqual([{ path: '/api/debug-log/clear', body: undefined }]);
});

it('the viewer keeps the newest part, from the start of a line', () => {
  const line = 'x'.repeat(99) + '\n';
  const log = line.repeat(Math.ceil(DEBUG_LOG_VIEW_CHARS / line.length) + 5);
  const tail = debugLogTail(log);
  expect(tail.length).toBeLessThanOrEqual(DEBUG_LOG_VIEW_CHARS);
  expect(tail.startsWith('x')).toBe(true);
  expect(log.endsWith(tail)).toBe(true);
  expect(debugLogTail('short\n')).toBe('short\n');
});
