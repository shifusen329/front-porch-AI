// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character's Scenes on the phone: pictures of places the chat background
// follows (porch, kitchen, porch at night). Desktop twin:
// lib/ui/dialogs/scene_library/scene_library_dialog.dart. The file name is
// the tag, so a ZIP of porch.png and porch-night.png imports as it is.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';

export interface SceneItem {
  name: string;
  place: string;
  time: string | null;
  alt: number;
}

type Resp = { scenes: SceneItem[] };
type ZipResp = Resp & { added: number; skipped: number };

const TIMES: [string, string][] = [
  ['', 'Any time'],
  ['morning', 'Morning'],
  ['day', 'Day'],
  ['evening', 'Evening'],
  ['night', 'Night'],
];

interface Draft {
  file: File | null;
  /** The scene being renamed; null when adding [file]. */
  scene: SceneItem | null;
  place: string;
  time: string;
}

interface Confirm {
  title: string;
  body: string;
  go: () => Promise<Resp>;
}

/** The host explains a refused picture or place. */
function messageOf(e: unknown): string {
  return e instanceof ApiError && [400, 404, 409, 413].includes(e.status)
    ? e.message
    : 'Action failed.';
}

function sceneLabel(s: SceneItem): string {
  return [s.place, s.time, s.alt > 0 ? `#${s.alt}` : null].filter(Boolean).join(' · ');
}

export function SceneManager({ characterId }: { characterId: string }) {
  const base = `/api/characters/${encodeURIComponent(characterId)}`;
  const [scenes, setScenes] = useState<SceneItem[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [draft, setDraft] = useState<Draft | null>(null);
  const [confirm, setConfirm] = useState<Confirm | null>(null);
  // Bumped on every change, so a re-added name never shows a cached picture.
  const [rev, setRev] = useState(0);
  const imageRef = useRef<HTMLInputElement>(null);
  const zipRef = useRef<HTMLInputElement>(null);
  // A ref, not state: a fast double tap lands before the re-render.
  const acting = useRef(false);

  useEffect(() => {
    let cancelled = false;
    api
      .get<Resp>(`${base}/scenes`)
      .then((r) => !cancelled && setScenes(Array.isArray(r?.scenes) ? r.scenes : []))
      // An older host has no Scenes: the section stays empty.
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [base]);

  /** One post per tap, however fast the taps. */
  const once = <T extends Resp>(go: () => Promise<T>, done?: (r: T) => string) => {
    if (acting.current) return;
    acting.current = true;
    setBusy(true);
    setError('');
    setNotice('');
    go()
      .then((r) => {
        if (Array.isArray(r?.scenes)) setScenes(r.scenes);
        setRev((v) => v + 1);
        if (done) setNotice(done(r));
      })
      .catch((e) => setError(messageOf(e)))
      .finally(() => {
        acting.current = false;
        setBusy(false);
      });
  };

  const save = (d: Draft) => {
    setDraft(null);
    const time = d.time || null;
    if (d.scene) {
      const name = d.scene.name;
      once(() => api.post<Resp>(`${base}/scenes/rename`, { name, place: d.place, time }));
    } else if (d.file) {
      const file = d.file;
      const q = `?place=${encodeURIComponent(d.place)}${time ? `&time=${time}` : ''}`;
      once(
        () => api.upload<Resp>(`${base}/scenes${q}`, file),
        () => `Added ${d.place.trim().toLowerCase()}.`,
      );
    }
  };

  const importZip = (file: File) =>
    once(
      () => api.upload<ZipResp>(`${base}/scenes/zip`, file),
      (r) =>
        r.added === 0
          ? 'No picture in that ZIP is named for a place, like porch.png or porch-night.png.'
          : `Added ${r.added}${r.skipped > 0 ? `, skipped ${r.skipped}` : ''}.`,
    );

  const ask = (c: Confirm) => setConfirm(c);

  return (
    <div className="scene-manager" data-testid="scene-manager">
      <div className="gallery-section-head">
        <span className="section-label">Scenes</span>
        <div className="tool-row">
          {scenes.length > 0 && (
            <button
              className="ghost"
              disabled={busy}
              onClick={() =>
                ask({
                  title: 'Delete every scene picture?',
                  body: `All ${scenes.length} pictures of places go. Expressions and looks stay.`,
                  go: () => api.post<Resp>(`${base}/scenes/delete`, { clear: true }),
                })
              }
            >
              Clear all
            </button>
          )}
          <button className="ghost" disabled={busy} onClick={() => imageRef.current?.click()}>
            {busy ? 'Working…' : '⬆ Add picture'}
          </button>
        </div>
      </div>
      <p className="muted gallery-empty">
        Pictures of places. With the Realism Engine on, the chat background switches to wherever
        the character is. Name each for its place: porch, kitchen, living room.
      </p>
      {scenes.length > 0 && (
        <div className="avatar-grid">
          {scenes.map((s) => (
            <div key={s.name} className="avatar-tile scene-tile" data-scene={s.name}>
              <img
                src={`${base}/scenes/${encodeURIComponent(s.name)}/image?w=256&r=${rev}`}
                alt={sceneLabel(s)}
                loading="lazy"
              />
              <span className="avatar-label">{sceneLabel(s)}</span>
              <div className="avatar-actions">
                <button
                  className="icon-btn"
                  aria-label={`Rename ${sceneLabel(s)}`}
                  disabled={busy}
                  onClick={() => setDraft({ file: null, scene: s, place: s.place, time: s.time ?? '' })}
                >
                  ✎
                </button>
                <button
                  className="icon-btn"
                  aria-label={`Delete ${sceneLabel(s)}`}
                  disabled={busy}
                  onClick={() =>
                    ask({
                      title: 'Delete this picture?',
                      body: `The ${sceneLabel(s)} picture goes for good.`,
                      go: () => api.post<Resp>(`${base}/scenes/delete`, { name: s.name }),
                    })
                  }
                >
                  🗑
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
      <div className="gallery-section-foot">
        <button className="ghost" disabled={busy} onClick={() => zipRef.current?.click()}>
          Import ZIP of scenes
        </button>
      </div>
      {notice && <p className="muted">{notice}</p>}
      {error && <p className="error">{error}</p>}

      <input
        ref={imageRef}
        type="file"
        accept="image/png,image/jpeg,image/webp,image/gif"
        hidden
        data-testid="scene-image-input"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) setDraft({ file: f, scene: null, place: '', time: '' });
          e.target.value = '';
        }}
      />
      <input
        ref={zipRef}
        type="file"
        // Not the sprite pack's accept: journeys find that input by it.
        accept="application/zip,.zip"
        hidden
        data-testid="scene-zip-input"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) importZip(f);
          e.target.value = '';
        }}
      />

      {draft && (
        <div className="drawer-backdrop center" onClick={() => setDraft(null)}>
          <div
            className="modal"
            role="dialog"
            aria-label={draft.scene ? 'Rename picture' : 'Where is this?'}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="drawer-head">
              <span>{draft.scene ? 'Rename picture' : 'Where is this?'}</span>
              <button className="link-btn" onClick={() => setDraft(null)}>
                Close
              </button>
            </div>
            <label className="scene-field">
              Place
              <input
                autoFocus
                value={draft.place}
                placeholder="porch, kitchen, living room"
                onChange={(e) => setDraft({ ...draft, place: e.target.value })}
              />
            </label>
            <label className="scene-field">
              Time of day
              <select value={draft.time} onChange={(e) => setDraft({ ...draft, time: e.target.value })}>
                {TIMES.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <div className="modal-actions">
              <button className="ghost" onClick={() => setDraft(null)}>
                Cancel
              </button>
              <button className="primary" disabled={!draft.place.trim()} onClick={() => save(draft)}>
                Save
              </button>
            </div>
          </div>
        </div>
      )}
      {confirm && (
        <div className="drawer-backdrop center" onClick={() => setConfirm(null)}>
          <div
            className="modal"
            role="dialog"
            aria-label={confirm.title}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="drawer-head">
              <span>{confirm.title}</span>
            </div>
            <p className="muted">{confirm.body}</p>
            <div className="modal-actions">
              <button className="ghost" onClick={() => setConfirm(null)}>
                Cancel
              </button>
              <button
                className="danger"
                onClick={() => {
                  const go = confirm.go;
                  setConfirm(null);
                  once(go);
                }}
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
