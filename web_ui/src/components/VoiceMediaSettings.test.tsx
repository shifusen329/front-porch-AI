// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Voice & Media card's Refresh voices button reads the voices an
// OpenAI-compatible server publishes, through the desktop. It shows only when
// the desktop says the server can list them. Desktop twin: the Refresh test in
// test/ui/dialogs/tts_settings_dialog_interaction_test.dart; the relay route
// is pinned in test/services/tts/openai_voice_list_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posted: string[] = [];
let status: Record<string, unknown> = {};
let listAnswer: Record<string, unknown> = {};

vi.mock('../api/client', () => ({
  api: {
    get: () => Promise.resolve(status),
    post: (path: string) => {
      posted.push(path);
      return Promise.resolve(path === '/api/voice/list-voices' ? listAnswer : status);
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
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

async function settle() {
  await act(async () => {
    await Promise.resolve();
    await Promise.resolve();
  });
}

async function show() {
  act(() => root.render(createElement(VoiceMediaSettings)));
  await settle();
}

function refreshButton() {
  return [...container.querySelectorAll('button')].find((b) =>
    b.textContent?.includes('Refresh voices'),
  );
}

it('reads the server voices once and says how many came back', async () => {
  status = { ttsEnabled: true, sttAvailable: false, ttsEngine: 'openai', listsVoices: true };
  listAnswer = { ...status, found: 33 };
  await show();

  const button = refreshButton()!;
  act(() => {
    button.click();
    button.click();
  });
  await settle();

  expect(posted).toEqual(['/api/voice/list-voices']);
  expect(container.textContent).toContain('Found 33 voices on the server.');
});

it('says so when the server sends no list', async () => {
  status = { ttsEnabled: true, sttAvailable: false, ttsEngine: 'openai', listsVoices: true };
  listAnswer = { ...status, found: null };
  await show();

  act(() => refreshButton()!.click());
  await settle();

  expect(container.textContent).toContain('The server sent no voice list.');
});

it('offers no refresh when the engine cannot list voices', async () => {
  status = { ttsEnabled: true, sttAvailable: false, ttsEngine: 'kokoro', listsVoices: false };
  await show();

  expect(refreshButton()).toBeUndefined();
});
