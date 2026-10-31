// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → Appearance → Chat Appearance → Show markdown
// formatting in messages (desktop: chat_appearance_section.dart). Messages
// on screen follow the switch at once (useChatMarkdown).

import { useState } from 'react';
import { api } from '../api/client';
import { setChatMarkdown, useChatMarkdown } from '../hooks/useChatMarkdown';

export function ChatMarkdownSettings() {
  const on = useChatMarkdown();
  const [problem, setProblem] = useState('');

  const commit = (next: boolean) => {
    const before = on;
    setChatMarkdown(next);
    setProblem('');
    api.post('/api/settings', { chatMarkdown: next }).catch(() => {
      setChatMarkdown(before);
      setProblem('That could not be saved. Check that the app is running, then try again.');
    });
  };

  return (
    <section className="card" data-testid="chat-markdown-card">
      <h3>Show markdown formatting in messages</h3>
      <p className="reading-blurb">
        Text between *stars* shows in italics, **two stars** in bold, ~~tildes~~ struck through
        and `backticks` as code, without the marks. Off shows messages exactly as written.
      </p>
      <label>
        <input
          type="checkbox"
          checked={on}
          onChange={(e) => commit(e.target.checked)}
          aria-label="Show markdown formatting in messages"
        />
        {' '}Show markdown formatting in messages
      </label>
      {problem && (
        <p className="small rag-engine-error" role="alert">
          {problem}
        </p>
      )}
    </section>
  );
}
