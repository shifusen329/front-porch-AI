// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Speak on the phone: when the host has no audio for a message — its speech
// server refused the model, say — the host's reason shows beside the
// button instead of the tap doing nothing, and the next tap clears it.
// Renders the real button; the host's answers are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { postForBlob } = vi.hoisted(() => ({ postForBlob: vi.fn() }));
vi.mock('../api/client', () => {
  class ApiError extends Error {
    status: number;
    constructor(status: number, message: string) {
      super(message);
      this.status = status;
    }
  }
  return { api: { postForBlob }, ApiError };
});

import { ApiError } from '../api/client';
import { SpeakButton } from './VoiceControls';

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  postForBlob.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const tap = async () => {
  await act(async () => {
    container.querySelector<HTMLButtonElement>('button')!.click();
  });
};

describe('Speak', () => {
  it('shows why there is no audio, and clears it on the next tap', async () => {
    const reason =
      "Text-to-speech failed. 192.168.0.100:8006 answered 400: Unsupported model 'tts-1'. Supported: omnivoice.";
    postForBlob.mockRejectedValueOnce(new (ApiError as unknown as new (s: number, m: string) => Error)(503, reason));
    await act(async () => {
      root.render(createElement(SpeakButton, { text: 'Hello there.' }));
    });

    await tap();

    expect(postForBlob).toHaveBeenCalledWith('/api/tts/speak', { text: 'Hello there.' });
    expect(container.querySelector('[role="alert"]')?.textContent).toBe(reason);

    postForBlob.mockReturnValueOnce(new Promise(() => {}));
    await tap();
    expect(container.querySelector('[role="alert"]')).toBeNull();
  });
});
