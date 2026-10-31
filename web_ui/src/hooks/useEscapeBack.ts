// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Escape is the back key, as in the desktop app. Sheets, pickers and fields
// that handle Escape themselves get the key first; what is left: a text box
// with the cursor lets go of it, then a sheet, drawer or menu still open
// closes as a tap outside it would, then the screen goes back (through the
// unsaved-changes blocker, like the browser's back).

import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';

const OVERLAY = [
  '.drawer-backdrop',
  '.fp-sheet',
  '.chance-overlay',
  '.msg-edit-overlay',
  '[role="dialog"]',
  '[aria-modal="true"]',
  '[role="menu"]',
  '[role="listbox"]',
].join(', ');

const CLOSE_TEXT = new Set(['Close', '✕', '×']);

function topOverlay(): Element | null {
  const open = document.querySelectorAll(OVERLAY);
  return open.length ? open[open.length - 1] : null;
}

function typingIn(el: Element | null): HTMLElement | null {
  if (!(el instanceof HTMLElement)) return null;
  if (el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) return el;
  if (el instanceof HTMLInputElement) {
    return ['button', 'checkbox', 'radio', 'range', 'submit', 'reset', 'color', 'file'].includes(el.type)
      ? null
      : el;
  }
  return el.isContentEditable ? el : null;
}

/** What a tap outside would do: the backdrop's click, else its Close button. */
function dismiss(open: Element): void {
  const backdrop = open.closest('.drawer-backdrop');
  if (backdrop instanceof HTMLElement) {
    backdrop.click();
    return;
  }
  const root = open.closest('[role="dialog"], [aria-modal="true"], .fp-sheet') ?? open;
  const close = [...root.querySelectorAll('button')].find(
    (b) => /^close/i.test(b.getAttribute('aria-label') ?? '') || CLOSE_TEXT.has(b.textContent?.trim() ?? ''),
  );
  close?.click();
}

/** The router's place in this tab's history; 0 is where the app was opened. */
function canGoBack(): boolean {
  const state = window.history.state as { idx?: unknown } | null;
  return typeof state?.idx === 'number' && state.idx > 0;
}

export function useEscapeBack(): void {
  const navigate = useNavigate();
  useEffect(() => {
    // Capture, so the screen is read as it was before any handler ran.
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape' || e.isComposing || e.repeat) return;
      const open = topOverlay();
      const typing = typingIn(document.activeElement);
      window.setTimeout(() => {
        if (e.defaultPrevented) return;
        if (typing) {
          typing.blur();
        } else if (open) {
          if (open.isConnected) dismiss(open);
        } else if (canGoBack()) {
          void navigate(-1);
        }
      }, 0);
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [navigate]);
}
