// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Narrate All for the phone web app: the host sends the chat's lines (each
// with the voice the desktop reads it in) from /api/chat/narration, and this
// plays them on this device in order, fetching the next line's audio while
// one plays. Shaped like the story reader's useSceneNarration.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';

export interface NarrationLine {
  /** The `#N` shown under the message's avatar. */
  number: number;
  speaker: string;
  text: string;
  /** Null is the global voice. */
  voiceKey: string | null;
}

export function useChatNarration() {
  const [reading, setReading] = useState(false);
  const [done, setDone] = useState(0);
  const [total, setTotal] = useState(0);
  const [current, setCurrent] = useState<NarrationLine | null>(null);
  const [error, setError] = useState<string | null>(null);
  // A ref, not the state: a double tap lands before the re-render.
  const readingRef = useRef(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const cache = useRef<Map<number, Promise<string>>>(new Map());

  const audioFor = useCallback((lines: NarrationLine[], i: number) => {
    const hit = cache.current.get(i);
    if (hit) return hit;
    const line = lines[i];
    const body = line.voiceKey ? { text: line.text, voiceKey: line.voiceKey } : { text: line.text };
    const url = api.postForBlob('/api/tts/speak', body).then((b) => URL.createObjectURL(b));
    cache.current.set(i, url);
    return url;
  }, []);

  const clearCache = useCallback(() => {
    cache.current.forEach((u) => void u.then((x) => URL.revokeObjectURL(x)).catch(() => {}));
    cache.current.clear();
  }, []);

  const stop = useCallback(() => {
    readingRef.current = false;
    setReading(false);
    setCurrent(null);
    audioRef.current?.pause();
    audioRef.current = null;
    clearCache();
  }, [clearCache]);

  /** Reads from `#from` (1 is the chat's first message) to the end. */
  const start = useCallback(
    async (from = 1) => {
      if (readingRef.current) return;
      readingRef.current = true;
      setReading(true);
      setError(null);
      setDone(0);
      try {
        const { lines } = await api.get<{ lines: NarrationLine[] }>(
          `/api/chat/narration?from=${Math.max(1, Math.floor(from))}`,
        );
        if (lines.length === 0) setError('Nothing to narrate from there.');
        setTotal(lines.length);
        for (let i = 0; readingRef.current && i < lines.length; i++) {
          setCurrent(lines[i]);
          let url: string;
          try {
            url = await audioFor(lines, i);
          } catch (e) {
            // The host said no (TTS off, a voice the server lacks): stop here
            // rather than skipping every line in silence.
            setError(e instanceof Error && e.message ? e.message : 'Could not read this line aloud.');
            break;
          }
          if (!readingRef.current) break;
          if (i + 1 < lines.length) void audioFor(lines, i + 1).catch(() => {});
          await new Promise<void>((resolve) => {
            const audio = new Audio(url);
            audioRef.current = audio;
            audio.onended = () => resolve();
            audio.onerror = () => resolve();
            audio.play().catch(() => resolve());
          });
          if (!readingRef.current) break;
          URL.revokeObjectURL(url);
          cache.current.delete(i);
          setDone(i + 1);
        }
      } catch (e) {
        setError(e instanceof Error && e.message ? e.message : 'Could not load the chat to narrate.');
      } finally {
        readingRef.current = false;
        setReading(false);
        setCurrent(null);
        clearCache();
      }
    },
    [audioFor, clearCache],
  );

  useEffect(
    () => () => {
      readingRef.current = false;
      audioRef.current?.pause();
      clearCache();
    },
    [clearCache],
  );

  return { reading, done, total, current, error, start, stop };
}
