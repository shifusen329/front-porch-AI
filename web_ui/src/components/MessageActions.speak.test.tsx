// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Speak on the phone follows the host's word on each message: the user's
// own lines and the narrator's get the button too, and the audio is asked
// for in the voice the desktop reads that message in.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { postForBlob } = vi.hoisted(() => ({ postForBlob: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get: vi.fn(), post: vi.fn(), postForBlob },
  ApiError: class extends Error {},
}));

import { MessageActions } from './MessageActions';
import { type Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

function render(m: Message) {
  act(() => {
    root.render(
      createElement(MessageActions, {
        m,
        isLast: false,
        busy: false,
        canSpeak: true,
        onSwipe: vi.fn(),
        onRegenerate: vi.fn(),
        onContinue: vi.fn(),
        onFork: vi.fn(),
        onEdit: vi.fn(),
        onDelete: vi.fn(),
      }),
    );
  });
}

const speak = () => container.querySelector<HTMLButtonElement>('button[aria-label="Speak this message"]');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  postForBlob.mockReset();
  postForBlob.mockReturnValue(new Promise(() => {}));
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Speak', () => {
  it('reads the user\'s own line, in the user\'s voice', async () => {
    render({ index: 1, text: 'Mind if I sit?', sender: 'Wanderer', isUser: true, speakable: true, voiceKey: 'me' });
    expect(speak()).not.toBeNull();
    await act(async () => speak()!.click());
    expect(postForBlob).toHaveBeenCalledWith('/api/tts/speak', { text: 'Mind if I sit?', voiceKey: 'me' });
  });

  it('leaves out a line the host says is not read', () => {
    render({ index: 0, text: 'Chat started.', sender: 'System', isUser: false, speakable: false });
    expect(speak()).toBeNull();
  });

  it('an older host that says nothing keeps the old rule: replies only', () => {
    render({ index: 1, text: 'Mind if I sit?', sender: 'Wanderer', isUser: true });
    expect(speak()).toBeNull();
    render({ index: 2, text: '"Sit."', sender: 'Riley', isUser: false });
    expect(speak()).not.toBeNull();
  });
});
