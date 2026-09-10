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
  /// 账号归属（本地多账号数据隔离）：0=旧数据（首登收养）。
  IntColumn get ownerUin => integer().withDefault(const Constant(0))();
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
  /// 账号归属（本地多账号数据隔离）：0=旧数据（首登收养）。
  IntColumn get ownerUin => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sessionKey, ownerUin};
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
  /// 账号归属（本地多账号数据隔离）：0=旧数据（首登收养）。
  IntColumn get ownerUin => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {uin, ownerUin};
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // v1→v2: chat_sessions 无主键 → 加主键；v2→v3: 新增 friends 好友信息缓存表；
    // v3→v4: 新增 settings 设置表；v4→v5: chat_messages 新增 msg_type 列；
    // v5→v6: friends 新增 relation/mark 列（好友关系位掩码）；
    // v6→v7: 多账号隔离 —— chat_messages/chat_sessions/friends 新增 ownerUin 列
    //        （0=旧数据，首次登录时收养到当前账号）。
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
      if (from < 7) {
        await m.addColumn(chatMessages, chatMessages.ownerUin);
        await m.addColumn(chatSessions, chatSessions.ownerUin);
        await m.addColumn(friends, friends.ownerUin);
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

  /// 查询某会话消息（按账号隔离）。
  Future<List<ChatMessageRecord>> messagesOf(
    int ownerUin,
    String key, {
    int limit = 200,
  }) {
    final query = select(chatMessages)
      ..where((t) => t.ownerUin.equals(ownerUin) & t.sessionKey.equals(key))
      ..orderBy([(t) => OrderingTerm.asc(t.time)])
      ..limit(limit);
    return query.get();
  }

  /// 一次查询全部消息（按账号隔离，按 time 升序），用于启动时批量恢复
  /// 离线缓存，避免逐会话查询的 N+1 问题。
  Future<List<ChatMessageRecord>> allMessages(int ownerUin, {int limit = 10000}) {
    final query = select(chatMessages)
      ..where((t) => t.ownerUin.equals(ownerUin))
      ..orderBy([(t) => OrderingTerm.asc(t.time)])
      ..limit(limit);
    return query.get();
  }

  /// 原子替换某会话的整段历史（按账号隔离，清空 + 批量写入一个事务）。
  Future<void> replaceMessages(
    int ownerUin,
    String key,
    List<ChatMessagesCompanion> rows,
  ) async {
    await transaction(() async {
      await (delete(chatMessages)
            ..where((t) => t.ownerUin.equals(ownerUin) & t.sessionKey.equals(key)))
          .go();
      await batch((b) => b.insertAll(chatMessages, rows));
    });
  }

  Future<void> clearMessages(int ownerUin, String key) => (delete(chatMessages)
        ..where((t) => t.ownerUin.equals(ownerUin) & t.sessionKey.equals(key)))
      .go();

  Future<void> upsertSession(ChatSessionsCompanion row) =>
      into(chatSessions).insertOnConflictUpdate(row);

  /// 全部会话（按账号隔离）。
  Future<List<ChatSessionRecord>> allSessions(int ownerUin) =>
      (select(chatSessions)..where((t) => t.ownerUin.equals(ownerUin))).get();

  Future<ChatSessionRecord?> sessionOf(int ownerUin, String key) => (select(
    chatSessions,
  )..where((t) => t.ownerUin.equals(ownerUin) & t.sessionKey.equals(key)))
      .getSingleOrNull();

  Future<void> updateUnread(int ownerUin, String key, int unread) =>
      (update(chatSessions)
            ..where(
              (t) => t.ownerUin.equals(ownerUin) & t.sessionKey.equals(key),
            ))
          .write(ChatSessionsCompanion(unreadCount: Value(unread)));

  Future<void> markRead(int ownerUin, String key) =>
      (update(chatSessions)
            ..where(
              (t) => t.ownerUin.equals(ownerUin) & t.sessionKey.equals(key),
            ))
          .write(const ChatSessionsCompanion(unreadCount: Value(0)));

  /// 好友信息缓存：全量覆盖保存（按账号隔离）。
  Future<void> replaceFriends(int ownerUin, List<FriendRecord> records) async {
    await transaction(() async {
      await (delete(friends)..where((t) => t.ownerUin.equals(ownerUin))).go();
      await batch((b) => b.insertAll(friends, records));
    });
  }

  /// 某账号的全部好友（按账号隔离）。
  Future<List<FriendRecord>> allFriends(int ownerUin) =>
      (select(friends)..where((t) => t.ownerUin.equals(ownerUin))).get();

  /// 收养旧数据：把 v6 及更早版本遗留的 ownerUin=0 数据挂到 [ownerUin]。
  /// 首次登录时调用一次，让升级前的本地聊天历史归属到当前账号；
  /// 之后切换账号不会看到别的账号的数据。
  Future<void> adoptOrphanData(int ownerUin) async {
    await transaction(() async {
      await (update(chatMessages)..where((t) => t.ownerUin.equals(0)))
          .write(ChatMessagesCompanion(ownerUin: Value(ownerUin)));
      await (update(chatSessions)..where((t) => t.ownerUin.equals(0)))
          .write(ChatSessionsCompanion(ownerUin: Value(ownerUin)));
      await (update(friends)..where((t) => t.ownerUin.equals(0)))
          .write(FriendsCompanion(ownerUin: Value(ownerUin)));
    });
  }
}
