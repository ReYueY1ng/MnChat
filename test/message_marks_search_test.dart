// 本机消息标记（收藏 / 本机删除）与全文检索的数据库级验证。
//
// 用内存库跑真实 drift 迁移（v10 会建 FTS5 trigram 虚表与三支同步触发器），
// 断言的是 SQL 行为本身：中文子串命中、单字回退 LIKE、本机删除后不再出现在
// 结果里、收藏夹按标记时间倒序。
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/message_mark.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/storage/chat_mapper.dart';

void main() {
  const owner = 279630451;
  const friendKey = 'friend_273640665';
  const groupKey = 'group_10086';

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // 触发迁移（onCreate），建表 + 建虚表。
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  /// 写一条消息（用生产映射，保证 storage 口径一致）。
  Future<void> put(
    String sessionKey,
    int uin,
    int time,
    String text,
  ) async {
    await db.insertMessage(
      chatMessageToCompanion(
        ChatMessage(uin: uin, text: text, time: time),
        sessionKey,
        myUin: owner,
        ownerUin: owner,
      ),
    );
  }

  group('全文检索', () {
    setUp(() async {
      await put(friendKey, 273640665, 1700000000, '今天一起去冒险吧');
      await put(friendKey, 273640665, 1700000100, '好呀好呀，先做作业');
      await put(groupKey, 1001, 1700000200, '群里的冒险队集合了');
    });

    test('中文三字子串命中（FTS5 trigram 路径）', () async {
      final hits = await db.searchMessages(owner, '冒险');
      // 「冒险」只有 2 字 → 走 LIKE；用 3 字关键词验证 FTS 路径。
      final fts = await db.searchMessages(owner, '冒险队');
      expect(fts.map((h) => h.text), contains('群里的冒险队集合了'));
      expect(hits.length, 2, reason: '2 字关键词应回退 LIKE 并跨会话命中两条');
    });

    test('跨会话命中 + 按会话过滤', () async {
      final all = await db.searchMessages(owner, '冒险');
      expect(all.map((h) => h.sessionKey).toSet(), {friendKey, groupKey});

      final onlyFriend = await db.searchMessages(
        owner,
        '冒险',
        sessionKey: friendKey,
      );
      expect(onlyFriend.length, 1);
      expect(onlyFriend.single.sessionKey, friendKey);
    });

    test('单字查询走 LIKE 回退且结果正确', () async {
      final hits = await db.searchMessages(owner, '作');
      expect(hits.map((h) => h.text), ['好呀好呀，先做作业']);
    });

    test('LIKE 通配符按字面量处理（% 不当作通配）', () async {
      final hits = await db.searchMessages(owner, '%');
      expect(hits, isEmpty);
    });

    test('结果按时间倒序', () async {
      final hits = await db.searchMessages(owner, '冒险');
      expect(
        hits.map((h) => h.time).toList(),
        [1700000200, 1700000000],
      );
    });

    test('本机删除的消息不出现在检索结果里', () async {
      await db.setMessageMark(
        ownerUin: owner,
        sessionKey: groupKey,
        msgUin: 1001,
        msgTime: 1700000200,
        kind: MessageMarkKind.hidden,
        on: true,
      );
      final hits = await db.searchMessages(owner, '冒险');
      expect(hits.map((h) => h.sessionKey).toSet(), {friendKey});
    });

    test('新插入的消息立刻可搜（INSERT 触发器同步虚表）', () async {
      await put(friendKey, 273640665, 1700000300, '这是新增的糖葫芦消息');
      final hits = await db.searchMessages(owner, '糖葫芦');
      expect(hits.length, 1);
      expect(hits.single.time, 1700000300);
    });

    test('删除消息后检索不到（DELETE 触发器同步虚表）', () async {
      await (db.delete(db.chatMessages)
            ..where((t) => t.content.equals('群里的冒险队集合了')))
          .go();
      final hits = await db.searchMessages(owner, '冒险队');
      expect(hits, isEmpty);
    });
  });

  group('本机标记', () {
    test('收藏 → 收藏夹列出并带正文；取消收藏后为空', () async {
      await put(friendKey, 273640665, 1700000000, '这条要收藏');
      await db.setMessageMark(
        ownerUin: owner,
        sessionKey: friendKey,
        msgUin: 273640665,
        msgTime: 1700000000,
        kind: MessageMarkKind.favorite,
        on: true,
        now: 1700000500,
      );
      var favorites = await db.favoriteMessages(owner);
      expect(favorites.length, 1);
      expect(favorites.single.text, '这条要收藏');
      expect(favorites.single.markedAt, 1700000500);

      await db.setMessageMark(
        ownerUin: owner,
        sessionKey: friendKey,
        msgUin: 273640665,
        msgTime: 1700000000,
        kind: MessageMarkKind.favorite,
        on: false,
      );
      favorites = await db.favoriteMessages(owner);
      expect(favorites, isEmpty);
    });

    test('消息行被历史替换清掉后，收藏仍列出（正文为空）', () async {
      await put(friendKey, 273640665, 1700000000, '待清理');
      await db.setMessageMark(
        ownerUin: owner,
        sessionKey: friendKey,
        msgUin: 273640665,
        msgTime: 1700000000,
        kind: MessageMarkKind.favorite,
        on: true,
      );
      await db.clearMessages(owner, friendKey);
      final favorites = await db.favoriteMessages(owner);
      expect(favorites.length, 1);
      expect(favorites.single.text, '');
      expect(favorites.single.uin, 273640665);
    });

    test('messageMarkKeys 返回 <uin>_<time> 键集合', () async {
      await db.setMessageMark(
        ownerUin: owner,
        sessionKey: friendKey,
        msgUin: 7,
        msgTime: 99,
        kind: MessageMarkKind.hidden,
        on: true,
      );
      final keys = await db.messageMarkKeys(
        owner,
        MessageMarkKind.hidden,
        sessionKey: friendKey,
      );
      expect(keys, {'7_99'});
    });

    test('不同账号的标记互不可见', () async {
      await db.setMessageMark(
        ownerUin: owner,
        sessionKey: friendKey,
        msgUin: 7,
        msgTime: 99,
        kind: MessageMarkKind.hidden,
        on: true,
      );
      final other = await db.messageMarkKeys(
        owner + 1,
        MessageMarkKind.hidden,
        sessionKey: friendKey,
      );
      expect(other, isEmpty);
    });
  });

  test('schema 版本为 10 且虚表存在', () async {
    expect(db.schemaVersion, 10);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE name = ?", variables: [Variable.withString(kFtsTableName)])
        .get();
    expect(rows, isNotEmpty, reason: 'FTS5 虚表应已创建');
  });
}
