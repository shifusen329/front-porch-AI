// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Visual novel mode on the phone: the cast on stage behind the chat log,
// each in the picture the desktop chose for them (their expression for how
// they feel, else their portrait), the last speaker in front. Desktop twin:
// lib/ui/chat_components/stage/visual_novel_stage.dart; who stands where
// and in which picture comes from the host (stageSpritesFor), never from
// here.

import type { ReactNode } from 'react';

/** One figure, as the chat state lists it. `v` changes when the picture does. */
export interface StageSprite {
  id: string;
  name: string;
  speaking: boolean;
  v: string;
}

export function stageImageUrl(s: StageSprite): string {
  return `/api/chat/stage/${encodeURIComponent(s.id)}?v=${encodeURIComponent(s.v)}`;
}

export function VisualNovelStage({ sprites }: { sprites: StageSprite[] }) {
  if (sprites.length === 0) return null;
  return (
    <div className="vn-stage" data-testid="vn-stage" aria-hidden>
      {sprites.map((s) => (
        <div key={s.id} className={`vn-sprite${s.speaking ? '' : ' back'}`}>
          {/* The key remounts the picture on a change, which plays the fade-in. */}
          <img key={s.v} src={stageImageUrl(s)} alt="" />
        </div>
      ))}
    </div>
  );
}

/** The chat log over the stage: a panel the handle grows to the full height
 * and back. */
export function VisualNovelLog({
  expanded,
  onToggle,
  children,
}: {
  expanded: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  return (
    <div className={`vn-log${expanded ? ' expanded' : ''}`} data-testid="vn-log">
      <button
        type="button"
        className="vn-handle"
        aria-label={expanded ? 'Show the stage' : 'Show the whole chat'}
        aria-expanded={expanded}
        onClick={onToggle}
      >
        <span aria-hidden />
      </button>
      {children}
    </div>
  );
}

/** [children] in the log panel when visual novel mode is [on], as they are
 * otherwise. */
export function MaybeVisualNovelLog({
  on,
  expanded,
  onToggle,
  children,
}: {
  on: boolean;
  expanded: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  if (!on) return <>{children}</>;
  return (
    <VisualNovelLog expanded={expanded} onToggle={onToggle}>
      {children}
    </VisualNovelLog>
  );
}
