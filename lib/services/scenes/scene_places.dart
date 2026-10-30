// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

/// Other words that put a character in a place. A picture named for the key
/// also matches these, and one named for any of these also matches the key.
/// Kept to words that rarely mean anything else: "deck" (cards) and
/// "counter" (any shop) misfired.
const kScenePlaceSynonyms = <String, List<String>>{
  'porch': ['veranda', 'verandah', 'stoop', 'front steps', 'porch swing'],
  'bedroom': ['bed'],
  'living room': ['couch', 'sofa', 'lounge'],
  'bathroom': ['shower', 'bathtub', 'tub', 'bath'],
  'kitchen': ['stove'],
  'yard': ['backyard', 'back yard', 'lawn'],
  'forest': ['woods', 'woodland'],
  'beach': ['shore', 'seaside'],
  'tavern': ['inn', 'pub'],
  'office': ['desk'],
  'car': ['driver seat', 'passenger seat'],
  'street': ['sidewalk', 'road'],
  'library': ['bookshelves', 'stacks'],
  'garden': ['greenhouse'],
};

/// Places a character can be in that end the current scene even when there
/// is no picture of them: after "walks into the hallway" the porch must go.
const kKnownScenePlaces = <String>[
  'hallway', 'hall', 'stairs', 'staircase', 'attic', 'basement', 'cellar', //
  'garage', 'closet', 'dining room', 'study', 'den', 'balcony', 'rooftop',
  'roof', 'patio', 'garden', 'yard', 'driveway', 'office', 'classroom',
  'school', 'library', 'shop', 'store', 'market', 'cafe', 'café',
  'restaurant', 'bar', 'club', 'tavern', 'church', 'temple', 'hospital',
  'gym', 'pool', 'park', 'street', 'alley', 'city', 'town', 'village',
  'station', 'train', 'bus', 'car', 'ship', 'boat', 'plane', 'beach',
  'forest', 'river', 'lake', 'field', 'meadow', 'mountain', 'cave', 'camp',
  'tent', 'castle', 'throne room', 'dungeon', 'barn', 'stable', 'farm',
  'kitchen', 'bedroom', 'bathroom', 'living room', 'porch',
];
