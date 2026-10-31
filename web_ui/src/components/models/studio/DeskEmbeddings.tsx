// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef, useState } from 'react';
import { fetchEmbeddings } from './deskApi';
import type { Embedding, EmbeddingListing, ImageConfig } from './types';

/**
 * The embeddings on the desk, under the negative prompt. Each says whether it
 * goes in the prompt or the negative prompt; Add lists what the image server
 * has. A new pick is sent by name only and the app decides its side.
 */
export function DeskEmbeddings(props: {
  cfg: ImageConfig;
  save: (patch: Record<string, unknown>) => Promise<boolean>;
}) {
  const picks = props.cfg.embeddings ?? [];
  const [adding, setAdding] = useState(false);
  const write = (next: (Embedding | { name: string })[]) => void props.save({ embeddings: next });
  return (
    <div data-testid="desk-embeddings">
      <span>Embeddings</span>
      {picks.length === 0 ? (
        <p>None yet. Add one your image server has, such as a negative embedding made for your model.</p>
      ) : null}
      <ul>
        {picks.map((e) => (
          <li key={e.name}>
            <span>{e.name}</span>
            <select aria-label={`Where ${e.name} goes`} value={e.negative ? 'negative' : 'prompt'}
              onChange={(ev) => write(picks.map((p) => (p.name === e.name ? { name: p.name, negative: ev.target.value === 'negative' } : p)))}>
              <option value="prompt">Prompt</option>
              <option value="negative">Negative</option>
            </select>
            <button type="button" aria-label={`Remove ${e.name}`}
              onClick={() => write(picks.filter((p) => p.name !== e.name))}>×</button>
          </li>
        ))}
      </ul>
      <button type="button" onClick={() => setAdding(true)}>Add an embedding</button>
      {adding ? (
        <EmbeddingSheet
          taken={picks.map((e) => e.name)}
          onPick={(name) => {
            setAdding(false);
            write([...picks, { name }]);
          }}
          onClose={() => setAdding(false)}
        />
      ) : null}
    </div>
  );
}

function EmbeddingSheet(props: { taken: string[]; onPick: (name: string) => void; onClose: () => void }) {
  const [listing, setListing] = useState<EmbeddingListing | null>(null);
  // A second tap before the sheet closes must not add the name twice.
  const chosen = useRef(false);
  useEffect(() => {
    let live = true;
    fetchEmbeddings()
      .then((read) => live && setListing(read))
      .catch(() => live && setListing({ fits: [], others: [], problem: 'The list could not be read.' }));
    return () => {
      live = false;
    };
  }, []);
  const choose = (name: string) => {
    if (chosen.current) return;
    chosen.current = true;
    props.onPick(name);
  };
  const empty = listing && !listing.problem && listing.fits.length === 0 && listing.others.length === 0;
  return (
    <div className="fp-sheet" role="dialog" aria-label="Add an embedding">
      <button type="button" onClick={props.onClose}>Close</button>
      <h2>Add an embedding</h2>
      {listing == null ? <p>Reading the image server's embeddings…</p> : null}
      {listing?.problem ? <p>{listing.problem}</p> : null}
      {empty ? <p>The image server lists no embeddings.</p> : null}
      <ul>
        {(listing?.fits ?? []).map((name) => (
          <li key={name}>
            <button type="button" disabled={props.taken.includes(name)} onClick={() => choose(name)}>
              {props.taken.includes(name) ? `${name} ✓` : name}
            </button>
          </li>
        ))}
      </ul>
      {listing?.others.length ? (
        <>
          <p>Made for another kind of model, so the server skips these with the one it has loaded:</p>
          <ul>
            {listing.others.map((name) => <li key={name}>{name}</li>)}
          </ul>
        </>
      ) : null}
    </div>
  );
}
