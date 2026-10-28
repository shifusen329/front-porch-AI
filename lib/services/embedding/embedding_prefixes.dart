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

/// Text an embedding model was trained to see before a search query and
/// before a stored passage. Retrieval quality drops without them on the
/// families listed here; any other model gets the text as it is.
///
/// Matched on the server's model id (`snowflake-arctic-embed-l-v2.0:latest`,
/// `BAAI/bge-small-en-v1.5`, …). The on-device engine keeps its own fixed
/// prefix and never comes here.
typedef EmbeddingPrefixes = ({String query, String document});

const _searchPassages =
    'Represent this sentence for searching relevant passages: ';

EmbeddingPrefixes embeddingPrefixesFor(String model) {
  final m = model.toLowerCase();
  if (m.contains('nomic-embed')) {
    return (query: 'search_query: ', document: 'search_document: ');
  }
  if (m.contains('arctic-embed')) {
    // v2.0 moved to e5-style query prefixes; v1 and v1.5 kept bge's.
    return (
      query: m.contains('v2') ? 'query: ' : _searchPassages,
      document: '',
    );
  }
  if (m.contains('e5-') || m.contains('e5_')) {
    return (query: 'query: ', document: 'passage: ');
  }
  if (m.contains('bge-m3')) return (query: '', document: '');
  if (m.contains('bge-') || m.contains('mxbai-embed')) {
    return (query: _searchPassages, document: '');
  }
  if (m.contains('qwen3-embedding') || m.contains('gte-qwen')) {
    return (
      query:
          'Instruct: Given the latest lines of a conversation, retrieve '
          'earlier passages of the story that are relevant to them\nQuery: ',
      document: '',
    );
  }
  return (query: '', document: '');
}
