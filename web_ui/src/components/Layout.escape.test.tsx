// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Escape is the back key, as in the desktop app: a text box lets go of the
// cursor, a sheet or drawer still open closes, then the screen goes back.
// The real Layout over a real hash router in this tab's history.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { useState } from 'react';
import { createHashRouter, Link, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Layout } from './Layout';

vi.mock('../auth/AuthContext', () => ({ useAuth: () => ({ setAuthenticated: () => {} }) }));

/** A sheet that closes only on a tap outside it. */
function Sheet({ onClose }: { onClose: () => void }) {
  return (
    <div className="drawer-backdrop" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal" role="dialog" aria-label="Pick a voice">
        <p>Voices</p>
      </div>
    </div>
  );
}

/** A menu that closes itself on Escape, as the card menu does. */
function SelfClosingMenu({ onClose }: { onClose: () => void }) {
  return (
    <div role="menu" aria-label="Card menu" tabIndex={-1}
      onKeyDown={(e) => e.key === 'Escape' && onClose()}>
      <button type="button" role="menuitem">Rename</button>
    </div>
  );
}

function Settings() {
  const [sheet, setSheet] = useState(false);
  const [menu, setMenu] = useState(false);
  return (
    <div>
      <h1>Settings page</h1>
      <input aria-label="Search settings" defaultValue="voice" />
      {/* Like the composer closing its @-mention list. */}
      <input aria-label="Mention" defaultValue="@Ad"
        onKeyDown={(e) => e.key === 'Escape' && e.preventDefault()} />
      <button type="button" onClick={() => setSheet(true)}>Open sheet</button>
      <button type="button" onClick={() => setMenu(true)}>Open menu</button>
      {sheet ? <Sheet onClose={() => setSheet(false)} /> : null}
      {menu ? <SelfClosingMenu onClose={() => setMenu(false)} /> : null}
    </div>
  );
}

function Home() {
  return (
    <div>
      <h1>Home page</h1>
      <Link to="/settings">Settings link</Link>
    </div>
  );
}

let container: HTMLDivElement;
let root: Root;
const width = window.innerWidth;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  window.history.replaceState(null, '', '/');
  window.location.hash = '';
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: width });
  vi.restoreAllMocks();
});

async function renderApp() {
  const router = createHashRouter([
    { path: '/', element: <Layout><Home /></Layout> },
    { path: '/settings', element: <Layout><Settings /></Layout> },
  ]);
  await act(async () => root.render(<RouterProvider router={router} />));
}

const heading = () => container.querySelector('h1')?.textContent;

function byText(label: string): HTMLElement {
  return [...container.querySelectorAll<HTMLElement>('a,button')].find(
    (e) => e.textContent === label,
  )!;
}

async function click(el: Element) {
  await act(async () => {
    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, button: 0 }));
  });
}

/** Escape from [target], then long enough for what it does to land. */
async function escape(target: Element = document.activeElement ?? document.body) {
  await act(async () => {
    target.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
  });
  for (let i = 0; i < 5; i++) {
    await act(async () => {
      await new Promise((r) => setTimeout(r, 10));
    });
  }
}

async function until(check: () => boolean) {
  for (let i = 0; i < 100 && !check(); i++) {
    await act(async () => {
      await new Promise((r) => setTimeout(r, 10));
    });
  }
  expect(check()).toBe(true);
}

async function openSettings() {
  await click(byText('Settings link'));
  expect(heading()).toBe('Settings page');
}

describe('Escape goes back', () => {
  it('goes back to the screen before', async () => {
    await renderApp();
    await openSettings();

    await escape(document.body);
    await until(() => heading() === 'Home page');
  });

  it('never leaves the app from the screen it opened on', async () => {
    const back = vi.spyOn(window.history, 'back');
    const go = vi.spyOn(window.history, 'go');
    await renderApp();

    await escape(document.body);
    expect(heading()).toBe('Home page');
    expect(back).not.toHaveBeenCalled();
    expect(go).not.toHaveBeenCalled();
  });

  it('lets go of a text box first', async () => {
    await renderApp();
    await openSettings();
    const field = container.querySelector<HTMLInputElement>('input[aria-label="Search settings"]')!;
    field.focus();
    expect(document.activeElement).toBe(field);

    await escape(field);
    expect(document.activeElement).not.toBe(field);
    expect(heading()).toBe('Settings page');

    await escape(document.body);
    await until(() => heading() === 'Home page');
  });

  it('leaves a box that used Escape itself alone', async () => {
    await renderApp();
    await openSettings();
    const field = container.querySelector<HTMLInputElement>('input[aria-label="Mention"]')!;
    field.focus();

    await escape(field);
    expect(document.activeElement).toBe(field);
    expect(heading()).toBe('Settings page');
  });

  it('closes a sheet that has no Escape of its own, and stays', async () => {
    await renderApp();
    await openSettings();
    await click(byText('Open sheet'));
    expect(container.querySelector('[role="dialog"]')).not.toBeNull();

    await escape(document.body);
    expect(container.querySelector('[role="dialog"]')).toBeNull();
    expect(heading()).toBe('Settings page');
  });

  it('a menu that closes itself on Escape costs one Escape, not two', async () => {
    await renderApp();
    await openSettings();
    await click(byText('Open menu'));
    const menu = container.querySelector('[role="menu"]')!;

    await escape(menu);
    expect(container.querySelector('[role="menu"]')).toBeNull();
    expect(heading()).toBe('Settings page');
  });

  it('the phone menu drawer closes on Escape', async () => {
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 390 });
    await renderApp();
    await click(container.querySelector('[aria-label="Open menu"]')!);
    expect(container.querySelector('[aria-label="Close menu"]')).not.toBeNull();

    await escape(document.body);
    expect(container.querySelector('[aria-label="Close menu"]')).toBeNull();
    expect(heading()).toBe('Home page');
  });
});
