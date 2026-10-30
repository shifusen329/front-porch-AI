// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Visual novel mode and the scene background for the open chat: whether it
// is a visual novel, who stands on stage, and the picture of where the scene
// is, read from the host (GET /api/chat/stage) whenever the chat moves on —
// a new chat, a new message, a reply starting or ending, a changed feeling,
// theme or scene. The host decides; the page only draws.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { StageSprite } from '../../components/VisualNovelStage';

/** The scene picture behind the chat: `who` and `v` name its file. */
export interface ChatScene {
  who: string;
  v: string;
  place: string;
  time: string;
}

export interface ChatStage {
  visualNovel: boolean;
  stage: StageSprite[];
  scene: ChatScene | null;
}

const OFF: ChatStage = { visualNovel: false, stage: [], scene: null };

export function useChatStage(changeKey: string): ChatStage {
  const [stage, setStage] = useState<ChatStage>(OFF);
  useEffect(() => {
    let cancelled = false;
    api
      .get<Partial<ChatStage>>('/api/chat/stage')
      .then((r) => {
        if (cancelled) return;
        setStage({
          visualNovel: r.visualNovel === true,
          stage: r.stage ?? [],
          // An older host sends no scene: the chat keeps its background.
          scene: r.scene ?? null,
        });
      })
      // An older host has no stage: the chat stays classic.
      .catch(() => !cancelled && setStage(OFF));
    return () => {
      cancelled = true;
    };
  }, [changeKey]);
  return stage;
}
