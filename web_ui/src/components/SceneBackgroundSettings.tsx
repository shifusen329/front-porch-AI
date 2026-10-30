// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → Appearance → Chat Appearance → Backgrounds follow
// the scene (desktop: chat_appearance_section.dart). A chat can choose for
// itself in its Chat settings (ChatThemeSettings).

import { useEffect, useState } from 'react';
import { api } from '../api/client';

export function SceneBackgroundSettings() {
  const [on, setOn] = useState(true);
  const [problem, setProblem] = useState('');

  useEffect(() => {
    let cancelled = false;
    api
      .get<{ sceneBackgrounds?: boolean }>('/api/settings')
      .then((r) => {
        if (!cancelled && typeof r.sceneBackgrounds === 'boolean') setOn(r.sceneBackgrounds);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  const commit = (next: boolean) => {
    const before = on;
    setOn(next);
    setProblem('');
    api.post('/api/settings', { sceneBackgrounds: next }).catch(() => {
      setOn(before);
      setProblem('That could not be saved. Check that the app is running, then try again.');
    });
  };

  return (
    <section className="card" data-testid="scene-backgrounds-card">
      <h3>Backgrounds follow the scene</h3>
      <p className="reading-blurb">
        With the Realism Engine on, the chat background shows the place the character is in, when
        they have a picture of it in their Scenes. A chat can choose for itself in its Chat
        settings.
      </p>
      <label>
        <input
          type="checkbox"
          checked={on}
          onChange={(e) => commit(e.target.checked)}
          aria-label="Backgrounds follow the scene"
        />
        {' '}Backgrounds follow the scene
      </label>
      {problem && (
        <p className="small rag-engine-error" role="alert">
          {problem}
        </p>
      )}
    </section>
  );
}
