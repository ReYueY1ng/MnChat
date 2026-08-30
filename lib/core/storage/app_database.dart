import 'package:drift/drift.dart';

part 'app_database.g.dart';

@DataClassName('ChatMessageRecord')
class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get content => text()();
  TextColumn get sessionKey => text()();
  IntColumn get uin => integer()();
  IntColumn get time => integer()();
  TextColumn get extendData => text().nullable()();
  BoolColumn get isSuccess => boolean()();
  IntColumn get notTime => integer().nullable()();
  TextColumn get srcUserVersion => text().nullable()();
  TextColumn get bubble => text().nullable()();
  TextColumn get interCode => text().nullable()();
  IntColumn get groupId => integer().nullable()();
  BoolColumn get isSystemMsg => boolean()();
  BoolColumn get isTime => boolean()();
  TextColumn get direction => text()();
}

@DataClassName('ChatSessionRecord')
class ChatSessions extends Table {
  TextColumn get sessionKey => text()();
  IntColumn get typeId => integer()();
  TextColumn get name => text()();
  TextColumn get avatar => text().nullable()();
  IntColumn get lastTime => integer()();
  IntColumn get lastReadTime => integer()();
  IntColumn get unreadCount => integer()();
  IntColumn get lastUin => integer().nullable()();
  TextColumn get lastText => text().nullable()();
}

@DriftDatabase(tables: [ChatMessages, ChatSessions])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  Future<void> insertMessage(ChatMessagesCompanion row) =>
      into(chatMessages).insert(row);

  Future<List<ChatMessageRecord>> messagesOf(String key, {int limit = 200}) {
    final query = select(chatMessages)
      ..where((t) => t.sessionKey.equals(key))
      ..orderBy([(t) => OrderingTerm.desc(t.time)])
      ..limit(limit);
    return query.get();
  }

  Future<void> clearMessages(String key) =>
      (delete(chatMessages)..where((t) => t.sessionKey.equals(key))).go();

  Future<void> upsertSession(ChatSessionsCompanion row) =>
      into(chatSessions).insertOnConflictUpdate(row);

  Future<List<ChatSessionRecord>> allSessions() => select(chatSessions).get();

  Future<ChatSessionRecord?> sessionOf(String key) =>
      (select(chatSessions)..where((t) => t.sessionKey.equals(key)))
          .getSingleOrNull();

  Future<void> updateUnread(String key, int unread) =>
      (update(chatSessions)..where((t) => t.sessionKey.equals(key)))
          .write(ChatSessionsCompanion(unreadCount: Value(unread)));

  Future<void> markRead(String key) =>
      (update(chatSessions)..where((t) => t.sessionKey.equals(key)))
          .write(const ChatSessionsCompanion(unreadCount: Value(0)));
}
