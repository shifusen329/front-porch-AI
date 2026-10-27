// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice & Media enable toggles for the web Settings page. Desktop Voice &
// Media lives on the host; a phone/remote user still needs to turn TTS and
// STT on (audit P2.12). Engine pick / voice download stay on desktop. An
// OpenAI-compatible server that publishes its own voices can have them read
// again from here, as the desktop's Refresh does.

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';

interface VoiceStatus {
  ttsEnabled: boolean;
  sttEnabled?: boolean;
  sttAvailable: boolean;
  ttsEngine?: string;
  globalVoice?: string;
  listsVoices?: boolean;
  /** Set only on a list-voices answer: how many voices the server sent. */
  found?: number | null;
}

export function VoiceMediaSettings() {
  const [v, setV] = useState<VoiceStatus | null>(null);
  const [saving, setSaving] = useState(false);
  const [listing, setListing] = useState(false);
  const [listNote, setListNote] = useState('');
  // A ref, not the state: a fast double click lands before the re-render.
  const listingNow = useRef(false);

  const load = () =>
    api.get<VoiceStatus>('/api/voice/status').then(setV).catch(() => {});

  useEffect(() => {
    void load();
  }, []);

  if (!v) return null;

  const patch = async (p: Partial<VoiceStatus>) => {
    setSaving(true);
    try {
      const next = await api.post<VoiceStatus>('/api/voice/settings', p);
      setV(next);
    } catch {
      /* keep last known */
    } finally {
      setSaving(false);
    }
  };

  const listVoices = async () => {
    if (listingNow.current) return;
    listingNow.current = true;
    setListing(true);
    setListNote('');
    try {
      const next = await api.post<VoiceStatus>('/api/voice/list-voices', {});
      setV(next);
      setListNote(
        next.found == null
          ? 'The server sent no voice list. Type the voice id it uses in the desktop app.'
          : `Found ${next.found} ${next.found === 1 ? 'voice' : 'voices'} on the server.`,
      );
    } catch {
      setListNote('Could not reach the desktop app. Try again in a moment.');
    } finally {
      listingNow.current = false;
      setListing(false);
    }
  };

  return (
    <section className="card">
      <h3>Voice &amp; Media</h3>
      <p className="muted small">
        Turn spoken replies and the microphone on for this computer. Pick the
        engine and voice on the desktop app — this page only enables them.
      </p>
      <label className="row-label">
        <span>Enable text-to-speech</span>
        <input
          type="checkbox"
          checked={v.ttsEnabled}
          disabled={saving}
          onChange={(e) => void patch({ ttsEnabled: e.target.checked })}
        />
      </label>
      <label className="row-label">
        <span>Enable speech-to-text</span>
        <input
          type="checkbox"
          checked={!!v.sttEnabled}
          disabled={saving}
          onChange={(e) => void patch({ sttEnabled: e.target.checked })}
        />
      </label>
      {!v.sttAvailable && v.sttEnabled && (
        <p className="muted small">
          Speech-to-text is on, but the host has not finished loading a
          recogniser yet. Try the mic again in a moment.
        </p>
      )}
      {v.listsVoices && (
        <>
          <div className="row-label">
            <span>Voices from your text-to-speech server</span>
            <button className="ghost" disabled={listing} onClick={() => void listVoices()}>
              {listing ? 'Refreshing…' : 'Refresh voices'}
            </button>
          </div>
          <p className="muted small" role="status">
            {listNote || 'Refresh after adding a voice on the server, so the character voice pickers show it.'}
          </p>
        </>
      )}
    </section>
  );
}
