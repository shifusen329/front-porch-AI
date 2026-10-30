// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Avatar Gallery's select bar and its Undo bar, for AvatarManager.
// Desktop twins: lib/ui/dialogs/avatar_gallery/avatar_gallery_select_bar.dart.

import { useEffect } from 'react';

export function GallerySelectBar({
  count,
  busy,
  labelToSelect,
  onSelectAll,
  onSelectLabel,
  onCancel,
  onDelete,
}: {
  count: number;
  busy: boolean;
  /** The last expression picked has alternates under this label. */
  labelToSelect: string | null;
  onSelectAll: () => void;
  onSelectLabel: () => void;
  onCancel: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="selection-bar gallery-select-bar" role="toolbar" aria-label="Selected pictures">
      <span className="sel-count">{count} selected</span>
      <div className="sel-actions">
        <button className="ghost small" onClick={onSelectAll}>
          Select all
        </button>
        {labelToSelect && (
          <button className="ghost small" onClick={onSelectLabel}>
            Select every “{labelToSelect}”
          </button>
        )}
        <button className="ghost small" onClick={onCancel}>
          Cancel
        </button>
        <button className="danger-btn small" disabled={busy || count === 0} onClick={onDelete}>
          Delete {count}
        </button>
      </div>
    </div>
  );
}

/** "Deleted 12 images · Undo" for [seconds], then it goes. */
export function GalleryUndoBar({
  message,
  seconds,
  busy,
  onUndo,
  onExpire,
}: {
  message: string;
  seconds: number;
  busy: boolean;
  onUndo: () => void;
  onExpire: () => void;
}) {
  useEffect(() => {
    const timer = window.setTimeout(onExpire, seconds * 1000);
    return () => window.clearTimeout(timer);
    // The bar is keyed by its batch, so a new removal starts a new timer.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return (
    <div className="undo-bar gallery-undo-bar" role="status">
      <span>{message}</span>
      <button className="ghost small" disabled={busy} onClick={onUndo}>
        Undo
      </button>
    </div>
  );
}
