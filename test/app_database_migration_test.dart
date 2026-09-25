// 数据库迁移测试（schema 8→9：为热点查询补索引）。
//
// 覆盖三件事：
//   (a) 全新库 onCreate 后索引存在，且索引列顺序正确。
//   (b) v8→v9 升级：数据原样保留，且 onUpgrade 补建了同样的索引。
//   (c) v7→v8→v9 锁死主键修复：做过 buggy v7 的库升级后，会话/好友的
//       `ON CONFLICT` 不再因主键不匹配而抛异常，数据保留。
//
// 期望的索引（fresh 与 upgraded 必须完全一致）：
//   idx_chat_messages_owner_session_time : chat_messages(owner_uin, session_key, time)
//   idx_chat_messages_owner_time         : chat_messages(owner_uin, time)
//   idx_chat_sessions_owner_uin          : chat_sessions(owner_uin)
//   idx_friends_owner_uin                : friends(owner_uin)
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/storage/app_database.dart';

/// fresh 与 upgraded 都必须存在的索引 → 有序的索引列（与 CREATE INDEX 顺序一致）。
const expectedIndexes = <String, List<String>>{
  'idx_chat_messages_owner_session_time': ['owner_uin', 'session_key', 'time'],
  'idx_chat_messages_owner_time': ['owner_uin', 'time'],
  'idx_chat_sessions_owner_uin': ['owner_uin'],
  'idx_friends_owner_uin': ['owner_uin'],
};

const _v8ChatMessages = '''
CREATE TABLE "chat_messages" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "content" TEXT NOT NULL, "session_key" TEXT NOT NULL, "uin" INTEGER NOT NULL, "time" INTEGER NOT NULL, "extend_data" TEXT NULL, "is_success" INTEGER NOT NULL CHECK ("is_success" IN (0, 1)), "not_time" INTEGER NULL, "src_user_version" TEXT NULL, "bubble" TEXT NULL, "inter_code" TEXT NULL, "group_id" INTEGER NULL, "is_system_msg" INTEGER NOT NULL CHECK ("is_system_msg" IN (0, 1)), "is_time" INTEGER NOT NULL CHECK ("is_time" IN (0, 1)), "direction" TEXT NOT NULL, "msg_type" TEXT NOT NULL DEFAULT 'text', "owner_uin" INTEGER NOT NULL DEFAULT 0);
''';

/// v8 chat_sessions：owner_uin 已在复合主键里。
const _v8ChatSessions = '''
CREATE TABLE "chat_sessions" ("session_key" TEXT NOT NULL, "type_id" INTEGER NOT NULL, "name" TEXT NOT NULL, "avatar" TEXT NULL, "last_time" INTEGER NOT NULL, "last_read_time" INTEGER NOT NULL, "unread_count" INTEGER NOT NULL, "last_uin" INTEGER NULL, "last_text" TEXT NULL, "owner_uin" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("session_key", "owner_uin"));
''';

/// v7 buggy chat_sessions：owner_uin 列在、但主键只有 session_key（当年 addColumn 建坏）。
const _v7ChatSessions = '''
CREATE TABLE "chat_sessions" ("session_key" TEXT NOT NULL, "type_id" INTEGER NOT NULL, "name" TEXT NOT NULL, "avatar" TEXT NULL, "last_time" INTEGER NOT NULL, "last_read_time" INTEGER NOT NULL, "unread_count" INTEGER NOT NULL, "last_uin" INTEGER NULL, "last_text" TEXT NULL, "owner_uin" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("session_key"));
''';

const _v8Friends = '''
CREATE TABLE "friends" ("uin" INTEGER NOT NULL, "nickname" TEXT NOT NULL, "avatar" TEXT NULL, "is_online" INTEGER NOT NULL CHECK ("is_online" IN (0, 1)), "game_status" TEXT NULL, "updated_at" INTEGER NOT NULL, "relation" INTEGER NOT NULL DEFAULT 0, "mark" INTEGER NOT NULL DEFAULT 0, "owner_uin" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("uin", "owner_uin"));
''';

/// v7 buggy friends：owner_uin 列在、但主键只有 uin。
const _v7Friends = '''
CREATE TABLE "friends" ("uin" INTEGER NOT NULL, "nickname" TEXT NOT NULL, "avatar" TEXT NULL, "is_online" INTEGER NOT NULL CHECK ("is_online" IN (0, 1)), "game_status" TEXT NULL, "updated_at" INTEGER NOT NULL, "relation" INTEGER NOT NULL DEFAULT 0, "mark" INTEGER NOT NULL DEFAULT 0, "owner_uin" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("uin"));
''';

const _settingsTable = '''
CREATE TABLE "settings_table" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"));
''';

const _seedMessages = [
  'INSERT INTO "chat_messages" ("id","content","session_key","uin","time","extend_data","is_success","not_time","src_user_version","bubble","inter_code","group_id","is_system_msg","is_time","direction","msg_type","owner_uin") VALUES (1,\'hello\',\'friend_1001\',1001,1700000000,NULL,1,NULL,NULL,NULL,NULL,NULL,0,0,\'in\',\'text\',7)',
  'INSERT INTO "chat_messages" ("id","content","session_key","uin","time","extend_data","is_success","not_time","src_user_version","bubble","inter_code","group_id","is_system_msg","is_time","direction","msg_type","owner_uin") VALUES (2,\'world\',\'friend_1001\',1001,1700000100,NULL,1,NULL,NULL,NULL,NULL,NULL,0,0,\'out\',\'text\',7)',
];

const _seedSessions = [
  'INSERT INTO "chat_sessions" ("session_key","type_id","name","avatar","last_time","last_read_time","unread_count","last_uin","last_text","owner_uin") VALUES (\'friend_1001\',0,\'Alice\',NULL,1700000100,1700000000,2,1001,\'hi\',7)',
];

const _seedFriends = [
  'INSERT INTO "friends" ("uin","nickname","avatar","is_online","game_status","updated_at","relation","mark","owner_uin") VALUES (1001,\'Alice\',NULL,1,\'游戏中\',1700000000,3,5,7)',
];

const _seedSettings = [
  'INSERT INTO "settings_table" ("key","value") VALUES (\'autologin_token\',\'secret-abc\')',
];

/// 用一张 v8 形状的旧库启动连接（无索引），user_version=8。
QueryExecutor _v8Executor() => NativeDatabase.memory(
  setup: (raw) {
    for (final sql in const [
      _v8ChatMessages,
      _v8ChatSessions,
      _v8Friends,
      _settingsTable,
    ]) {
      raw.execute(sql);
    }
    for (final sql in const [
      ..._seedMessages,
      ..._seedSessions,
      ..._seedFriends,
      ..._seedSettings,
    ]) {
      raw.execute(sql);
    }
    raw.userVersion = 8;
  },
);

/// 用一张 buggy v7 形状的旧库启动连接，user_version=7。
QueryExecutor _v7Executor() => NativeDatabase.memory(
  setup: (raw) {
    for (final sql in const [
      _v8ChatMessages,
      _v7ChatSessions,
      _v7Friends,
      _settingsTable,
    ]) {
      raw.execute(sql);
    }
    for (final sql in const [
      ..._seedMessages,
      ..._seedSessions,
      ..._seedFriends,
      ..._seedSettings,
    ]) {
      raw.execute(sql);
    }
    raw.userVersion = 7;
  },
);

Future<void> _open(AppDatabase db) => db.customSelect('SELECT 1').get();

/// 非自动索引的索引名（按名字排序）。
Future<List<String>> _indexNames(AppDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name = ? "
        "AND name NOT LIKE 'sqlite_autoindex%' ORDER BY name",
        variables: [Variable<String>(table)],
      )
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<Map<String, List<String>>> _allIndexes(AppDatabase db) async {
  final result = <String, List<String>>{};
  for (final table in const [
    'chat_messages',
    'chat_sessions',
    'friends',
  ]) {
    for (final name in await _indexNames(db, table)) {
      final rows = await db.customSelect('PRAGMA index_info("$name")').get();
      result[name] = rows.map((r) => r.read<String>('name')).toList();
    }
  }
  return result;
}

void main() {
  group('(a) 全新库：索引存在且列顺序正确', () {
    test('onCreate 创建全部 4 个索引', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _open(db);

      final indexes = await _allIndexes(db);
      expect(
        indexes.keys.toSet(),
        containsAll(expectedIndexes.keys),
        reason: 'fresh 库缺少索引: $indexes',
      );
      for (final entry in expectedIndexes.entries) {
        expect(
          indexes[entry.key],
          entry.value,
          reason: '${entry.key} 的列顺序/名称不匹配',
        );
      }
      // fresh 库的索引集合必须与期望完全一致（b/c 断言 upgraded 亦等于该集合，
      // 因此 fresh == upgraded）。
      expect(indexes, equals(expectedIndexes));
    });
  });

  group('(b) v8→v9 升级：数据保留 + 补建索引', () {
    test('所有行原样保留且索引与 fresh 一致', () async {
      final db = AppDatabase(_v8Executor());
      addTearDown(db.close);
      await _open(db);

      // 数据保留。
      final messages = await db.messagesOf(7, 'friend_1001');
      expect(messages.map((m) => m.content).toList(), ['hello', 'world']);
      expect(messages.map((m) => m.time).toList(), [1700000000, 1700000100]);
      expect(await db.allMessages(7), hasLength(2));

      final sessions = await db.allSessions(7);
      expect(sessions, hasLength(1));
      expect(sessions.single.name, 'Alice');
      expect(sessions.single.unreadCount, 2);
      expect(sessions.single.ownerUin, 7);

      final friends = await db.allFriends(7);
      expect(friends, hasLength(1));
      expect(friends.single.nickname, 'Alice');
      expect(friends.single.ownerUin, 7);
      expect(friends.single.relation, 3);
      expect(friends.single.mark, 5);

      expect(await db.getSetting('autologin_token'), 'secret-abc');

      // v8→v9 升级补建的索引必须与 fresh 完全一致。
      final indexes = await _allIndexes(db);
      expect(indexes, equals(expectedIndexes));
    });
  });

  group('(c) v7→v9：主键修复 + 索引补建 + 数据保留', () {
    test('upsertSession no longer throws and repairs composite PK', () async {
      final db = AppDatabase(_v7Executor());
      addTearDown(db.close);
      await _open(db);

      // 数据保留。
      expect(await db.messagesOf(7, 'friend_1001'), hasLength(2));
      final before = await db.allSessions(7);
      expect(before, hasLength(1));
      expect(before.single.name, 'Alice');

      // 主键修复：同 (session_key, owner_uin) 的 upsert 应是 UPDATE 而非抛异常/新增。
      await db.upsertSession(
        ChatSessionsCompanion.insert(
          sessionKey: 'friend_1001',
          typeId: 0,
          name: 'Alice2',
          lastTime: 1700000200,
          lastReadTime: 1700000000,
          unreadCount: 0,
          ownerUin: const Value(7),
        ),
      );
      final after = await db.allSessions(7);
      expect(after, hasLength(1), reason: 'upsert 必须命中复合主键而非新增行');
      expect(after.single.name, 'Alice2');

      // friends 复合主键同样已修复。
      await db
          .into(db.friends)
          .insertOnConflictUpdate(
            FriendsCompanion.insert(
              uin: 1001,
              nickname: 'AliceUpd',
              isOnline: false,
              updatedAt: 1700000300,
              ownerUin: const Value(7),
            ),
          );
      final friends = await db.allFriends(7);
      expect(friends, hasLength(1));
      expect(friends.single.nickname, 'AliceUpd');

      // v7→v9 路径补建的索引也必须与 fresh 完全一致。
      final indexes = await _allIndexes(db);
      expect(indexes, equals(expectedIndexes));
    });
  });
}
