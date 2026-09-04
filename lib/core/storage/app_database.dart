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

  @override
  Set<Column> get primaryKey => {sessionKey};
}

/// 好友信息缓存：启动时先显示本地快照，再网络刷新（query_friend_list）。
@DataClassName('FriendRecord')
class Friends extends Table {
  IntColumn get uin => integer()();
  TextColumn get nickname => text()();
  TextColumn get avatar => text().nullable()();
  BoolColumn get isOnline => boolean()();
  TextColumn get gameStatus => text().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {uin};
}

@DriftDatabase(tables: [ChatMessages, ChatSessions, Friends])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // v1→v2: chat_sessions 无主键 → 加主键；v2→v3: 新增 friends 好友信息缓存表。
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.deleteTable('chat_sessions');
            await m.deleteTable('chat_messages');
            await m.createTable(chatSessions);
            await m.createTable(chatMessages);
          }
          if (from < 3) {
            await m.createTable(friends);
          }
        },
      );

  Future<void> insertMessage(ChatMessagesCompanion row) =>
      into(chatMessages).insert(row);

  Future<List<ChatMessageRecord>> messagesOf(String key, {int limit = 200}) {
    final query = select(chatMessages)
      ..where((t) => t.sessionKey.equals(key))
      ..orderBy([(t) => OrderingTerm.asc(t.time)])
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

  /// 好友信息缓存：全量覆盖保存（每次 query_friend_list 成功后调用）。
  Future<void> replaceFriends(List<FriendRecord> records) async {
    await transaction(() async {
      await delete(friends).go();
      await batch((b) => b.insertAll(friends, records));
    });
  }

  Future<List<FriendRecord>> allFriends() => select(friends).get();
}
