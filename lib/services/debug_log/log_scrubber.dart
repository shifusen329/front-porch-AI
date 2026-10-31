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

/// What a secret is replaced with in the debug log.
const kRedacted = '[redacted]';

const _secretNames =
    r'api[_-]?key|apikey|x-api-key|access[_-]?token|refresh[_-]?token|'
    r'auth[_-]?token|token|secret|client[_-]?secret|password|passwd|'
    r'authorization|cookie|session';

final _bearer = RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}');
final _jsonField = RegExp(
  '"($_secretNames)"\\s*:\\s*"[^"]*"',
  caseSensitive: false,
);
final _queryField = RegExp(
  '([?&;]($_secretNames|key)=)[^&\\s"\'#]+',
  caseSensitive: false,
);
final _header = RegExp(
  r'\b(authorization|x-api-key|api-key|cookie|set-cookie)\s*:\s*'
  r'(?!(?:Bearer|Basic)\s)[^\s,}]+',
  caseSensitive: false,
);

// Keys that are recognisable on their own: OpenAI, Anthropic and OpenRouter
// (sk-), xAI, Groq, Hugging Face, Google, GitHub, Replicate and NVIDIA.
final _knownKey = RegExp(
  r'\b(sk-[A-Za-z0-9_-]{16,}|xai-[A-Za-z0-9]{20,}|gsk_[A-Za-z0-9]{20,}|'
  r'hf_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|ghp_[A-Za-z0-9]{20,}|'
  r'github_pat_[A-Za-z0-9_]{20,}|r8_[A-Za-z0-9]{20,}|nvapi-[A-Za-z0-9_-]{20,})',
);

/// [line] with API keys, tokens, passwords and cookies blanked out, so a
/// debug log can be shared. Chat text is left as it is.
String scrubSecrets(String line) => line
    .replaceAllMapped(_bearer, (m) => '${m[1]} $kRedacted')
    .replaceAllMapped(_jsonField, (m) => '"${m[1]}": "$kRedacted"')
    .replaceAllMapped(_queryField, (m) => '${m[1]}$kRedacted')
    .replaceAllMapped(_header, (m) => '${m[1]}: $kRedacted')
    .replaceAll(_knownKey, kRedacted);
