// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Backend → Memory search: the embedding model that turns saved
// memories into vectors — a model server (Ollama or OpenAI-compatible, its
// embedding models in a dropdown) or the desktop's on-device model — and
// Clear and re-vectorize. Desktop twin: MemorySearchSection
// (lib/ui/settings/tabs/backend/memory_search_section.dart).

import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';

export interface MemorySearchSnapshot {
  provider?: 'endpoint' | 'onDevice';
  endpointUrl?: string;
  endpointModel?: string;
  hasApiKey?: boolean;
  onDeviceModel?: string;
  activeModel?: string;
  indexModel?: string;
  status?: {
    available?: boolean;
    configured?: boolean;
    modelOnDisk?: boolean;
    settingUp?: boolean;
    setupError?: string | null;
    lastEngineError?: string | null;
    endpointHost?: string | null;
    dimensions?: number;
    indexMatches?: boolean;
  };
  rebuild?: {
    running?: boolean;
    done?: number;
    total?: number;
    error?: string | null;
    stored?: number | null;
    missing?: number | null;
  };
}

const BASE = '/api/memory/embedding';

/** `endpoint|model` → `model`. */
function modelName(id?: string): string {
  if (!id) return '';
  const bar = id.indexOf('|');
  return bar < 0 ? id : id.slice(bar + 1);
}

function failure(e: unknown): string {
  return e instanceof ApiError ? e.message : 'Could not reach the desktop app.';
}

function statusLine(s: MemorySearchSnapshot): string {
  const st = s.status ?? {};
  if (s.provider === 'onDevice') {
    if (st.available) return `Ready — ${s.onDeviceModel ?? 'the on-device model'} on the desktop.`;
    if (st.settingUp) return 'The desktop is setting up the on-device model…';
    if (!st.modelOnDisk) {
      return 'The on-device model is not installed. Turn Memory on in a chat on the desktop app to download it (~550 MB, one time).';
    }
    return st.setupError || st.lastEngineError || 'The on-device model starts the next time memory is used.';
  }
  if (!st.configured) return 'Pick a server and one of its embedding models.';
  if (st.available) {
    return `Ready — ${s.endpointModel} on ${st.endpointHost ?? s.endpointUrl}, ${st.dimensions ?? 0}-dimension vectors.`;
  }
  const err = st.setupError || st.lastEngineError;
  if (err) return `Can't reach the memory model: ${err}`;
  return 'Not checked yet.';
}

export function MemorySearchSettings() {
  const [snap, setSnap] = useState<MemorySearchSnapshot | null>(null);
  const [url, setUrl] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [models, setModels] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [confirming, setConfirming] = useState(false);
  // A ref, not the state: a fast double tap lands before the re-render.
  const busyNow = useRef(false);

  const take = useCallback((next: MemorySearchSnapshot) => {
    setSnap(next);
    setUrl((u) => u || next.endpointUrl || '');
  }, []);

  const run = useCallback(
    async (call: () => Promise<MemorySearchSnapshot | void>) => {
      if (busyNow.current) return;
      busyNow.current = true;
      setBusy(true);
      setMessage('');
      try {
        const next = await call();
        if (next) take(next);
      } catch (e) {
        setMessage(failure(e));
      } finally {
        busyNow.current = false;
        setBusy(false);
      }
    },
    [take],
  );

  const loadModels = useCallback(async () => {
    const r = await api.post<{ models?: string[] }>(`${BASE}/models`, {});
    const list = r.models ?? [];
    setModels(list);
    if (list.length === 0) setMessage('This server lists no models.');
  }, []);

  useEffect(() => {
    let cancelled = false;
    api
      .get<MemorySearchSnapshot>(BASE)
      .then((s) => {
        if (cancelled) return;
        take(s);
        if (s.provider === 'endpoint' && s.endpointUrl) {
          loadModels().catch((e) => !cancelled && setMessage(`Could not list models: ${failure(e)}`));
        }
      })
      .catch((e) => !cancelled && setMessage(failure(e)));
    return () => {
      cancelled = true;
    };
  }, [take, loadModels]);

  const running = snap?.rebuild?.running === true;
  useEffect(() => {
    if (!running) return;
    const timer = setInterval(() => {
      api.get<MemorySearchSnapshot>(BASE).then(take).catch(() => {});
    }, 1500);
    return () => clearInterval(timer);
  }, [running, take]);

  const saveServer = () =>
    run(async () => {
      const next = await api.post<MemorySearchSnapshot>(BASE, {
        provider: 'endpoint',
        endpointUrl: url.trim(),
        ...(apiKey.trim() ? { apiKey: apiKey.trim() } : {}),
      });
      setApiKey('');
      take(next);
      try {
        await loadModels();
      } catch (e) {
        setModels([]);
        setMessage(`Could not list models: ${failure(e)}`);
      }
    });

  const current = snap?.endpointModel ?? '';
  const choices = current && !models.includes(current) ? [current, ...models] : models;
  const rb = snap?.rebuild ?? {};
  const stored = rb.stored ?? 0;
  const missing = rb.missing ?? 0;
  const mismatch = snap?.status?.indexMatches === false && stored > 0;
  const configured = snap?.status?.configured === true;
  const pct = running && (rb.total ?? 0) > 0 ? Math.round(((rb.done ?? 0) / (rb.total ?? 1)) * 100) : null;

  return (
    <section className="card" data-testid="memory-search-card">
      <h3>Memory search</h3>
      <p className="muted small">
        The embedding model that turns saved memories, Journal cards and Data Bank entries into
        vectors, so each reply can find the old moments that matter. Used when Memory (RAG) is on.
      </p>
      {snap && (
        <>
          <label>
            Runs on
            <select
              data-testid="memory-search-provider"
              value={snap.provider ?? 'endpoint'}
              disabled={busy}
              onChange={(e) => run(() => api.post<MemorySearchSnapshot>(BASE, { provider: e.target.value }))}
            >
              <option value="endpoint">A model server</option>
              <option value="onDevice">The desktop's on-device model</option>
            </select>
          </label>
          {snap.provider !== 'onDevice' && (
            <>
              <label>
                Server URL
                <input
                  data-testid="memory-search-url"
                  value={url}
                  placeholder="http://192.168.0.100:11434 or https://api.openai.com/v1"
                  disabled={busy}
                  onChange={(e) => setUrl(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') void saveServer();
                  }}
                />
              </label>
              <p className="muted small">
                Ollama, or any OpenAI-compatible server. The desktop app calls it, so use an address the
                desktop can reach.
              </p>
              <label>
                API key (optional)
                <input
                  data-testid="memory-search-key"
                  type="password"
                  value={apiKey}
                  placeholder={snap.hasApiKey ? 'Saved — type a new one to replace it' : 'Not needed for Ollama on your own network'}
                  disabled={busy}
                  onChange={(e) => setApiKey(e.target.value)}
                />
              </label>
              <div className="row-label">
                <button className="ghost" data-testid="memory-search-load" disabled={busy || !url.trim()} onClick={() => void saveServer()}>
                  Load models
                </button>
              </div>
              <label>
                Embedding model
                <select
                  data-testid="memory-search-model"
                  value={current}
                  disabled={busy || choices.length === 0}
                  onChange={(e) =>
                    run(() =>
                      api.post<MemorySearchSnapshot>(BASE, { provider: 'endpoint', endpointModel: e.target.value }),
                    )
                  }
                >
                  {!current && <option value="">{choices.length ? 'Pick one' : "Load the server's models first"}</option>}
                  {choices.map((m) => (
                    <option key={m} value={m}>
                      {m}
                    </option>
                  ))}
                </select>
              </label>
            </>
          )}
          <p className="muted small" role="status" data-testid="memory-search-status">
            {statusLine(snap)}
          </p>
          <div className="row-label">
            <button
              className="ghost"
              disabled={busy}
              onClick={() => run(() => api.post<MemorySearchSnapshot>(`${BASE}/check`, {}))}
            >
              Check connection
            </button>
          </div>

          <h4>Stored vectors</h4>
          <p className="muted small" data-testid="memory-search-counts">
            {stored} saved memories, Journal cards and Data Bank entries
            {missing > 0 ? `, ${missing} without a vector` : ''}.
          </p>
          {mismatch && (
            <p className="small rag-engine-error" data-testid="memory-search-mismatch">
              They were made with {modelName(snap.indexModel)}, and memory search now uses{' '}
              {modelName(snap.activeModel)}. Vectors from two models don't compare, so old memories
              won't be found until you re-vectorize.
            </p>
          )}
          {running && (
            <div className="rag-engine-status">
              <div className="rag-progress-track" aria-hidden>
                <div
                  className="rag-progress-fill"
                  style={pct == null ? { width: '30%', opacity: 0.5 } : { width: `${pct}%` }}
                />
              </div>
              <p className="muted small">
                {rb.done ?? 0} of {rb.total ?? 0}
              </p>
            </div>
          )}
          {!running && rb.error && <p className="small rag-engine-error">{rb.error}</p>}
          <div className="row-label">
            {running ? (
              <button className="ghost" onClick={() => run(() => api.post<MemorySearchSnapshot>(`${BASE}/rebuild/stop`, {}))}>
                Stop
              </button>
            ) : confirming ? (
              <>
                <span className="small">Every vector is replaced; the text is kept.</span>
                <button
                  className="primary"
                  data-testid="memory-search-rebuild-confirm"
                  disabled={busy}
                  onClick={() => {
                    setConfirming(false);
                    void run(() => api.post<MemorySearchSnapshot>(`${BASE}/rebuild`, { mode: 'all' }));
                  }}
                >
                  Re-vectorize
                </button>
                <button className="ghost" onClick={() => setConfirming(false)}>
                  Cancel
                </button>
              </>
            ) : (
              <>
                <button
                  className="primary"
                  data-testid="memory-search-rebuild"
                  disabled={busy || !configured}
                  onClick={() => setConfirming(true)}
                >
                  Clear and re-vectorize everything
                </button>
                {missing > 0 && (
                  <button
                    className="ghost"
                    disabled={busy || !configured}
                    onClick={() => run(() => api.post<MemorySearchSnapshot>(`${BASE}/rebuild`, { mode: 'missing' }))}
                  >
                    Vectorize the {missing} missing
                  </button>
                )}
              </>
            )}
          </div>
        </>
      )}
      {message && (
        <p className="small rag-engine-error" role="alert">
          {message}
        </p>
      )}
    </section>
  );
}
