// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Chats tab's read-only query: the most recent chats, 1:1 and group
// mixed, each with the end of its transcript. A plain library, not a part
// (the Drift part list is frozen); `database.dart` re-exports it. No schema
// change. The row's snippet is built by `recentChatSnippet`
// (lib/services/chat/recent_chat_snippet.dart).

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';

/// How many of a chat's newest live messages [RecentSession.tail] holds:
/// enough to step back past a reply that shows nothing (thinking only).
const int kRecentSessionTailSize = 4;

/// One stored message from the end of a recent chat.
class RecentSessionMessage {
  /// The speaker's name as stored on the row (`messages.sender`).
  final String sender;
  final bool isUser;

  /// The swipe on screen, as stored: think tags and macros left in.
  final String text;

  /// The swipe on screen is a picture (generated, or a photo the user sent).
  final bool hasImage;

  const RecentSessionMessage({
    required this.sender,
    required this.isUser,
    required this.text,
    this.hasImage = false,
  });
}

/// One chat for the Chats tab. See [AppDatabaseRecentSessions].
class RecentSession {
  final String sessionId;

  /// `groups.id` of a group chat; null for a 1:1 chat.
  final String? groupId;

  /// `characters.id` of a 1:1 chat's character: the library card's UUID
  /// (`CharacterCard.dbId`), not its stableGroupId. Null for a group chat.
  final String? characterId;

  /// The character's name (1:1) or the group's name.
  final String displayName;

  /// The name the user gave this chat (Edit Chat Session), or null.
  final String? sessionName;

  /// Who the user speaks as here: the chat's persona, else the default
  /// persona, else 'User'. What `{{user}}` reads in the snippet.
  final String userName;

  /// When the newest live message was written.
  final DateTime lastMessageAt;

  /// Live (not soft-deleted) messages in the chat.
  final int messageCount;

  /// The newest live messages, newest first, at most
  /// [kRecentSessionTailSize].
  final List<RecentSessionMessage> tail;

  const RecentSession({
    required this.sessionId,
    required this.groupId,
    required this.characterId,
    required this.displayName,
    required this.sessionName,
    required this.userName,
    required this.lastMessageAt,
    required this.messageCount,
    required this.tail,
  });

  bool get isGroup => groupId != null;
}

/// A chat with a `group_id` is a group chat, named from `groups`; any other
/// is 1:1, and its `character_id` is `characters.id`. A chat whose owner is
/// gone or soft-deleted is left out (the history picker cannot open it).
/// `last_at` falls back to the session row for messages from before the
/// column carried a time.
const String _recentHeadsSql = '''
SELECT s.id, s.group_id, s.name,
  CASE WHEN s.group_id IS NULL THEN s.character_id END AS character_id,
  CASE WHEN s.group_id IS NULL THEN c.name ELSE g.name END AS owner_name,
  COALESCE(
    (SELECT p.name FROM personas p
      WHERE p.id = s.user_persona_id AND p.deleted_at IS NULL),
    (SELECT p.name FROM personas p WHERE p.deleted_at IS NULL
      ORDER BY p.is_active DESC, p.rowid LIMIT 1),
    'User') AS user_name,
  COALESCE(NULLIF(MAX(m.updated_at), 0), s.updated_at) AS last_at,
  COUNT(*) AS cnt
FROM sessions s
JOIN messages m ON m.session_id = s.id AND m.deleted_at IS NULL
LEFT JOIN characters c ON c.id = s.character_id AND c.deleted_at IS NULL
LEFT JOIN groups g ON g.id = s.group_id AND g.deleted_at IS NULL
WHERE s.deleted_at IS NULL
  AND (CASE WHEN s.group_id IS NULL THEN c.id ELSE g.id END) IS NOT NULL
GROUP BY s.id
ORDER BY last_at DESC, s.rowid DESC
LIMIT ?
''';

extension AppDatabaseRecentSessions on AppDatabase {
  /// The [limit] chats whose last live message is newest, newest first,
  /// 1:1 and group mixed. Read-only. Soft-deleted chats and messages are
  /// left out, and so is a chat with no live message.
  Future<List<RecentSession>> getRecentSessions(int limit) async {
    if (limit <= 0) return const [];
    final heads = await customSelect(
      _recentHeadsSql,
      variables: [Variable.withInt(limit)],
    ).get();
    if (heads.isEmpty) return const [];
    final tails = await _recentTails([
      for (final h in heads) h.read<String>('id'),
    ]);
    return [
      for (final h in heads)
        RecentSession(
          sessionId: h.read<String>('id'),
          groupId: h.readNullable<String>('group_id'),
          characterId: h.readNullable<String>('character_id'),
          displayName: h.read<String>('owner_name'),
          sessionName: _blankToNull(h.readNullable<String>('name')),
          userName: h.read<String>('user_name'),
          lastMessageAt: h.read<DateTime>('last_at'),
          messageCount: h.read<int>('cnt'),
          tail: tails[h.read<String>('id')] ?? const [],
        ),
    ];
  }

  Future<Map<String, List<RecentSessionMessage>>> _recentTails(
    List<String> sessionIds,
  ) async {
    final marks = List.filled(sessionIds.length, '?').join(',');
    final rows = await customSelect(
      'SELECT session_id, sender, is_user, swipes, swipe_index, metadata, '
      'swipe_metadata FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY '
      'session_id ORDER BY position DESC) AS rn FROM messages '
      'WHERE session_id IN ($marks) AND deleted_at IS NULL) '
      'WHERE rn <= ? ORDER BY session_id, rn',
      variables: [
        for (final id in sessionIds) Variable.withString(id),
        Variable.withInt(kRecentSessionTailSize),
      ],
    ).get();
    final out = <String, List<RecentSessionMessage>>{};
    for (final r in rows) {
      (out[r.read<String>('session_id')] ??= []).add(_tailMessage(r));
    }
    return out;
  }
}

/// The swipe on screen, chosen the way hydration does: an out-of-range
/// index shows swipe 0, and per-swipe metadata wins over the row's.
RecentSessionMessage _tailMessage(QueryRow r) {
  final swipes = _jsonList(r.read<String>('swipes'));
  final at = r.read<int>('swipe_index');
  final i = at >= 0 && at < swipes.length ? at : 0;
  final perSwipe = _jsonList(r.readNullable<String>('swipe_metadata'));
  final meta =
      (i < perSwipe.length ? perSwipe[i] : null) ??
      _json(r.readNullable<String>('metadata'));
  return RecentSessionMessage(
    sender: r.read<String>('sender'),
    isUser: r.read<bool>('is_user'),
    text: swipes.isEmpty ? '' : '${swipes[i] ?? ''}',
    hasImage:
        meta is Map &&
        (meta['is_generated_image'] == true || meta['is_user_image'] == true),
  );
}

Object? _json(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException catch (e) {
    debugPrint('[RecentSessions] unreadable message JSON: $e');
    return null;
  }
}

List<Object?> _jsonList(String? raw) {
  final v = _json(raw);
  return v is List ? v : const [];
}

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s;
