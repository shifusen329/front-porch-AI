// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The scene background on the phone: the picture of where the character is,
// over the chat's own background, cross-fading when the place changes and
// fading out when the scene ends. Desktop twin:
// lib/ui/chat_components/stage/scene_backdrop_layer.dart; which picture
// comes from the host (SceneBackdrop), never from here.

import { useEffect, useRef, useState } from 'react';
import type { ChatScene } from '../pages/chat/useChatStage';

export function sceneImageUrl(s: ChatScene): string {
  return `/api/chat/scene/image?who=${encodeURIComponent(s.who)}&v=${encodeURIComponent(s.v)}`;
}

interface Layer {
  key: string;
  url: string;
  leaving: boolean;
}

const stillMotion = () =>
  typeof window !== 'undefined' &&
  typeof window.matchMedia === 'function' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export function SceneBackdrop({ scene }: { scene: ChatScene | null }) {
  const [layers, setLayers] = useState<Layer[]>([]);
  const host = useRef<HTMLDivElement>(null);
  const key = scene ? `${scene.who}/${scene.v}` : '';

  useEffect(() => {
    let cancelled = false;
    if (!scene) {
      setLayers((ls) => (stillMotion() ? [] : ls.map((l) => ({ ...l, leaving: true }))));
      return;
    }
    const url = sceneImageUrl(scene);
    // Decode first, so the fade never starts from a blank frame.
    const img = new Image();
    img.src = url;
    const ready = typeof img.decode === 'function' ? img.decode().catch(() => {}) : Promise.resolve();
    void ready.then(() => {
      if (cancelled) return;
      // The picture showing stays underneath while the new one fades in.
      setLayers((ls) => [
        ...ls.filter((l) => !l.leaving && l.key !== key).slice(-1),
        { key, url, leaving: false },
      ]);
    });
    return () => {
      cancelled = true;
    };
    // `key` names the picture; the rest of `scene` follows it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  // The chat view lifts its children over the scene only while one shows.
  useEffect(() => {
    const view = host.current?.parentElement;
    view?.classList.toggle('has-scene', layers.length > 0);
    return () => view?.classList.remove('has-scene');
  }, [layers.length]);

  const settle = (layer: Layer) =>
    setLayers((ls) =>
      layer.leaving
        ? ls.filter((l) => l.key !== layer.key)
        : ls.filter((l) => l.key === layer.key || l.leaving),
    );

  return (
    <div className="chat-scene" ref={host} aria-hidden data-testid="chat-scene">
      {layers.map((l) => (
        <div
          key={l.key}
          className={`chat-scene-layer${l.leaving ? ' leaving' : ''}`}
          data-scene={l.key}
          style={{ backgroundImage: `url("${l.url}")` }}
          onAnimationEnd={() => settle(l)}
        />
      ))}
    </div>
  );
}
