import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart'
    show DriftNativeOptions, driftDatabase;
import 'package:path_provider/path_provider.dart';

import '../models/chat_search.dart';
import '../models/message_mark.dart';
import '../utils/log.dart';

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

/// 本机消息标记：收藏（favorite）与本地删除（hidden）。
///
/// 不为它加列到 chat_messages：标记是“本机视角”的附加信息，生命周期与服务端
/// 消息独立，且同一条消息最多各有一条 favorite/hidden；按
/// (ownerUin, sessionKey, msgUin, msgTime, kind) 作主键就能幂等写入。
/// 用 (uin, time) 而不是 chat_messages 的自增 id 定位消息：历史替换
/// （`replaceMessages`）会重建行，自增 id 不可跨次稳定。
@TableIndex(name: 'idx_message_marks_owner_kind', columns: {#ownerUin, #kind})
@DataClassName('MessageMarkRecord')
class MessageMarks extends Table {
  /// 账号归属（多账号数据隔离）。
  IntColumn get ownerUin => integer()();

  TextColumn get sessionKey => text()();

  /// 消息发送者 uin（与 chat_messages.uin 一致）。
  IntColumn get msgUin => integer()();

  /// 消息时间（epoch 秒，与 chat_messages.time 一致）。
  IntColumn get msgTime => integer()();

  /// 标记类型，取值见 models/message_mark.dart 的 [MessageMarkKind]。
  TextColumn get kind => text()();

  /// 标记发生时间（epoch 秒）；收藏夹按它倒序。
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {ownerUin, sessionKey, msgUin, msgTime, kind};
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

@DriftDatabase(
  tables: [ChatMessages, ChatSessions, Friends, MessageMarks, SettingsTable],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// FTS5 虚表是否可用。
  ///
  /// 更老的 SQLite 或未编译 FTS5 的构建上建表会抛；此时整体退回 LIKE 检索
  /// （中文单/双字也要走 LIKE），因此这里是运行期开关而不是配置。
  bool _ftsAvailable = true;

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // 虚表不在 drift 的表定义里（Migrator 不认识 fts5），单独建。
      await _createFullTextSearch();
    },
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
      if (from < 10) {
        // v9→v10: 本机消息标记（收藏 / 本机删除）+ 全文搜索虚表与同步触发器。
        // 已存在的历史行由 _createFullTextSearch 回填。
        await m.createTable(messageMarks);
        await m.createIndex(idxMessageMarksOwnerKind);
        await _createFullTextSearch();
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

  // ── 本机消息标记（收藏 / 本机删除）────────────────────────────────────

  /// 写入或清除一条本机消息标记。[on] 为 false 时删除该标记（幂等）。
  ///
  /// [sessionKey] 同 `models/session_key.dart` 的格式；(msgUin, msgTime) 定位
  /// 服务端消息。写失败只记日志 —— 标记是辅助功能，不应阻断聊天链路。
  Future<void> setMessageMark({
    required int ownerUin,
    required String sessionKey,
    required int msgUin,
    required int msgTime,
    required String kind,
    required bool on,
    int? now,
  }) async {
    if (ownerUin == 0) return;
    try {
      if (on) {
        await into(messageMarks).insertOnConflictUpdate(
          MessageMarksCompanion(
            ownerUin: Value(ownerUin),
            sessionKey: Value(sessionKey),
            msgUin: Value(msgUin),
            msgTime: Value(msgTime),
            kind: Value(kind),
            createdAt: Value(
              now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ),
          ),
        );
        return;
      }
      await (delete(messageMarks)..where(
            (t) =>
                t.ownerUin.equals(ownerUin) &
                t.sessionKey.equals(sessionKey) &
                t.msgUin.equals(msgUin) &
                t.msgTime.equals(msgTime) &
                t.kind.equals(kind),
          ))
          .go();
    } catch (e) {
      log.error('set message mark failed: $e', tag: _logTag);
    }
  }

  /// 某一类标记的全部键（`<uin>_<time>`，见 [messageMarkKey]）。
  ///
  /// UI 侧用它在渲染前去重（本机删除）或打星（收藏）；[sessionKey] 非空时只取
  /// 该会话（进入会话时只需一个会话的标记集）。
  Future<Set<String>> messageMarkKeys(
    int ownerUin,
    String kind, {
    String? sessionKey,
  }) async {
    if (ownerUin == 0) return <String>{};
    final query = select(messageMarks)
      ..where(
        (t) =>
            t.ownerUin.equals(ownerUin) &
            t.kind.equals(kind) &
            (sessionKey == null
                ? const Constant(true)
                : t.sessionKey.equals(sessionKey)),
      );
    final rows = await query.get();
    return {for (final r in rows) messageMarkKey(r.msgUin, r.msgTime)};
  }

  /// 每个 uin 在本机的最后一条消息时间（epoch 秒）：`uin → time`。
  ///
  /// “上次互动”服务端不下发，官方“30 天不互动开始衰减”的提醒只能按本机聊天
  /// 记录算（见 `models/partner_nudge.dart`）。[uins] 为空时聚合整个账号
  /// （调用方自己按需取用）。
  Future<Map<int, int>> lastMessageTimesByUin(
    int ownerUin, {
    Iterable<int> uins = const <int>[],
  }) async {
    if (ownerUin == 0) return const <int, int>{};
    final list = uins.toList(growable: false);
    final where = StringBuffer('WHERE owner_uin = ?');
    final variables = <Variable<Object>>[Variable.withInt(ownerUin)];
    if (list.isNotEmpty) {
      where.write(' AND uin IN (${List.filled(list.length, '?').join(',')})');
      variables.addAll(list.map(Variable.withInt));
    }
    final rows = await customSelect(
      'SELECT uin, MAX(time) AS last_time FROM chat_messages '
      '$where GROUP BY uin',
      variables: variables,
      readsFrom: {chatMessages},
    ).get();
    return {
      for (final r in rows) r.read<int>('uin'): r.read<int>('last_time'),
    };
  }

  /// 收藏夹：按收藏时间倒序（带上正文）。
  ///
  /// 用 LEFT JOIN 并在标记侧取 (uin, time)：历史替换
  /// （`replaceMessages`）可能已经把消息行重建/删掉，此时仍应列出这条收藏，
  /// 只是正文取不到（空串）。
  Future<List<ChatSearchHit>> favoriteMessages(
    int ownerUin, {
    int limit = 500,
  }) {
    const sql = 'SELECT mk.session_key AS session_key, mk.msg_uin AS uin, '
        'mk.msg_time AS time, COALESCE(m.content, \'\') AS content, '
        'mk.created_at AS marked_at '
        'FROM message_marks mk '
        'LEFT JOIN chat_messages m ON m.owner_uin = mk.owner_uin '
        'AND m.session_key = mk.session_key AND m.uin = mk.msg_uin '
        'AND m.time = mk.msg_time '
        'WHERE mk.owner_uin = ? AND mk.kind = ? '
        'ORDER BY mk.created_at DESC, mk.msg_time DESC LIMIT ?';
    return customSelect(
      sql,
      variables: [
        Variable.withInt(ownerUin),
        Variable.withString(MessageMarkKind.favorite),
        Variable.withInt(limit),
      ],
      readsFrom: {messageMarks, chatMessages},
    ).map(_favoriteRow).get();
  }

  static ChatSearchHit _favoriteRow(QueryRow row) => ChatSearchHit(
    sessionKey: row.read<String>('session_key'),
    uin: row.read<int>('uin'),
    time: row.read<int>('time'),
    text: row.read<String>('content'),
    markedAt: row.read<int>('marked_at'),
  );

  // ── 垮会话全文检索 ──────────────────────────────────────────────────

  /// 检索聊天记录。[query] 为原始关键词（**不要**自己转义）。
  ///
  /// - ≥3 字：走 FTS5 trigram 虚表（中文无词边界，trigram 才能命中子串）；
  /// - 1~2 字：trigram 无法成词，退回 LIKE 子串匹配；
  /// - 虚表不可用或查询报错：静默退回 LIKE（搜索是只读辅助功能，绝不崩页面）。
  ///
  /// 本机已删除（hidden 标记）的消息不会出现在结果里；[sessionKey] 非空时只搜
  /// 该会话（会话内搜索复用同一实现）。
  Future<List<ChatSearchHit>> searchMessages(
    int ownerUin,
    String query, {
    String? sessionKey,
    int limit = 200,
  }) async {
    final q = query.trim();
    if (ownerUin == 0 || q.isEmpty) return const <ChatSearchHit>[];
    if (q.length >= 3 && _ftsAvailable) {
      try {
        return await _searchWithFts(
          ownerUin,
          q,
          sessionKey: sessionKey,
          limit: limit,
        );
      } catch (_) {
        // 该库上 FTS5 不可用（建表失败、查询语法异常…）：本次起改走 LIKE。
        _ftsAvailable = false;
      }
    }
    return _searchWithLike(
      ownerUin,
      q,
      sessionKey: sessionKey,
      limit: limit,
    );
  }

  /// 排除本机已删除消息的条件子句（FTS 与 LIKE 两条路径共用一份口径）。
  static const String _notHidden =
      'NOT EXISTS (SELECT 1 FROM message_marks mk '
      'WHERE mk.owner_uin = m.owner_uin AND mk.session_key = m.session_key '
      'AND mk.msg_uin = m.uin AND mk.msg_time = m.time '
      "AND mk.kind = 'hidden')";

  static const String _selectColumns =
      'SELECT m.session_key AS session_key, m.uin AS uin, m.time AS time, '
      'm.content AS content FROM chat_messages m ';

  Future<List<ChatSearchHit>> _searchWithFts(
    int ownerUin,
    String q, {
    String? sessionKey,
    required int limit,
  }) {
    // FTS5 把短横线/星号/引号当运算符，关键词带它们会变成语法错误；整句包成
    // 短语（内部双引号按 FTS5 规则翻倍）最稳。
    final phrase = '"${q.replaceAll('"', '""')}"';
    final sql = StringBuffer(_selectColumns)
      ..write('JOIN $kFtsTableName f ON m.id = f.rowid ')
      ..write('WHERE f.content MATCH ? AND m.owner_uin = ?');
    final variables = <Variable<Object>>[
      Variable.withString(phrase),
      Variable.withInt(ownerUin),
    ];
    if (sessionKey != null) {
      sql.write(' AND m.session_key = ?');
      variables.add(Variable.withString(sessionKey));
    }
    sql.write(' AND $_notHidden ORDER BY m.time DESC LIMIT ?');
    variables.add(Variable.withInt(limit));
    return customSelect(
      sql.toString(),
      variables: variables,
      readsFrom: {chatMessages, messageMarks},
    ).map(_searchRow).get();
  }

  Future<List<ChatSearchHit>> _searchWithLike(
    int ownerUin,
    String q, {
    String? sessionKey,
    required int limit,
  }) {
    final sql = StringBuffer(_selectColumns)
      ..write(r"WHERE m.content LIKE ? ESCAPE '\' AND m.owner_uin = ?");
    final variables = <Variable<Object>>[
      Variable.withString('%${_escapeLike(q)}%'),
      Variable.withInt(ownerUin),
    ];
    if (sessionKey != null) {
      sql.write(' AND m.session_key = ?');
      variables.add(Variable.withString(sessionKey));
    }
    sql.write(' AND $_notHidden ORDER BY m.time DESC LIMIT ?');
    variables.add(Variable.withInt(limit));
    return customSelect(
      sql.toString(),
      variables: variables,
      readsFrom: {chatMessages, messageMarks},
    ).map(_searchRow).get();
  }

  static ChatSearchHit _searchRow(QueryRow row) => ChatSearchHit(
    sessionKey: row.read<String>('session_key'),
    uin: row.read<int>('uin'),
    time: row.read<int>('time'),
    text: row.read<String>('content'),
  );

  /// LIKE 通配符转义（`\` `%` `_` 当字面量）。
  static String _escapeLike(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// 建 FTS5 虚表（trigram）+ 回填历史行 + 同步触发器。
  ///
  /// 为什么是 trigram：中文没有词边界，默认 unicode61 会把整句当一个 token，
  /// `MATCH '关键词'` 永远搜不到子串；trigram 把文本切成 3 字滑窗，于是任意
  /// ≥3 字的子串都能命中（1~2 字的查询由 [searchMessages] 回退 LIKE）。
  /// 虚表用 `rowid = chat_messages.id` 与主表对齐，触发器保持同步。
  /// 建表失败（更老的 SQLite / 未编译 FTS5）只降级不抛，检索自动走 LIKE。
  Future<void> _createFullTextSearch() async {
    try {
      await customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS $kFtsTableName USING fts5('
        'content, session_key UNINDEXED, msg_uin UNINDEXED, '
        'msg_time UNINDEXED, owner_uin UNINDEXED, tokenize="trigram")',
      );
      await customStatement(
        'INSERT INTO $kFtsTableName('
        'rowid, content, session_key, msg_uin, msg_time, owner_uin) '
        'SELECT id, content, session_key, uin, time, owner_uin '
        'FROM chat_messages '
        'WHERE id NOT IN (SELECT rowid FROM $kFtsTableName)',
      );
      for (final sql in _ftsTriggers) {
        await customStatement(sql);
      }
      _ftsAvailable = true;
    } catch (e) {
      _ftsAvailable = false;
      log.warn('FTS5 不可用，全文检索回退 LIKE：$e', tag: _logTag);
    }
  }

  /// 主表 ↔ 虚表同步触发器（插入 / 删除 / 正文更新）。
  ///
  /// 用触发器而不是在 Dart 侧每一处写库点手动同步：`replaceMessages` 的
  /// 先清后插也会逐行触发，口径只有一份。
  static const List<String> _ftsTriggers = <String>[
    'CREATE TRIGGER IF NOT EXISTS chat_messages_fts_ai AFTER INSERT ON chat_messages '
        'BEGIN INSERT INTO $kFtsTableName('
        'rowid, content, session_key, msg_uin, msg_time, owner_uin) '
        'VALUES (new.id, new.content, new.session_key, new.uin, new.time, new.owner_uin); END',
    'CREATE TRIGGER IF NOT EXISTS chat_messages_fts_ad AFTER DELETE ON chat_messages '
        'BEGIN DELETE FROM $kFtsTableName WHERE rowid = old.id; END',
    'CREATE TRIGGER IF NOT EXISTS chat_messages_fts_au AFTER UPDATE ON chat_messages '
        'BEGIN UPDATE $kFtsTableName SET content = new.content WHERE rowid = new.id; END',
  ];

  /// 本模块日志标签。
  static const String _logTag = 'AppDatabase';
}

/// 数据库文件名（不含扩展名）。
const String kDbName = 'mnchat';

/// 全文检索虚表名（FTS5 + trigram 分词）。
///
/// 定义在 [AppDatabase] 之外：测试要直接用 sqlite 验证虚表与触发器的同步，
/// 而建表 SQL 不在 drift 的表定义里（Migrator 不认识 fts5）。
const String kFtsTableName = 'chat_messages_fts';

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
