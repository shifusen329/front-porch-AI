// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The character's Avatar Gallery for the edit page — the web mirror of the
// desktop unified gallery. Two sections:
//   • Looks       — any image (outfit / scene / seasonal), uploaded as-is (no
//                   crop), the gallery faces you can swipe between in chat.
//   • Expressions — emotion-labeled face images (face-cropped on upload), used
//                   by the expression engine. A ZIP sprite pack imports many
//                   at once (joy.png, joy-1.png …). Up to 40 expressions;
//                   alternates of one don't count (the desktop's limit).
// The ★ favorite (one across BOTH sections) is the default opening face + the
// image baked into an exported / Stoop card. Upload-only: no in-app editing or
// generation on the web (that lives on desktop). Select mode, Clear, Replace on
// ZIP import and a short Undo match the desktop gallery.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { GallerySelectBar, GalleryUndoBar } from './GallerySelectBar';
import { ImageCropModal } from './ImageCropModal';

interface AvatarItem {
  id: string;
  label: string;
  displayOrder: number;
  isPrime: boolean;
  isLook: boolean;
  isFavorite: boolean;
}

interface UndoHandle {
  batch: string;
  count: number;
  replaced: number;
  seconds: number;
}

type Resp = { avatars: AvatarItem[]; undo?: UndoHandle };
type ZipResp = Resp & { added: number; skipped: number; unrecognized: number };

/** A confirm the gallery is waiting on. */
interface Confirm {
  title: string;
  body: string;
  action: string;
  thumbs: string[];
  run: () => void;
}

/** The desktop's limit (kMaxExpressions): distinct expressions, not images. */
export const MAX_EXPRESSIONS = 40;

/** Distinct expression labels, the way the host counts them. */
export function expressionCount(items: AvatarItem[]): number {
  return new Set(
    items.filter((a) => !a.isLook).map((a) => (a.label ?? '').trim().toLowerCase()).filter(Boolean),
  ).size;
}

/** The host explains a refused upload (the 40 limit, a file that isn't a ZIP). */
function messageOf(e: unknown): string {
  return e instanceof ApiError && [400, 409, 410].includes(e.status)
    ? e.message
    : 'Action failed.';
}

export function AvatarManager({ characterId }: { characterId: string }) {
  const [avatars, setAvatars] = useState<AvatarItem[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [pending, setPending] = useState<File | null>(null); // expression → crop
  const lookRef = useRef<HTMLInputElement>(null);
  const exprRef = useRef<HTMLInputElement>(null);
  const zipRef = useRef<HTMLInputElement>(null);
  const labelRef = useRef<HTMLInputElement>(null);

  const base = `/api/characters/${characterId}`;

  const load = () =>
    api
      .get<Resp>(`${base}/avatars`)
      .then((r) => setAvatars(r.avatars))
      .catch(() => {});

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [characterId]);

  const [selecting, setSelecting] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [lastPicked, setLastPicked] = useState<AvatarItem | null>(null);
  const [undo, setUndo] = useState<UndoHandle | null>(null);
  const [confirm, setConfirm] = useState<Confirm | null>(null);
  const [zipChoice, setZipChoice] = useState<File | null>(null);
  // A ref, not state: a fast double tap lands before the re-render.
  const acting = useRef(false);

  const run = (p: Promise<Resp>) => {
    setBusy(true);
    setError('');
    setNotice('');
    p.then((r) => {
      setAvatars(r.avatars);
      if (r.undo) setUndo(r.undo);
    })
      .catch((e) => setError(messageOf(e)))
      .finally(() => setBusy(false));
  };

  /** One post per tap, however fast the taps. */
  const once = (go: () => Promise<Resp>) => {
    if (acting.current) return;
    acting.current = true;
    run(
      go().finally(() => {
        acting.current = false;
      }),
    );
  };

  const stopSelecting = () => {
    setSelecting(false);
    setSelected(new Set());
    setLastPicked(null);
  };

  const pick = (a: AvatarItem) => {
    const next = new Set(selected);
    if (next.has(a.id)) {
      next.delete(a.id);
    } else {
      next.add(a.id);
      setLastPicked(a.isLook ? null : a);
    }
    setSelected(next);
  };

  const thumb = (id: string) => `${base}/avatars/${id}/image?w=128`;

  const removeIds = (ids: string[]) =>
    once(() => api.post<Resp>(`${base}/avatars/delete`, { ids }));

  const askDelete = (ids: string[]) =>
    setConfirm({
      title: ids.length === 1 ? 'Delete this image?' : `Delete ${ids.length} images?`,
      body: 'They leave the gallery; the portrait stays. Undo brings them back for a few seconds.',
      action: ids.length === 1 ? 'Delete' : `Delete ${ids.length}`,
      thumbs: ids.slice(0, 8).map(thumb),
      run: () => {
        stopSelecting();
        removeIds(ids);
      },
    });

  const askClear = (looksOnly: boolean, count: number) =>
    setConfirm({
      title: `Delete all ${count} ${looksOnly ? 'gallery looks' : 'expression images'}?`,
      body: `${
        looksOnly
          ? 'The portrait and the expression images stay.'
          : 'The portrait and the gallery looks stay.'
      } Undo brings them back for a few seconds.`,
      action: 'Delete all',
      thumbs: [],
      run: () =>
        once(() =>
          api.post<Resp>(`${base}/avatars/delete`, { clear: looksOnly ? 'looks' : 'expressions' }),
        ),
    });

  const undoNow = (handle: UndoHandle) => {
    setUndo(null);
    once(() => api.post<Resp>(`${base}/avatars/undo`, { batch: handle.batch }));
  };

  // The desktop gallery's "Import ZIP sprite pack": emotion-named images,
  // alternates as joy-1.png, joy-2.png.
  const importZip = (file: File, replace = false) =>
    run(
      api.upload<ZipResp>(`${base}/avatars/zip${replace ? '?replace=1' : ''}`, file).then((r) => {
        setNotice(
          [
            `Imported ${r.added}`,
            r.skipped > 0 ? `${r.skipped} skipped (${MAX_EXPRESSIONS} expressions)` : '',
            r.unrecognized > 0 ? `${r.unrecognized} unrecognized` : '',
          ]
            .filter(Boolean)
            .join(' · '),
        );
        return r;
      }),
    );

  // Looks: any image, uploaded as-is (a full outfit/scene shouldn't be square-cropped).
  const uploadLook = (file: File) =>
    run(api.upload<Resp>(`${base}/looks`, file));

  // Expressions: face-cropped (ImageCropModal) then uploaded with the emotion label.
  const uploadExpression = async (blob: Blob) => {
    setPending(null);
    const label = (labelRef.current?.value ?? '').trim();
    const q = label ? `?label=${encodeURIComponent(label)}` : '';
    const file = new File([blob], 'avatar.png', { type: blob.type || 'image/png' });
    run(
      api.upload<Resp>(`${base}/avatars${q}`, file).then((r) => {
        if (labelRef.current) labelRef.current.value = '';
        return r;
      }),
    );
  };

  const toggleFavorite = (a: AvatarItem) =>
    run(api.post(`${base}/favorite?avatarId=${a.isFavorite ? '' : a.id}`));

  const looks = avatars.filter((a) => a.isLook);
  const expressions = avatars.filter((a) => !a.isLook);
  const used = expressionCount(avatars);

  const sameLabel = (e: AvatarItem) =>
    !!lastPicked && e.label.trim().toLowerCase() === lastPicked.label.trim().toLowerCase();
  const alternates = expressions.filter(sameLabel).length;

  const batchTools = (items: AvatarItem[], looksOnly: boolean) =>
    items.length > 0 &&
    !selecting && (
      <div className="gallery-batch-tools">
        <button className="ghost small" disabled={busy} onClick={() => setSelecting(true)}>
          Select
        </button>
        <button
          className="ghost small danger"
          disabled={busy}
          onClick={() => askClear(looksOnly, items.length)}
        >
          {looksOnly ? 'Clear looks' : 'Clear expressions'}
        </button>
      </div>
    );

  // Desktop parity: the portrait ✕ is a SWAP — the ★ (else first) look
  // promotes into the portrait slot and the old portrait demotes into the
  // gallery (2026-08-14: nothing is destroyed any more). The confirm shows
  // the actual image that takes over, same as the desktop dialog.
  const [confirmSwap, setConfirmSwap] = useState<AvatarItem | null>(null);
  const requestSwapPortrait = () => {
    const candidate = looks.find((l) => l.isFavorite) ?? looks[0];
    if (candidate) setConfirmSwap(candidate);
  };
  const doSwapPortrait = () => {
    setConfirmSwap(null);
    run(api.post(`${base}/portrait/delete`));
  };

  const tile = (a: AvatarItem, withPrime: boolean) => (
    <div
      key={a.id}
      className={`avatar-tile${a.isPrime ? ' prime' : ''}${a.isFavorite ? ' favorite' : ''}${
        selecting ? ' selecting' : ''
      }${selected.has(a.id) ? ' selected' : ''}`}
      onClick={selecting ? () => pick(a) : undefined}
      role={selecting ? 'checkbox' : undefined}
      aria-checked={selecting ? selected.has(a.id) : undefined}
      aria-label={selecting ? `Select ${a.label || 'look'}` : undefined}
    >
      <img src={`${base}/avatars/${a.id}/image?w=256`} alt={a.label || 'avatar'} />
      {a.label && <span className="avatar-label">{a.label}</span>}
      {a.isFavorite && !selecting && <span className="avatar-badge">★ Default</span>}
      {selecting && (
        <span className={`select-check${selected.has(a.id) ? ' on' : ''}`}>
          {selected.has(a.id) ? '✓' : ''}
        </span>
      )}
      {!selecting && (
        <div className="avatar-actions">
          <button
            className="icon-btn"
            title={a.isFavorite ? 'Unset default face' : 'Use as default face (★)'}
            disabled={busy}
            onClick={() => toggleFavorite(a)}
          >
            {a.isFavorite ? '★' : '☆'}
          </button>
          {withPrime && !a.isPrime && (
            <button
              className="icon-btn"
              title="Set as the expression engine's default"
              disabled={busy}
              onClick={() => run(api.post(`${base}/avatars/${a.id}/prime`))}
            >
              📌
            </button>
          )}
          <button
            className="icon-btn"
            title="Delete"
            disabled={busy}
            onClick={() => askDelete([a.id])}
          >
            🗑
          </button>
        </div>
      )}
    </div>
  );

  return (
    <div className="avatar-manager">
      {/* ── Looks ─────────────────────────────────────────────── */}
      <div className="gallery-section-head">
        <span className="section-label">Looks</span>
        <div className="tool-row">
          {looks.length > 0 && (
            <button className="ghost" disabled={busy} onClick={requestSwapPortrait}>
              ⇄ Swap portrait
            </button>
          )}
          <button className="ghost" disabled={busy} onClick={() => lookRef.current?.click()}>
            {busy ? 'Working…' : '⬆ Upload look'}
          </button>
        </div>
      </div>
      {batchTools(looks, true)}
      {looks.length === 0 ? (
        <p className="muted gallery-empty">
          Upload alternate looks (outfits, scenes) — you can swipe between them in chat.
        </p>
      ) : (
        <div className="avatar-grid">{looks.map((a) => tile(a, false))}</div>
      )}

      {/* ── Expressions ───────────────────────────────────────── */}
      <div className="gallery-section-head">
        <span className="section-label">Expressions</span>
        <div className="tool-row">
          <input ref={labelRef} placeholder="Emotion (e.g. happy)" />
          <button className="ghost" disabled={busy} onClick={() => exprRef.current?.click()}>
            {busy ? 'Working…' : '⬆ Upload'}
          </button>
        </div>
      </div>
      {batchTools(expressions, false)}
      {expressions.length === 0 ? (
        <p className="muted gallery-empty">
          Upload emotion-labeled face images one at a time, or a ZIP sprite pack named by
          emotion (joy.png, joy-1.png, anger.png …).
        </p>
      ) : (
        <div className="avatar-grid">{expressions.map((a) => tile(a, true))}</div>
      )}
      {/* Under the tiles, as on the desktop gallery; wraps on a phone. */}
      <div className="gallery-section-foot">
        <button className="ghost" disabled={busy} onClick={() => zipRef.current?.click()}>
          Import ZIP sprite pack
        </button>
        <span className={`muted small${used >= MAX_EXPRESSIONS ? ' error' : ''}`}>
          {used}/{MAX_EXPRESSIONS} expressions
          {expressions.length > used ? ` · ${expressions.length} images` : ''}
        </span>
      </div>

      {selecting && (
        <GallerySelectBar
          count={selected.size}
          busy={busy}
          labelToSelect={alternates > 1 && lastPicked ? lastPicked.label : null}
          onSelectAll={() => setSelected(new Set(avatars.map((a) => a.id)))}
          onSelectLabel={() =>
            setSelected(new Set([...selected, ...expressions.filter(sameLabel).map((e) => e.id)]))
          }
          onCancel={stopSelecting}
          onDelete={() => askDelete([...selected])}
        />
      )}
      {undo && (
        <GalleryUndoBar
          key={undo.batch}
          message={
            undo.replaced > 0
              ? `Replaced ${undo.count} expression images with ${undo.replaced} from the pack`
              : `Deleted ${undo.count} ${undo.count === 1 ? 'image' : 'images'}`
          }
          seconds={undo.seconds}
          busy={busy}
          onUndo={() => undoNow(undo)}
          onExpire={() => setUndo(null)}
        />
      )}
      {notice && <p className="muted">{notice}</p>}
      {error && <p className="error">{error}</p>}

      {/* hidden inputs */}
      <input
        ref={lookRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) void uploadLook(f);
          e.target.value = '';
        }}
      />
      <input
        ref={exprRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0] ?? null;
          if (f) setPending(f);
          e.target.value = '';
        }}
      />
      <input
        ref={zipRef}
        type="file"
        accept=".zip,application/zip"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          // With expressions here, ask first: add to them, or replace them.
          if (f) {
            if (expressions.length > 0) setZipChoice(f);
            else importZip(f);
          }
          e.target.value = '';
        }}
      />
      {pending && (
        <ImageCropModal
          file={pending}
          onCancel={() => setPending(null)}
          onCropped={(blob) => void uploadExpression(blob)}
        />
      )}
      {confirmSwap && (
        <div className="drawer-backdrop center" onClick={() => setConfirmSwap(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-head">
              <span>Swap the portrait?</span>
              <button className="link-btn" onClick={() => setConfirmSwap(null)}>
                Close
              </button>
            </div>
            <div className="swap-preview">
              <img src={`${base}/avatars/${confirmSwap.id}/image?w=256`} alt="promoted look" />
              <p className="muted">
                This image — {confirmSwap.isFavorite ? 'your ★ starred look' : 'your first gallery look'} —
                becomes the new portrait, and the old portrait moves into the gallery as a look.
                Nothing is deleted; swap back any time.
              </p>
            </div>
            <div className="modal-actions">
              <button className="ghost" onClick={() => setConfirmSwap(null)}>
                Cancel
              </button>
              <button className="primary" onClick={doSwapPortrait}>
                Swap portrait
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
            {confirm.thumbs.length > 0 && (
              <div className="gallery-confirm-thumbs">
                {confirm.thumbs.map((src) => (
                  <img key={src} src={src} alt="" />
                ))}
              </div>
            )}
            <p className="muted">{confirm.body}</p>
            <div className="modal-actions">
              <button className="ghost" onClick={() => setConfirm(null)}>
                Cancel
              </button>
              <button
                className="danger-btn"
                onClick={() => {
                  const go = confirm.run;
                  setConfirm(null);
                  go();
                }}
              >
                {confirm.action}
              </button>
            </div>
          </div>
        </div>
      )}
      {zipChoice && (
        <div className="drawer-backdrop center" onClick={() => setZipChoice(null)}>
          <div
            className="modal"
            role="dialog"
            aria-label="Add or replace"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="drawer-head">
              <span>Add to these, or replace them?</span>
            </div>
            <p className="muted">
              This character has {expressions.length} expression{' '}
              {expressions.length === 1 ? 'image' : 'images'}. Replace deletes them first (the
              gallery looks stay); Undo brings them back for a few seconds.
            </p>
            <div className="modal-actions">
              <button className="ghost" onClick={() => setZipChoice(null)}>
                Cancel
              </button>
              <button
                className="ghost danger"
                onClick={() => {
                  const f = zipChoice;
                  setZipChoice(null);
                  importZip(f, true);
                }}
              >
                Replace them
              </button>
              <button
                className="primary"
                onClick={() => {
                  const f = zipChoice;
                  setZipChoice(null);
                  importZip(f);
                }}
              >
                Add to these
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
