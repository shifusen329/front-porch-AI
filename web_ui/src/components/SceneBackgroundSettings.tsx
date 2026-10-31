// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → Appearance → Chat Appearance → Backgrounds follow
// the scene and Paint missing places with the image generator (desktop:
// chat_appearance_section.dart). A chat can choose for itself in its Chat
// settings (ChatThemeSettings).

import { useEffect, useState } from 'react';
import { api } from '../api/client';

type SceneSwitch = 'sceneBackgrounds' | 'scenePainting';

export function SceneBackgroundSettings() {
  const [on, setOn] = useState<Record<SceneSwitch, boolean>>({
    sceneBackgrounds: true,
    scenePainting: true,
  });
  const [problem, setProblem] = useState('');

  useEffect(() => {
    let cancelled = false;
    api
      .get<Partial<Record<SceneSwitch, boolean>>>('/api/settings')
      .then((r) => {
        if (cancelled) return;
        setOn((was) => ({
          sceneBackgrounds:
            typeof r.sceneBackgrounds === 'boolean' ? r.sceneBackgrounds : was.sceneBackgrounds,
          // An older host has no painting switch: it shows on, and does nothing.
          scenePainting:
            typeof r.scenePainting === 'boolean' ? r.scenePainting : was.scenePainting,
        }));
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  const commit = (key: SceneSwitch, next: boolean) => {
    const before = on[key];
    setOn((was) => ({ ...was, [key]: next }));
    setProblem('');
    api.post('/api/settings', { [key]: next }).catch(() => {
      setOn((was) => ({ ...was, [key]: before }));
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
          checked={on.sceneBackgrounds}
          onChange={(e) => commit('sceneBackgrounds', e.target.checked)}
          aria-label="Backgrounds follow the scene"
        />
        {' '}Backgrounds follow the scene
      </label>
      <p className="reading-blurb">
        When the story goes somewhere with no picture, the chat model describes it for your image
        generator and the picture is saved to the character’s Scenes, one for the day and one for
        the night. Needs Image Generation on (Voice &amp; Media) and a server set up in the Image
        Studio, whose Advanced → Prompt format picks Danbooru tags or sentences.
      </p>
      <label>
        <input
          type="checkbox"
          checked={on.scenePainting}
          onChange={(e) => commit('scenePainting', e.target.checked)}
          aria-label="Paint missing places with the image generator"
        />
        {' '}Paint missing places with the image generator
      </label>
      {problem && (
        <p className="small rag-engine-error" role="alert">
          {problem}
        </p>
      )}
    </section>
  );
}
