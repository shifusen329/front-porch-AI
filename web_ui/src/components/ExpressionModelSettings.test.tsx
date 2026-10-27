// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web Voice & Media card sets the Local ONNX expression classifier's
// Hugging Face model. Desktop twin: the model field test in
// test/ui/settings/voice_media_tab_interaction_test.dart; the relay is pinned
// in test/services/web/voice_facade_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useState } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posted: unknown[] = [];
let answer: () => Promise<unknown> = () => Promise.resolve({});

vi.mock('../api/client', () => {
  class ApiError extends Error {}
  return {
    ApiError,
    api: {
      post: (_path: string, body: unknown) => {
        posted.push(body);
        return answer();
      },
    },
  };
});

const { ApiError } = await import('../api/client');
const { ExpressionModelSettings } = await import('./ExpressionModelSettings');

type Status = { expressionModel?: string; expressionModelLabels?: string[] | null };

function Card({ initial }: { initial: Status }) {
  const [status, setStatus] = useState(initial);
  return createElement(ExpressionModelSettings<Status>, { status, onSaved: setStatus });
}

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

function typeInto(input: HTMLInputElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

const button = (text: string) =>
  [...container.querySelectorAll('button')].find((b) => b.textContent === text)!;

it('sends the model once per double click and shows its own labels', async () => {
  answer = () =>
    Promise.resolve({
      expressionModel: 'Shifusen/distilbert-go_emotions-nsfw',
      expressionModelLabels: ['joy', 'neutral', 'cowgirl', 'paizuri'],
    });
  act(() => root.render(createElement(Card, { initial: { expressionModelLabels: null } })));
  const input = container.querySelector<HTMLInputElement>('input[aria-label="Expression model"]')!;

  typeInto(input, 'https://huggingface.co/Shifusen/distilbert-go_emotions-nsfw');
  act(() => {
    button('Use').click();
    button('Use').click();
  });
  await settle();

  expect(posted).toEqual([
    { expressionModel: 'https://huggingface.co/Shifusen/distilbert-go_emotions-nsfw' },
  ]);
  expect(input.value).toBe('Shifusen/distilbert-go_emotions-nsfw');
  expect(container.textContent).toContain('Its own, for tagging images: cowgirl, paizuri');
});

it('shows the desktop\'s refusal of a model id', async () => {
  answer = () => Promise.reject(new ApiError('not a Hugging Face model id'));
  act(() => root.render(createElement(Card, { initial: { expressionModel: 'Cohee/x' } })));

  act(() => button('Use').click());
  await settle();

  expect(container.textContent).toContain('not a Hugging Face model id');
});
