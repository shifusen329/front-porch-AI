// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Sync on the phone web app. It drives the DESKTOP's library sync
// (what you send and get is the desktop's library). Desktop twin:
// lib/ui/pages/settings_page/sync_tab.dart. Jobs take minutes, so each one
// starts and this card polls /api/sync; a Get restarts the desktop's web
// server, so polling rides out a few failed requests and then reloads.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { StepUpFields, attachStepUp } from './StepUpFields';

interface Entry {
  id: string;
  device: string;
  when: string;
  pinned?: boolean;
}

type Outcome =
  | { kind: 'done' | 'failed'; message: string }
  | { kind: 'sendConflict'; otherLibrary: boolean; message: string; theirs?: Entry }
  | { kind: 'getReady'; conflicts: boolean; summary: string; changes: string };

export interface SyncStatus {
  disabled: boolean;
  disabledReason?: string;
  configured: boolean;
  place: {
    kind: 'none' | 'webdav' | 'folder';
    serverUrl: string;
    username: string;
    folderName: string;
    folderPath: string;
    passwordSaved: boolean;
  };
  deviceName: string;
  deviceNameShown: string;
  sendOnClose: boolean;
  checkOnStart: boolean;
  remote: (Partial<Entry> & { summary?: string; newer: boolean; earlier: Entry[] }) | null;
  remoteError: string | null;
  lastSync: { sent: boolean; when: string; device: string } | null;
  here: string | null;
  undo: { when: string; device: string } | null;
  phase: 'idle' | 'checking' | 'packing' | 'sending' | 'fetching' | 'replacing';
  progress: { done: number; total: number };
  needsRestart: string | null;
  outcome: Outcome | null;
}

const PHASE: Record<SyncStatus['phase'], string> = {
  idle: '',
  checking: 'Checking the desktop for changes…',
  packing: 'Packing the library…',
  sending: 'Sending',
  fetching: 'Getting the library',
  replacing: 'Replacing the desktop\'s library…',
};

function isSyncStatus(value: unknown): value is SyncStatus {
  if (!value || typeof value !== 'object') return false;
  const v = value as Partial<SyncStatus>;
  return !!v.place && typeof v.phase === 'string' && !!v.progress;
}

function size(bytes: number): string {
  if (bytes >= 1 << 30) return `${(bytes / (1 << 30)).toFixed(1)} GB`;
  if (bytes >= 1 << 20) return `${(bytes / (1 << 20)).toFixed(1)} MB`;
  return `${Math.ceil(bytes / 1024)} KB`;
}

export function SyncSettings({ pollMs = 1000 }: { pollMs?: number }) {
  const [status, setStatus] = useState<SyncStatus | null>(null);
  const [kind, setKind] = useState<'webdav' | 'folder'>('webdav');
  const [serverUrl, setServerUrl] = useState('');
  const [username, setUsername] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [folderPath, setFolderPath] = useState('');
  const [folderName, setFolderName] = useState('');
  const [password, setPassword] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);
  const [totpCode, setTotpCode] = useState('');
  const [note, setNote] = useState('');
  const [reconnecting, setReconnecting] = useState(false);
  // A ref, not state: a fast double tap lands before the re-render.
  const acting = useRef(false);
  const swapStarted = useRef(false);

  // Only a real status: an older desktop, or anything in between, may answer
  // with something else, and the card must not fall over on it.
  const take = useCallback((next: unknown) => {
    if (!isSyncStatus(next)) {
      setReconnecting(true);
      return;
    }
    setStatus(next);
    setReconnecting(false);
  }, []);

  const load = useCallback(async () => {
    try {
      take(await api.get<SyncStatus>('/api/sync'));
    } catch {
      setReconnecting(true);
    }
  }, [take]);

  useEffect(() => {
    void (async () => {
      try {
        const first = await api.post<SyncStatus>('/api/sync/refresh', {});
        take(first);
        if (!isSyncStatus(first)) return;
        setKind(first.place.kind === 'folder' ? 'folder' : 'webdav');
        setServerUrl(first.place.serverUrl);
        setUsername(first.place.username);
        setFolderPath(first.place.folderPath);
        setFolderName(first.place.folderName);
      } catch {
        setReconnecting(true);
      }
    })();
    api
      .get<{ totpEnabled?: boolean }>('/api/auth/state')
      .then((st) => setTotpEnabled(!!st.totpEnabled))
      .catch(() => undefined);
  }, [take]);

  const busy = !!status && status.phase !== 'idle';
  useEffect(() => {
    if (!busy && !reconnecting && !swapStarted.current) return;
    const timer = window.setInterval(() => void load(), pollMs);
    return () => window.clearInterval(timer);
  }, [busy, reconnecting, load, pollMs]);

  // A Get started here finished: the desktop's library is a different one
  // now, so every page of this app reloads it.
  useEffect(() => {
    if (!swapStarted.current || busy || reconnecting) return;
    if (status?.outcome?.kind === 'done') {
      swapStarted.current = false;
      window.location.reload();
    } else if (status?.outcome) {
      swapStarted.current = false;
    }
  }, [status, busy, reconnecting]);

  const act = async (path: string, body: Record<string, unknown> = {}) => {
    if (acting.current) return;
    acting.current = true;
    setNote('');
    try {
      await api.post(path, body);
      await load();
    } catch (e) {
      setNote(e instanceof ApiError ? e.message : 'Could not reach the desktop app.');
    } finally {
      acting.current = false;
    }
  };

  const saveAndTest = async () => {
    if (acting.current) return;
    acting.current = true;
    setNote('');
    try {
      const body: Record<string, unknown> = { kind, serverUrl, username, folderPath, folderName };
      if (newPassword) {
        body.password = newPassword;
        attachStepUp(body, password, totpEnabled, totpCode);
      }
      take(await api.post<SyncStatus>('/api/sync/settings', body));
      setNewPassword('');
      setPassword('');
      setTotpCode('');
      const test = await api.post<{ ok: boolean; message: string }>('/api/sync/test', {});
      setNote(test.message);
      await load();
    } catch (e) {
      setNote(e instanceof ApiError ? e.message : 'Could not reach the desktop app.');
    } finally {
      acting.current = false;
    }
  };

  const setSwitch = (key: 'sendOnClose' | 'checkOnStart', value: boolean) =>
    void api.post<SyncStatus>('/api/sync/settings', { [key]: value }).then(take);

  if (!status) {
    return (
      <section className="card" data-testid="sync-card">
        <h3>Sync</h3>
        <p className="muted small">{reconnecting ? 'Could not reach the desktop app.' : 'Loading…'}</p>
      </section>
    );
  }
  if (status.disabled) {
    return (
      <section className="card" data-testid="sync-card">
        <h3>Sync</h3>
        <p className="muted small">{status.disabledReason}</p>
      </section>
    );
  }

  const ready = status.configured && !busy && !reconnecting;
  const outcome = status.outcome;
  const remote = status.remote;
  const last = status.lastSync;

  return (
    <section className="card" data-testid="sync-card">
      <h3>Sync</h3>
      <p className="muted small">
        Send the desktop&apos;s whole library to a place you own, and get it on your other devices.
        Characters, chats, personas, groups, worlds, lorebooks, the Data Bank, journals, presets and
        backgrounds travel. Models, backends and keys, voices and appearance stay on each device.
        Chats are uploaded as they are to the place you choose.
      </p>

      <fieldset className="sync-place">
        <legend>Sync place</legend>
        <label className="row-label">
          <input type="radio" checked={kind === 'webdav'} onChange={() => setKind('webdav')} />
          <span>WebDAV server</span>
        </label>
        <label className="row-label">
          <input type="radio" checked={kind === 'folder'} onChange={() => setKind('folder')} />
          <span>A folder on the desktop</span>
        </label>
        {kind === 'webdav' ? (
          <>
            <label>
              Server address
              <input
                value={serverUrl}
                inputMode="url"
                placeholder="https://cloud.example.com/remote.php/dav/files/you/"
                onChange={(e) => setServerUrl(e.target.value)}
              />
            </label>
            <label>
              Username
              <input value={username} onChange={(e) => setUsername(e.target.value)} />
            </label>
            <label>
              App password
              <input
                type="password"
                value={newPassword}
                placeholder={status.place.passwordSaved ? 'Saved on the desktop' : ''}
                onChange={(e) => setNewPassword(e.target.value)}
              />
            </label>
            {newPassword && (
              <StepUpFields
                password={password}
                onPassword={setPassword}
                totpEnabled={totpEnabled}
                totpCode={totpCode}
                onTotp={setTotpCode}
                reason={
                  totpEnabled
                    ? 'Saving a sync password needs your web login password and a 2FA code.'
                    : 'Saving a sync password needs your web login password.'
                }
              />
            )}
          </>
        ) : (
          <label>
            Folder on the desktop
            <input value={folderPath} onChange={(e) => setFolderPath(e.target.value)} />
          </label>
        )}
        <label>
          Folder the app creates there
          <input value={folderName} onChange={(e) => setFolderName(e.target.value)} />
        </label>
        <button
          className="ghost"
          disabled={busy || (!!newPassword && !password)}
          onClick={() => void saveAndTest()}
        >
          Save and test connection
        </button>
      </fieldset>

      <label>
        The desktop&apos;s name on the sync place
        <input
          defaultValue={status.deviceName}
          placeholder={status.deviceNameShown}
          onBlur={(e) =>
            void api
              .post<SyncStatus>('/api/sync/settings', { deviceName: e.target.value })
              .then(take)
          }
        />
      </label>

      <div className="sync-status" data-testid="sync-status">
        {status.remoteError ? (
          <p className="error">{status.remoteError}</p>
        ) : !status.configured ? (
          <p className="muted small">Set up a sync place above.</p>
        ) : !remote ? (
          <p className="muted small">Nothing has been sent to the sync place yet.</p>
        ) : (
          <p className="small">
            On the sync place: {remote.device ?? 'a device'}&apos;s library, {remote.when}
            {remote.summary ? ` · ${remote.summary}` : ''}
            {remote.newer ? ' · newer than the desktop’s' : ''}
          </p>
        )}
        <p className="muted small">
          {last
            ? `${last.sent ? 'Sent' : 'Got'} ${last.when}${last.sent ? '' : ` from ${last.device}`}.`
            : 'The desktop hasn’t synced yet.'}
        </p>
        {status.here && <p className="muted small">{status.here}</p>}
        {status.needsRestart && <p className="error">{status.needsRestart}</p>}
      </div>

      {outcome?.kind === 'sendConflict' && (
        <div className="sync-choice" role="group" aria-label="Send conflict">
          <p className="small">{outcome.message}</p>
          <p className="muted small">
            Theirs stays on the sync place under Earlier versions if you send yours anyway.
          </p>
          {!outcome.otherLibrary && (
            <button className="primary" onClick={() => void act('/api/sync/get')}>
              Get theirs first
            </button>
          )}
          <button className="ghost" onClick={() => void act('/api/sync/send', { overwrite: true })}>
            Send mine anyway
          </button>
        </div>
      )}
      {outcome?.kind === 'getReady' && !busy && (
        <div className="sync-choice" role="group" aria-label="Get the library">
          <p className="small">{outcome.summary}</p>
          {outcome.conflicts && <p className="muted small">{outcome.changes}</p>}
          <p className="muted small">
            The desktop&apos;s library is set aside; Undo puts it back for 7 days.
          </p>
          <button
            className="primary"
            onClick={() => {
              swapStarted.current = true;
              void act('/api/sync/get/apply');
            }}
          >
            {outcome.conflicts ? 'Take theirs' : 'Get it'}
          </button>
          <button className="ghost" onClick={() => void act('/api/sync/get/discard')}>
            {outcome.conflicts ? 'Keep mine' : 'Cancel'}
          </button>
        </div>
      )}
      {(outcome?.kind === 'done' || outcome?.kind === 'failed') && (
        <p className={outcome.kind === 'failed' ? 'error' : 'muted small'}>{outcome.message}</p>
      )}

      <div className="row-label sync-actions">
        <button className="primary" disabled={!ready} onClick={() => void act('/api/sync/send')}>
          Send my library
        </button>
        <button className="ghost" disabled={!ready} onClick={() => void act('/api/sync/get')}>
          Get the library
        </button>
        {status.undo && (
          <button className="ghost" disabled={!ready} onClick={() => void act('/api/sync/undo')}>
            Undo the Get from {status.undo.when}
          </button>
        )}
      </div>
      {(busy || reconnecting) && (
        <div className="sync-progress" aria-live="polite">
          {status.progress.total > 0 && (
            <progress value={status.progress.done} max={status.progress.total} />
          )}
          <p className="muted small">
            {reconnecting
              ? 'Reconnecting to the desktop…'
              : `${PHASE[status.phase]}${
                  status.progress.total > 0
                    ? ` · ${size(status.progress.done)} of ${size(status.progress.total)}`
                    : ''
                }`}
          </p>
          {busy && status.phase !== 'replacing' && status.phase !== 'checking' && (
            <button className="ghost" onClick={() => void act('/api/sync/cancel')}>
              Cancel
            </button>
          )}
        </div>
      )}
      {note && <p className="muted small">{note}</p>}

      {remote && remote.earlier.length > 0 && (
        <details className="sync-earlier">
          <summary>Earlier versions on the sync place</summary>
          {remote.earlier.map((s) => (
            <div key={s.id} className="row-label">
              <span className="small">
                {s.device} · {s.when}
                {s.pinned ? ' · kept because a newer one replaced it' : ''}
              </span>
              <button
                className="ghost"
                disabled={!ready}
                onClick={() => void act('/api/sync/get', { snapshot: s.id })}
              >
                Get this one
              </button>
            </div>
          ))}
        </details>
      )}

      <label className="row-label">
        <input
          type="checkbox"
          checked={status.sendOnClose}
          onChange={(e) => setSwitch('sendOnClose', e.target.checked)}
        />
        <span>Send the library when the desktop app closes</span>
      </label>
      <label className="row-label">
        <input
          type="checkbox"
          checked={status.checkOnStart}
          onChange={(e) => setSwitch('checkOnStart', e.target.checked)}
        />
        <span>Check for a newer library when the desktop app starts</span>
      </label>
    </section>
  );
}
