// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Visual novel mode for the open chat: whether it is on and who stands on
// stage, read from the host (GET /api/chat/stage) whenever the chat moves
// on — a new chat, a new message, a reply starting or ending, a changed
// feeling or theme. The host decides; the page only draws.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { StageSprite } from '../../components/VisualNovelStage';

export interface ChatStage {
  visualNovel: boolean;
  stage: StageSprite[];
}

const OFF: ChatStage = { visualNovel: false, stage: [] };

export function useChatStage(changeKey: string): ChatStage {
  const [stage, setStage] = useState<ChatStage>(OFF);
  useEffect(() => {
    let cancelled = false;
    api
      .get<Partial<ChatStage>>('/api/chat/stage')
      .then((r) => {
        if (cancelled) return;
        setStage({ visualNovel: r.visualNovel === true, stage: r.stage ?? [] });
      })
      // An older host has no stage: the chat stays classic.
      .catch(() => !cancelled && setStage(OFF));
    return () => {
      cancelled = true;
    };
  }, [changeKey]);
  return stage;
}
