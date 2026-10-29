// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Narrate All in the web chat tools, as the desktop side panel's Narration
// section: read the chat aloud on this device from its first message, or from
// the `#N` given under "Starting at". Shown only while text-to-speech is on.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { useChatNarration } from '../pages/chat/useChatNarration';

export function ChatToolsNarration() {
  const [ttsOn, setTtsOn] = useState(false);
  const [startAt, setStartAt] = useState(false);
  const [from, setFrom] = useState('');
  const n = useChatNarration();

  useEffect(() => {
    api
      .get<{ ttsEnabled: boolean }>('/api/voice/status')
      .then((v) => setTtsOn(!!v.ttsEnabled))
      .catch(() => {});
  }, []);

  if (!ttsOn) return null;

  const fromNumber = startAt ? Number.parseInt(from, 10) || 1 : 1;
  const at = Math.min(n.done + 1, Math.max(n.total, 1));

  return (
    <details className="tool-section" data-testid="chat-narration">
      <summary>Narration 🔊</summary>
      <p className="muted small">
        Reads the chat aloud in order: your lines in your voice, each character in theirs, the
        narrator in the narrator voice.
      </p>
      <label className="row-label">
        <span>Starting at</span>
        <input
          type="checkbox"
          data-testid="narration-start-at"
          checked={startAt}
          disabled={n.reading}
          onChange={(e) => setStartAt(e.target.checked)}
        />
      </label>
      <input
        type="number"
        min={1}
        inputMode="numeric"
        data-testid="narration-from"
        placeholder="Message number, e.g. 12"
        value={from}
        disabled={!startAt || n.reading}
        onChange={(e) => setFrom(e.target.value)}
      />
      {n.reading ? (
        <>
          <p className="small" role="status">
            Narrating {at} of {n.total}
            {n.current ? ` · #${n.current.number} ${n.current.speaker}` : ''}
          </p>
          <button data-testid="narration-stop" onClick={n.stop}>
            Stop
          </button>
        </>
      ) : (
        <button data-testid="narration-narrate" onClick={() => void n.start(fromNumber)}>
          Narrate
        </button>
      )}
      {n.error && (
        <p className="small rag-engine-error" role="alert">
          {n.error}
        </p>
      )}
    </details>
  );
}
