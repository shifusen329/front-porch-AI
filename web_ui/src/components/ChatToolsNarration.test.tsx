// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Narrate All in the web chat tools: the host's lines play on this device in
// order, each asked for in its own voice, the next fetched while one plays;
// Starting at asks from that message; Stop ends it; a refusal is shown.
// Renders the real section and hook; the host's answers and the device's
// audio are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, postForBlob } = vi.hoisted(() => ({ get: vi.fn(), postForBlob: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, postForBlob } }));

import { ChatToolsNarration } from './ChatToolsNarration';

/** The device's speaker: each clip "plays" until the test ends it. */
class FakeAudio {
  static all: FakeAudio[] = [];
  onended: (() => void) | null = null;
  onerror: (() => void) | null = null;
  paused = false;
  constructor(public src: string) {
    FakeAudio.all.push(this);
  }
  play() {
    return Promise.resolve();
  }
  pause() {
    this.paused = true;
  }
}

const lines = [
  { number: 2, speaker: 'Wanderer', text: 'Mind if I sit?', voiceKey: 'me' },
  { number: 3, speaker: 'Riley', text: '"Pull up a chair."', voiceKey: null },
];

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  vi.stubGlobal('Audio', FakeAudio);
  URL.createObjectURL = vi.fn(() => 'blob:line');
  URL.revokeObjectURL = vi.fn();
  FakeAudio.all = [];
  get.mockReset();
  postForBlob.mockReset();
  get.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/voice/status' ? { ttsEnabled: true } : { lines }),
  );
  postForBlob.mockResolvedValue(new Blob(['wav']));
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

const q = (id: string) => container.querySelector<HTMLElement>(`[data-testid="${id}"]`);
const status = () => container.querySelector('[role="status"]')?.textContent ?? '';
const flush = () => act(async () => {});

async function open() {
  await act(async () => {
    root.render(createElement(ChatToolsNarration));
  });
}

async function endClip(i: number) {
  await act(async () => {
    FakeAudio.all[i].onended?.();
  });
  await flush();
}

describe('Narration', () => {
  it('is not offered while text-to-speech is off', async () => {
    get.mockResolvedValue({ ttsEnabled: false });
    await open();
    expect(q('chat-narration')).toBeNull();
  });

  it('reads the lines in order, each in its own voice', async () => {
    await open();
    await act(async () => q('narration-narrate')!.click());
    await flush();

    expect(get).toHaveBeenCalledWith('/api/chat/narration?from=1');
    expect(postForBlob).toHaveBeenNthCalledWith(1, '/api/tts/speak', { text: 'Mind if I sit?', voiceKey: 'me' });
    expect(postForBlob).toHaveBeenNthCalledWith(2, '/api/tts/speak', { text: '"Pull up a chair."' });
    expect(status()).toBe('Narrating 1 of 2 · #2 Wanderer');

    await endClip(0);
    expect(status()).toBe('Narrating 2 of 2 · #3 Riley');
    await endClip(1);
    expect(q('narration-narrate')).not.toBeNull();
    expect(postForBlob).toHaveBeenCalledTimes(2);
  });

  it('Starting at asks from that message', async () => {
    await open();
    await act(async () => q('narration-start-at')!.click());
    const box = q('narration-from') as HTMLInputElement;
    await act(async () => {
      const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      set.call(box, '3');
      box.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await act(async () => q('narration-narrate')!.click());
    await flush();
    expect(get).toHaveBeenCalledWith('/api/chat/narration?from=3');
  });

  it('Stop ends it and silences the line', async () => {
    await open();
    await act(async () => q('narration-narrate')!.click());
    await flush();

    await act(async () => q('narration-stop')!.click());
    await flush();
    expect(FakeAudio.all[0].paused).toBe(true);
    expect(q('narration-narrate')).not.toBeNull();
    await endClip(0);
    expect(FakeAudio.all).toHaveLength(1);
  });

  it('a line the host refuses is shown, and the narration stops', async () => {
    postForBlob.mockRejectedValue(new Error("Voice 'me' not found."));
    await open();
    await act(async () => q('narration-narrate')!.click());
    await flush();
    expect(container.querySelector('[role="alert"]')?.textContent).toBe("Voice 'me' not found.");
    expect(q('narration-narrate')).not.toBeNull();
    expect(FakeAudio.all).toHaveLength(0);
  });
});
