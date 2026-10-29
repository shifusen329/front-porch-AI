// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Narrate All on the phone, end to end against the real app: switch
// text-to-speech on and pick your own voice in Settings → Voice & Media,
// chat a line, then Chat tools → Narration reads the chat on this device,
// asking the host for each line in its own voice (yours in yours). The host
// speaks through a loopback speech server the harness starts
// (integration_test/web_ui/browser_test.dart); text-to-speech is off in the
// sandbox otherwise, so this journey switches it back off.

import type { Page } from '@playwright/test';
import { expect, openRoute, SERIAL, test } from './support/fixtures';

const REPLY = process.env.FPAI_REPLY ?? '';
const LINE = 'I pull a rocking chair closer.';

const rows = (page: Page) => page.locator('.chat-messages .msg-row');

async function waitIdle(page: Page) {
  await expect(page.locator('.chat-input button.primary', { hasText: 'Send' })).toBeVisible({ timeout: 60_000 });
  await expect
    .poll(async () => {
      const s = (await (await page.request.get('/api/chat/state')).json()) as {
        isGenerating: boolean;
        isSettlingTurn?: boolean;
      };
      return !s.isGenerating && !s.isSettlingTurn;
    }, { timeout: 60_000 })
    .toBe(true);
}

async function voiceSettings(page: Page) {
  await openRoute(page, '/settings');
  const card = page.locator('[data-section="voice-media"]');
  await expect(card.getByTestId('user-voice')).toBeVisible();
  return card;
}

test.describe.serial('Narration', { tag: SERIAL }, () => {
  test.afterEach(async ({ page }) => {
    await page.request.post('/api/voice/settings', { data: { ttsEnabled: false, userVoice: '' } });
  });

  test('narrate the chat on this device, your line in your voice', async ({ page }) => {
    // Text-to-speech on, and your own voice picked from the server's list.
    const card = await voiceSettings(page);
    // The box follows the host's answer, so click and wait for it.
    const ttsOn = card.getByLabel('Enable text-to-speech');
    await ttsOn.click();
    await expect(ttsOn).toBeChecked();
    await card.getByTestId('user-voice').selectOption('me');
    await expect(card.getByTestId('user-voice')).toHaveValue('me');

    // A fresh chat with one line of yours and the reply.
    await openRoute(page, '/');
    await page.locator('.lib-card', { hasText: 'Porch Tester' }).locator('.lib-open').click();
    await expect(page.locator('.chat-view')).toBeVisible();
    await waitIdle(page);
    await page.locator('.conversations-btn').click();
    await page.getByRole('button', { name: '+ New chat' }).click();
    await waitIdle(page);
    const box = page.locator('textarea.composer-input');
    await box.fill(LINE);
    await box.press('Enter');
    await expect(rows(page).filter({ hasText: LINE })).toHaveCount(1);
    await waitIdle(page);
    await expect(rows(page).last().locator('.bubble.ai')).toContainText(REPLY);

    // Your own line has Speak too, in your voice.
    const asked: { text: string; voiceKey?: string }[] = [];
    page.on('request', (r) => {
      if (r.method() === 'POST' && new URL(r.url()).pathname === '/api/tts/speak') {
        asked.push(r.postDataJSON() as { text: string; voiceKey?: string });
      }
    });
    await expect(
      rows(page).filter({ hasText: LINE }).locator('button[aria-label="Speak this message"]'),
    ).toBeVisible();

    // Chat tools → Narration → Narrate: every line, in order, yours in yours.
    const section = page.getByTestId('chat-narration');
    if (!(await section.isVisible())) await page.locator('.stats-btn').click();
    await section.locator('summary').click();
    await section.getByTestId('narration-narrate').click();
    await expect.poll(() => asked.length, { timeout: 30_000 }).toBeGreaterThanOrEqual(3);
    await expect(section.getByTestId('narration-narrate')).toBeVisible({ timeout: 30_000 });
    await expect(section.getByRole('alert')).toHaveCount(0);

    const mine = asked.filter((a) => a.text === LINE);
    expect(mine).toEqual([{ text: LINE, voiceKey: 'me' }]);
    const reply = asked.find((a) => a.text.includes(REPLY));
    expect(reply?.voiceKey).toBeUndefined();
    expect(asked.findIndex((a) => a.text === LINE)).toBeLessThan(asked.indexOf(reply!));
  });
});
