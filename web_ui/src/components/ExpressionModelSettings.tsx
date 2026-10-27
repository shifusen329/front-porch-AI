// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Local ONNX expression classifier's Hugging Face model, set from the web
// Voice & Media card. Desktop twin: ExpressionModelField
// (lib/ui/settings/tabs/voice_media_tab/expression_model_field.dart). The
// desktop downloads the model the next time it classifies a reply.

import { useRef, useState } from 'react';
import { api, ApiError } from '../api/client';

export interface ExpressionModelStatus {
  expressionModel?: string;
  expressionModelDefault?: string;
  /** The labels the model gives once it is on the desktop; null before. */
  expressionModelLabels?: string[] | null;
}

/** The go-emotions labels every model shares; anything else is the model's own. */
const STANDARD = new Set([
  'admiration', 'affection', 'amusement', 'anger', 'annoyance', 'anticipation',
  'approval', 'caring', 'confusion', 'curiosity', 'desire', 'disappointment',
  'disapproval', 'disgust', 'embarrassment', 'excitement', 'fear', 'gratitude',
  'grief', 'joy', 'love', 'nervousness', 'optimism', 'pride', 'realization',
  'relief', 'remorse', 'sadness', 'surprise', 'neutral',
]);

export function ExpressionModelSettings<T extends ExpressionModelStatus>({
  status,
  onSaved,
}: {
  status: T;
  onSaved: (next: T) => void;
}) {
  const [draft, setDraft] = useState(status.expressionModel ?? '');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  // A ref, not the state: a fast double click lands before the re-render.
  const savingNow = useRef(false);

  const use = async (model: string) => {
    if (savingNow.current) return;
    savingNow.current = true;
    setSaving(true);
    setError('');
    try {
      const next = await api.post<T>('/api/voice/settings', { expressionModel: model });
      onSaved(next);
      setDraft(next.expressionModel ?? '');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not reach the desktop app.');
    } finally {
      savingNow.current = false;
      setSaving(false);
    }
  };

  const labels = status.expressionModelLabels;
  const own = (labels ?? []).filter((l) => !STANDARD.has(l));

  return (
    <>
      <label className="row-label">
        <span>Expression model (Local ONNX)</span>
        <input
          aria-label="Expression model"
          value={draft}
          placeholder="owner/name on Hugging Face"
          disabled={saving}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') void use(draft);
          }}
        />
      </label>
      <div className="row-label">
        <button className="ghost" disabled={saving} onClick={() => void use(draft)}>
          Use
        </button>
        <button className="ghost" disabled={saving} onClick={() => void use('')}>
          Default model
        </button>
      </div>
      <p className="muted small" role="status">
        {error ||
          (labels == null
            ? 'The desktop downloads it the next time it reads a reply; its labels show here then.'
            : own.length === 0
              ? `${labels.length} labels, all standard ones.`
              : `${labels.length} labels. Its own, for tagging images: ${own.join(', ')}`)}
      </p>
    </>
  );
}
