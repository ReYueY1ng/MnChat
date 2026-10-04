import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart'
    show DriftNativeOptions, driftDatabase;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// 热点查询：`messagesOf`/`replaceMessages`/`allMessages` 都按
/// (owner_uin, session_key) 过滤并按 time 排序。
@TableIndex(
  name: 'idx_chat_messages_owner_session_time',
  columns: {#ownerUin, #sessionKey, #time},
)
/// 单账号全量消息按 time 排序（启动恢复）。
@TableIndex(name: 'idx_chat_messages_owner_time', columns: {#ownerUin, #time})
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

/// 热点查询：`allSessions` 按 owner_uin 过滤。
@TableIndex(name: 'idx_chat_sessions_owner_uin', columns: {#ownerUin})
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
/// 热点查询：`allFriends` 按 owner_uin 过滤。
@TableIndex(name: 'idx_friends_owner_uin', columns: {#ownerUin})
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
/// 用 Drift 表替代 path_provider JSON 文件（原生 SQLite）。
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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // v1→v2: chat_sessions 无主键 → 加主键；v2→v3: 新增 friends 好友信息缓存表；
    // v3→v4: 新增 settings 设置表；v4→v5: chat_messages 新增 msg_type 列；
    // v5→v6: friends 新增 relation/mark 列（好友关系位掩码）；
    // v6→v7: 多账号隔离 —— chat_messages/chat_sessions/friends 新增 ownerUin 列
    //        （0=旧数据，首次登录时收养到当前账号）。**当年这一步误用 addColumn，
    //        见下 v7→v8 的修表说明。**
    // v7→v8: 修复被 v6→v7 建坏的表：ownerUin 是 chat_sessions / friends 主键的
    //        一部分（{sessionKey,ownerUin} / {uin,ownerUin}），而 SQLite 的
    //        ALTER TABLE ADD COLUMN 改不了主键 —— addColumn 只把列加了进去，
    //        表的主键仍是 (session_key) / (uin)。drift 为 `insertOnConflictUpdate`
    //        生成的是 `ON CONFLICT("session_key","owner_uin") DO UPDATE`，与实表
    //        主键不匹配 → 每次写会话/好友都抛
    //        "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint"
    //        （且是未捕获的异步异常）→ 会话行永远写不进去 → 重启后「会话丢失」。
    //        这两张表必须整表重建（alterTable 会按当前 Dart 定义建表并搬迁数据）。
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
        // chat_messages 主键是自增 id、不含 ownerUin，ADD COLUMN 没问题。
        await m.addColumn(chatMessages, chatMessages.ownerUin);
        // 这两张表 ownerUin 在主键里 → 只能重建。`newColumns` 告诉 drift 该列在
        // 旧表里尚不存在（由列默认值 0 填充），其余列按名字原样搬迁。
        await m.alterTable(
          TableMigration(chatSessions, newColumns: [chatSessions.ownerUin]),
        );
        await m.alterTable(
          TableMigration(friends, newColumns: [friends.ownerUin]),
        );
      } else if (from == 7) {
        // 已在 v7 的库：表里有 owner_uin 列、但主键是旧的 —— 不带 newColumns /
        // columnTransformer 重建，按列名原样搬迁，保留已有 owner_uin 值。
        await m.alterTable(TableMigration(chatSessions));
        await m.alterTable(TableMigration(friends));
      }
      if (from < 9) {
        // v8→v9: 为热点查询补索引（不改表结构）。索引定义见各表上的
        // @TableIndex；这里用 Migrator 复用同一份生成 SQL，保证升级库与全新库
        // 建出的索引名/列完全一致。
        await m.createIndex(idxChatMessagesOwnerSessionTime);
        await m.createIndex(idxChatMessagesOwnerTime);
        await m.createIndex(idxChatSessionsOwnerUin);
        await m.createIndex(idxFriendsOwnerUin);
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

/// 数据库文件名（不含扩展名）。
const String kDbName = 'mnchat';

/// 打开应用数据库连接。
///
/// **为什么不用 `driftDatabase(name:)` 的默认目录**：那个默认走
/// `getApplicationDocumentsDirectory()`，Linux 下映射到 XDG Documents，
/// 于是 `mnchat.sqlite`（含聊天记录、好友列表与加密凭据）会直接躺在
/// `~/Documents/` 里被文件管理器、同步盘、备份脚本扫到。应用私有数据应当
/// 落在 `getApplicationSupportDirectory()`（Linux: `~/.local/share/<id>/`，
/// Android: `/data/data/<pkg>/files/`），与 `config_text_cache.dart` 的
/// `cfg_cache` 归拢在同一个目录下。
///
/// 可丢弃的缓存（图片、表情包）仍留在 cache 目录，由系统按需回收；
/// 这里只安置不可再生的聊天数据。
DatabaseConnection openAppDatabaseConnection() {
  return driftDatabase(
    name: kDbName,
    native: DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}
