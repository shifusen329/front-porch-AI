// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → General → Troubleshooting → Write a debug log
// (desktop: debug_log_card.dart). The log lives on the computer running the
// app; this turns it on and off, shows its newest part, downloads a copy and
// clears it there.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { downloadBlob } from '../pages/story/storyUtil';

interface DebugLogStatus {
  enabled: boolean;
  bytes: number;
  fileName: string;
  problem?: string | null;
}

/** How much of the log View shows: the newest part, as on the desktop. */
export const DEBUG_LOG_VIEW_CHARS = 100000;

/** The newest DEBUG_LOG_VIEW_CHARS of the log, from the start of a line. */
export function debugLogTail(log: string): string {
  if (log.length <= DEBUG_LOG_VIEW_CHARS) return log;
  const cut = log.length - DEBUG_LOG_VIEW_CHARS;
  const lineStart = log.indexOf('\n', cut);
  return lineStart < 0 ? log.slice(cut) : log.slice(lineStart + 1);
}

/** The name a downloaded copy gets, as the desktop's Save a copy offers it. */
export function debugLogSaveName(at: Date): string {
  const two = (n: number) => String(n).padStart(2, '0');
  return `front-porch-log-${at.getFullYear()}-${two(at.getMonth() + 1)}-${two(at.getDate())}-${two(at.getHours())}${two(at.getMinutes())}.txt`;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
}

export function DebugLogSettings() {
  const [status, setStatus] = useState<DebugLogStatus | null>(null);
  const [shown, setShown] = useState<string | null>(null);
  const [problem, setProblem] = useState('');
  const [busy, setBusy] = useState(false);
  // A second tap before the first one re-renders must not run it twice.
  const working = useRef(false);
  const view = useRef<HTMLPreElement>(null);

  useEffect(() => {
    let live = true;
    api
      .get<DebugLogStatus>('/api/debug-log')
      .then((s) => live && setStatus(s))
      .catch(() => live && setProblem('The debug log could not be read from the app.'));
    return () => {
      live = false;
    };
  }, []);

  useEffect(() => {
    if (shown !== null && view.current) view.current.scrollTop = view.current.scrollHeight;
  }, [shown]);

  const run = async (step: () => Promise<void>, failure: string) => {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setProblem('');
    try {
      await step();
    } catch (e) {
      setProblem(e instanceof ApiError ? e.message : failure);
    } finally {
      working.current = false;
      setBusy(false);
    }
  };

  const toggle = (enabled: boolean) =>
    run(async () => {
      setStatus(await api.post<DebugLogStatus>('/api/debug-log', { enabled }));
    }, 'That could not be saved. Check that the app is running, then try again.');

  const showLog = () =>
    run(async () => {
      if (shown !== null) {
        setShown(null);
        return;
      }
      const blob = await api.getForBlob('/api/debug-log/file');
      setShown(debugLogTail(await blob.text()));
    }, 'The log could not be read.');

  const download = () =>
    run(async () => {
      const blob = await api.getForBlob('/api/debug-log/file');
      downloadBlob(blob, debugLogSaveName(new Date()));
    }, 'The log could not be downloaded.');

  const clear = () =>
    run(async () => {
      setStatus(await api.post<DebugLogStatus>('/api/debug-log/clear'));
      setShown(null);
    }, 'The log could not be cleared.');

  const hasLog = (status?.bytes ?? 0) > 0;

  return (
    <section className="card" data-testid="debug-log-card">
      <h3>Debug log</h3>
      <p className="reading-blurb">
        Keeps what the app does, its warnings and its errors, with the time, in a file on the
        computer running Front Porch AI. Turn it on, do what goes wrong, then download a copy to
        share. Keys and passwords are blanked out, but the log can hold parts of your chats, so
        look it over before you post it.
      </p>
      <label>
        <input
          type="checkbox"
          data-testid="debug-logging"
          checked={status?.enabled ?? false}
          disabled={status === null || busy}
          onChange={(e) => void toggle(e.target.checked)}
          aria-label="Write a debug log"
        />
        {' '}Write a debug log
      </label>
      {status?.problem && (
        <p className="small rag-engine-error" role="alert">
          The log could not be written: {status.problem}
        </p>
      )}
      <p className="muted small" data-testid="debug-log-size">
        {hasLog && status ? `${status.fileName} · ${formatBytes(status.bytes)}` : 'No log yet.'}
      </p>
      <div className="about-links">
        <button className="ghost" data-testid="debug-log-view" disabled={!hasLog || busy} onClick={() => void showLog()}>
          {shown === null ? 'View' : 'Hide'}
        </button>
        <button
          className="ghost"
          data-testid="debug-log-download"
          disabled={!hasLog || busy}
          onClick={() => void download()}
        >
          Download a copy
        </button>
        <button className="ghost" data-testid="debug-log-clear" disabled={!hasLog || busy} onClick={() => void clear()}>
          Clear
        </button>
      </div>
      {shown !== null && (
        <pre
          ref={view}
          data-testid="debug-log-text"
          className="small"
          style={{ maxHeight: '50vh', overflow: 'auto', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}
        >
          {shown}
        </pre>
      )}
      {problem && (
        <p className="small rag-engine-error" role="alert">
          {problem}
        </p>
      )}
    </section>
  );
}
