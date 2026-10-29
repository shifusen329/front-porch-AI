// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Voice & Media on the phone: Speak my messages, Your voice and
// Narrator voice, as the desktop's TTS settings have them. Each change is
// sent to the host; '' is the global voice, named as such.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posted: { path: string; body: unknown }[] = [];
let status: Record<string, unknown> = {};

vi.mock('../api/client', () => ({
  api: {
    get: () => Promise.resolve(status),
    post: (path: string, body: unknown) => {
      posted.push({ path, body });
      // The host keeps what it was sent, as /api/voice/settings does.
      status = { ...status, ...(body as object) };
      return Promise.resolve(status);
    },
  },
}));

const { VoiceMediaSettings } = await import('./VoiceMediaSettings');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  posted.length = 0;
  status = {
    ttsEnabled: true,
    sttAvailable: false,
    globalVoice: 'aisha',
    voices: [
      { id: 'aisha', name: 'Aisha' },
      { id: 'me', name: 'Me' },
      { id: 'teller', name: 'Teller' },
    ],
    userVoice: '',
    narratorVoice: '',
    ttsAutoPlayUser: false,
  };
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const q = <T extends HTMLElement>(id: string) => container.querySelector<T>(`[data-testid="${id}"]`)!;

async function choose(id: string, value: string) {
  await act(async () => {
    const select = q<HTMLSelectElement>(id);
    select.value = value;
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

it('sends Speak my messages and each voice, and names the global voice', async () => {
  await act(async () => {
    root.render(createElement(VoiceMediaSettings));
  });

  expect(q<HTMLSelectElement>('user-voice').options[0].textContent).toBe('Use the global voice (Aisha)');
  expect(q<HTMLInputElement>('speak-my-messages').checked).toBe(false);

  await act(async () => q<HTMLInputElement>('speak-my-messages').click());
  await choose('user-voice', 'me');
  await choose('narrator-voice', 'teller');

  expect(posted).toEqual([
    { path: '/api/voice/settings', body: { ttsAutoPlayUser: true } },
    { path: '/api/voice/settings', body: { userVoice: 'me' } },
    { path: '/api/voice/settings', body: { narratorVoice: 'teller' } },
  ]);
  expect(q<HTMLInputElement>('speak-my-messages').checked).toBe(true);
});

it('a voice this engine does not list is still shown', async () => {
  status = { ...status, userVoice: 'en_US-lessac-medium' };
  await act(async () => {
    root.render(createElement(VoiceMediaSettings));
  });
  expect(q<HTMLSelectElement>('user-voice').value).toBe('en_US-lessac-medium');
  expect(container.textContent).toContain('not available on this engine');
});
