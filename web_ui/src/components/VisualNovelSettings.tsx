// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → Appearance → Chat Appearance → Visual novel mode
// (desktop: chat_appearance_section.dart). A chat can choose for itself in
// its Chat settings (ChatThemeSettings).

import { useEffect, useState } from 'react';
import { api } from '../api/client';

export function VisualNovelSettings() {
  const [on, setOn] = useState(false);
  const [problem, setProblem] = useState('');

  useEffect(() => {
    let cancelled = false;
    api
      .get<{ visualNovelMode?: boolean }>('/api/settings')
      .then((r) => {
        if (!cancelled && typeof r.visualNovelMode === 'boolean') setOn(r.visualNovelMode);
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
    api.post('/api/settings', { visualNovelMode: next }).catch(() => {
      setOn(before);
      setProblem('That could not be saved. Check that the app is running, then try again.');
    });
  };

  return (
    <section className="card" data-testid="visual-novel-card">
      <h3>Visual novel mode</h3>
      <p className="reading-blurb">
        The characters stand on stage with the chat in a panel over them. Each shows their
        expression image for how they feel, or their portrait. A chat can choose for itself in
        its Chat settings.
      </p>
      <label>
        <input
          type="checkbox"
          checked={on}
          onChange={(e) => commit(e.target.checked)}
          aria-label="Visual novel mode"
        />
        {' '}Visual novel mode
      </label>
      {problem && (
        <p className="small rag-engine-error" role="alert">
          {problem}
        </p>
      )}
    </section>
  );
}
