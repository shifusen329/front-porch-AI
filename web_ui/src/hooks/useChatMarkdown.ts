// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Show markdown formatting in messages, shared by
// every message on screen. Read from /api/settings when the first message
// mounts (so a change made on the desktop shows on the next chat), and set
// at once by the Settings switch.

import { useEffect, useSyncExternalStore } from 'react';
import { api } from '../api/client';

let on = true;
const listeners = new Set<() => void>();

export function setChatMarkdown(next: boolean): void {
  if (next === on) return;
  on = next;
  listeners.forEach((l) => l());
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function load(): void {
  api
    .get<{ chatMarkdown?: boolean }>('/api/settings')
    .then((r) => {
      if (typeof r?.chatMarkdown === 'boolean') setChatMarkdown(r.chatMarkdown);
    })
    .catch(() => {
      /* keep the last known value */
    });
}

const snapshot = () => on;
let mounted = 0;

export function useChatMarkdown(): boolean {
  useEffect(() => {
    if (mounted++ === 0) load();
    return () => {
      mounted--;
    };
  }, []);
  return useSyncExternalStore(subscribe, snapshot, snapshot);
}
