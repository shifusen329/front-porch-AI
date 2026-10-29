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
// generation on the web (that lives on desktop).

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { ImageCropModal } from './ImageCropModal';

interface AvatarItem {
  id: string;
  label: string;
  displayOrder: number;
  isPrime: boolean;
  isLook: boolean;
  isFavorite: boolean;
}

type Resp = { avatars: AvatarItem[] };
type ZipResp = Resp & { added: number; skipped: number; unrecognized: number };

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
  return e instanceof ApiError && (e.status === 400 || e.status === 409)
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

  const run = (p: Promise<Resp>) => {
    setBusy(true);
    setError('');
    setNotice('');
    p.then((r) => setAvatars(r.avatars))
      .catch((e) => setError(messageOf(e)))
      .finally(() => setBusy(false));
  };

  // The desktop gallery's "Import ZIP sprite pack": emotion-named images,
  // alternates as joy-1.png, joy-2.png.
  const importZip = (file: File) =>
    run(
      api.upload<ZipResp>(`${base}/avatars/zip`, file).then((r) => {
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
      className={`avatar-tile${a.isPrime ? ' prime' : ''}${a.isFavorite ? ' favorite' : ''}`}
    >
      <img src={`${base}/avatars/${a.id}/image?w=256`} alt={a.label || 'avatar'} />
      {a.label && <span className="avatar-label">{a.label}</span>}
      {a.isFavorite && <span className="avatar-badge">★ Default</span>}
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
          onClick={() => run(api.post(`${base}/avatars/${a.id}/delete`))}
        >
          🗑
        </button>
      </div>
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
          if (f) importZip(f);
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
    </div>
  );
}
