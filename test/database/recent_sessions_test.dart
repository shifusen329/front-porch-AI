// The Chats tab lists recent chats, 1:1 and group mixed, newest last message
// first. Each row is named from the right table (a 1:1 chat stores the
// card's UUID, a group chat the group id), and its snippet is the last
// message that shows on screen: no thinking, no raw {{char}} / {{user}}, and
// in a group the speaker up front. Soft-deleted rows never show.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  late AppDatabase db;
  var seq = 0;
  final gone = DateTime(2026, 1, 1);
  DateTime at(int hour) => DateTime(2026, 10, 1, hour);

  setUp(() => db = AppDatabase.forTesting(sameIsolate: true));
  tearDown(() async => db.close());

  Future<void> character(
    String id,
    String name, {
    String? imagePath,
    bool deleted = false,
  }) => db
      .into(db.characters)
      .insert(
        CharactersCompanion.insert(
          id: id,
          name: name,
          imagePath: Value(imagePath),
          deletedAt: deleted ? Value(gone) : const Value.absent(),
        ),
      );

  Future<void> group(String id, String name, {bool deleted = false}) => db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(
          id: id,
          name: name,
          deletedAt: deleted ? Value(gone) : const Value.absent(),
        ),
      );

  Future<void> chat(
    String id, {
    String? characterId,
    String? groupId,
    String? name,
    String? personaId,
    DateTime? savedAt,
    bool deleted = false,
  }) => db.insertSession(
    SessionsCompanion.insert(
      id: id,
      characterId: Value(characterId),
      groupId: Value(groupId),
      name: Value(name),
      userPersonaId: Value(personaId),
      updatedAt: savedAt == null ? const Value.absent() : Value(savedAt),
      deletedAt: deleted ? Value(gone) : const Value.absent(),
    ),
  );

  Future<void> say(
    String sessionId,
    String sender,
    String text, {
    required DateTime at,
    bool isUser = false,
    String? characterId,
    Map<String, dynamic>? metadata,
    bool deleted = false,
  }) {
    final n = seq++;
    return db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'm$n',
            sessionId: sessionId,
            position: n,
            sender: sender,
            isUser: isUser,
            characterId: Value(characterId),
            swipes: Value(jsonEncode([text])),
            metadata: Value(metadata == null ? null : jsonEncode(metadata)),
            updatedAt: Value(at),
            deletedAt: deleted ? Value(gone) : const Value.absent(),
          ),
        );
  }

  Future<void> persona(String id, String name, {bool isDefault = false}) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          name: Value(name),
          isActive: Value(isDefault),
        ),
      );

  test('newest last message first, not the order chats were saved in, '
      'and the limit cuts the list', () async {
    await character('c-mira', 'Mira');
    // Opening a chat bumps the session row, so the row's own time must not
    // decide the order: the oldest message's chat was saved last.
    await chat('old-chat-new-reply', characterId: 'c-mira', savedAt: at(1));
    await chat('new-chat-old-reply', characterId: 'c-mira', savedAt: at(23));
    await chat('middle', characterId: 'c-mira', savedAt: at(2));
    await say('new-chat-old-reply', 'Mira', 'first', at: at(8));
    await say('old-chat-new-reply', 'Mira', 'early', at: at(7));
    await say('old-chat-new-reply', 'Mira', 'latest', at: at(12));
    await say('middle', 'Mira', 'mid', at: at(10));

    final all = await db.getRecentSessions(10);
    expect(all.map((s) => s.sessionId), [
      'old-chat-new-reply',
      'middle',
      'new-chat-old-reply',
    ]);
    expect(all.first.lastMessageAt, at(12));
    expect(all.first.messageCount, 2);
    expect(recentChatSnippet(all.first), 'latest');

    final two = await db.getRecentSessions(2);
    expect(two.map((s) => s.sessionId), ['old-chat-new-reply', 'middle']);
    expect(await db.getRecentSessions(0), isEmpty);
  });

  test('a 1:1 row is named from characters.id, a group row from groups, '
      'and the group snippet leads with its speaker', () async {
    await persona('p-alex', 'Alex', isDefault: true);
    // sessions.character_id holds the card's UUID; the image basename (the
    // card's stableGroupId) is a different string and keys nothing here.
    await character('5f0c1e2a-uuid', 'Mira', imagePath: 'mira_portrait.png');
    await group('g-7d1b', 'Porch Trio');
    await chat('solo', characterId: '5f0c1e2a-uuid', name: 'Rainy day');
    await chat('trio', groupId: 'g-7d1b');
    await say('solo', 'Mira', 'Tea?', at: at(9));
    await say('trio', 'Alex', 'Morning all', isUser: true, at: at(10));
    await say(
      'trio',
      'Ines',
      '<think>Tease {{user}} a little.</think>{{char}} grins at {{user}}.',
      characterId: 'member-ines-uuid',
      at: at(11),
    );

    final rows = await db.getRecentSessions(10);
    final byId = {for (final r in rows) r.sessionId: r};

    final solo = byId['solo']!;
    expect(solo.isGroup, isFalse);
    expect(solo.characterId, '5f0c1e2a-uuid');
    expect(solo.groupId, isNull);
    expect(solo.displayName, 'Mira');
    expect(solo.sessionName, 'Rainy day');
    expect(recentChatSnippet(solo), 'Tea?');

    final trio = byId['trio']!;
    expect(trio.isGroup, isTrue);
    expect(trio.groupId, 'g-7d1b');
    expect(trio.characterId, isNull);
    expect(trio.displayName, 'Porch Trio');
    expect(trio.sessionName, isNull);
    expect(trio.messageCount, 2);
    expect(recentChatSnippet(trio), 'Ines: Ines grins at Alex.');
  });

  test('the snippet skips a reply that only thought, strips think tags and '
      'resolves {{char}} / {{user}} from the chat\'s own persona', () async {
    await persona('p-sam', 'Sam', isDefault: true);
    await persona('p-alex', 'Alex');
    await character('c-mira', 'Mira');
    await group('g-1', 'Night Shift');

    await chat('own-persona', characterId: 'c-mira', personaId: 'p-alex');
    await say(
      'own-persona',
      'Mira',
      '<think>She should greet {{user}}.</think>{{char}} waves at {{user}}.',
      at: at(9),
    );
    // Cut off mid-thought: the bubble shows nothing, so neither does the row.
    await say('own-persona', 'Mira', '<think>still planning the', at: at(10));

    await chat('default-persona', characterId: 'c-mira');
    await say(
      'default-persona',
      'Sam',
      'Hi {{char}}, it is {{user}}.',
      isUser: true,
      at: at(8),
    );

    await chat('picture', groupId: 'g-1');
    await say('picture', 'Sam', 'Show me', isUser: true, at: at(6));
    await say(
      'picture',
      'Kit',
      '',
      metadata: {'is_generated_image': true, 'image_path': 'kit.png'},
      at: at(7),
    );

    final rows = await db.getRecentSessions(10);
    final byId = {for (final r in rows) r.sessionId: r};
    expect(recentChatSnippet(byId['own-persona']!), 'Mira waves at Alex.');
    expect(recentChatSnippet(byId['default-persona']!), 'Hi Mira, it is Sam.');
    expect(recentChatSnippet(byId['picture']!), 'Kit: Shared an image');
    for (final r in rows) {
      expect(recentChatSnippet(r), isNot(contains('{{')));
      expect(recentChatSnippet(r), isNot(contains('think>')));
    }
  });

  test('soft-deleted chats, messages and owners stay out', () async {
    await character('c-mira', 'Mira');
    await character('c-gone', 'Gone', deleted: true);
    await group('g-gone', 'Old Crew', deleted: true);
    await chat('live', characterId: 'c-mira');
    await chat('deleted-chat', characterId: 'c-mira', deleted: true);
    await chat('deleted-character', characterId: 'c-gone');
    await chat('deleted-group', groupId: 'g-gone');
    await chat('no-owner', characterId: 'no-such-card');
    await chat('no-messages', characterId: 'c-mira');
    await chat('only-deleted-messages', characterId: 'c-mira');

    await say('live', 'Mira', 'still here', at: at(9));
    await say('live', 'Mira', 'taken back', at: at(11), deleted: true);
    for (final id in [
      'deleted-chat',
      'deleted-character',
      'deleted-group',
      'no-owner',
    ]) {
      await say(id, 'Someone', 'should not show', at: at(12));
    }
    await say(
      'only-deleted-messages',
      'Mira',
      'gone',
      at: at(13),
      deleted: true,
    );

    final rows = await db.getRecentSessions(10);
    expect(rows.map((r) => r.sessionId), ['live']);
    expect(rows.single.messageCount, 1);
    expect(rows.single.lastMessageAt, at(9));
    expect(recentChatSnippet(rows.single), 'still here');
  });
}
