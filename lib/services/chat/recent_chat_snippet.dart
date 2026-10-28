// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The one-line snippet under a Chats tab row. Plain Dart over a
// [RecentSession], so the phone UI and the web relay build the same line.

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

/// Longest snippet [recentChatSnippet] returns, in characters, before `…`.
const int kRecentChatSnippetMaxChars = 160;

/// The snippet for a message that is only a picture.
const String kRecentChatImageSnippet = 'Shared an image';

final MacroResolver _macros = MacroResolver();
final RegExp _htmlComment = RegExp(r'<!--.*?-->', dotAll: true);
final RegExp _space = RegExp(r'\s+');

/// The newest message in [session] that shows something on screen, as one
/// line: think blocks and HTML comments stripped, macros resolved
/// (`{{user}}` is the chat's persona, `{{char}}` the speaker), whitespace
/// folded. A group chat's line leads with the speaker ("Ines: …"); app
/// notices (sender `System`) carry no speaker. Null when no message in the
/// tail shows anything.
String? recentChatSnippet(RecentSession session) {
  for (final m in session.tail) {
    final context = MacroContext(
      userName: session.userName,
      characterName: session.isGroup && !m.isUser
          ? m.sender
          : session.displayName,
    );
    var body = _oneLine(_macros.resolve(stripThinkTags(m.text), context));
    if (body.isEmpty && m.hasImage) body = kRecentChatImageSnippet;
    if (body.isEmpty) continue;
    final speaker = session.isGroup && m.sender != 'System'
        ? _oneLine(_macros.resolve(m.sender, context))
        : '';
    return _clip(speaker.isEmpty ? body : '$speaker: $body');
  }
  return null;
}

String _oneLine(String text) =>
    text.replaceAll(_htmlComment, ' ').replaceAll(_space, ' ').trim();

String _clip(String text) {
  final runes = text.runes;
  if (runes.length <= kRecentChatSnippetMaxChars) return text;
  final cut = String.fromCharCodes(runes.take(kRecentChatSnippetMaxChars));
  return '${cut.trimRight()}…';
}
