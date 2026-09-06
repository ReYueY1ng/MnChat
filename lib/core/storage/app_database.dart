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
  TextColumn get msgType => text().withDefault(const Constant('text'))();
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
  IntColumn get relation => integer().withDefault(const Constant(0))();
  IntColumn get mark => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {uin};
}

/// 应用设置 key-value 存储（自动登录凭据、开关、服务器地址、排序模式等）。
/// 用 Drift 表替代 path_provider JSON 文件：Web(WASM/IndexedDB) 与原生(SQLite) 统一。
@DataClassName('SettingRecord')
class SettingsTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [ChatMessages, ChatSessions, Friends, SettingsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // v1→v2: chat_sessions 无主键 → 加主键；v2→v3: 新增 friends 好友信息缓存表；
    // v3→v4: 新增 settings 设置表；v4→v5: chat_messages 新增 msg_type 列；
    // v5→v6: friends 新增 relation/mark 列（好友关系位掩码）。
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
      if (from < 4) {
        await m.createTable(settingsTable);
      }
      if (from < 5) {
        await m.addColumn(chatMessages, chatMessages.msgType);
      }
      if (from < 6) {
        await m.addColumn(friends, friends.relation);
        await m.addColumn(friends, friends.mark);
      }
    },
  );

  /// 读取设置项；不存在返回 null。
  Future<String?> getSetting(String key) async {
    final row = await (select(
      settingsTable,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 写入/覆盖设置项。
  Future<void> setSetting(String key, String value) async {
    await into(settingsTable).insertOnConflictUpdate(
      SettingsTableCompanion(key: Value(key), value: Value(value)),
    );
  }

  /// 删除设置项。
  Future<void> clearSetting(String key) async {
    await (delete(settingsTable)..where((t) => t.key.equals(key))).go();
  }

  Future<void> insertMessage(ChatMessagesCompanion row) =>
      into(chatMessages).insert(row);

  Future<List<ChatMessageRecord>> messagesOf(String key, {int limit = 200}) {
    final query = select(chatMessages)
      ..where((t) => t.sessionKey.equals(key))
      ..orderBy([(t) => OrderingTerm.asc(t.time)])
      ..limit(limit);
    return query.get();
  }

  /// 一次查询全部消息（按 time 升序），用于启动时批量恢复离线缓存，
  /// 避免逐会话查询的 N+1 问题。
  Future<List<ChatMessageRecord>> allMessages({int limit = 10000}) {
    final query = select(chatMessages)
      ..orderBy([(t) => OrderingTerm.asc(t.time)])
      ..limit(limit);
    return query.get();
  }

  /// 原子替换某会话的整段历史（清空 + 批量写入，一个事务内完成，
  /// 中途失败不留半写状态）。
  Future<void> replaceMessages(
    String key,
    List<ChatMessagesCompanion> rows,
  ) async {
    await transaction(() async {
      await (delete(chatMessages)..where((t) => t.sessionKey.equals(key))).go();
      await batch((b) => b.insertAll(chatMessages, rows));
    });
  }

  Future<void> clearMessages(String key) =>
      (delete(chatMessages)..where((t) => t.sessionKey.equals(key))).go();

  Future<void> upsertSession(ChatSessionsCompanion row) =>
      into(chatSessions).insertOnConflictUpdate(row);

  Future<List<ChatSessionRecord>> allSessions() => select(chatSessions).get();

  Future<ChatSessionRecord?> sessionOf(String key) => (select(
    chatSessions,
  )..where((t) => t.sessionKey.equals(key))).getSingleOrNull();

  Future<void> updateUnread(String key, int unread) =>
      (update(chatSessions)..where((t) => t.sessionKey.equals(key))).write(
        ChatSessionsCompanion(unreadCount: Value(unread)),
      );

  Future<void> markRead(String key) =>
      (update(chatSessions)..where((t) => t.sessionKey.equals(key))).write(
        const ChatSessionsCompanion(unreadCount: Value(0)),
      );

  /// 好友信息缓存：全量覆盖保存（每次 query_friend_list 成功后调用）。
  Future<void> replaceFriends(List<FriendRecord> records) async {
    await transaction(() async {
      await delete(friends).go();
      await batch((b) => b.insertAll(friends, records));
    });
  }

  Future<List<FriendRecord>> allFriends() => select(friends).get();
}
