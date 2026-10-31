// 消息分页 / 幂等 / 发件箱的存储层契约。
//
// 这些是 P0-2（聊天记录只能看最近几十条）的底座：游标分页、最新页恢复、
// 唯一索引去重、以及失败消息的持久化队列。
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/storage/app_database.dart';

import 'support/harness.dart';

void main() {
  late AppDatabase db;
  const owner = 7;
  const key = 'friend_1001';

  setUp(() {
    db = newTestDb();
  });
  tearDown(() => db.close());

  ChatMessagesCompanion msg({
    required int uin,
    required int time,
    required String text,
    int ownerUin = owner,
    String sessionKey = key,
  }) => ChatMessagesCompanion.insert(
    content: text,
    sessionKey: sessionKey,
    uin: uin,
    time: time,
    isSuccess: true,
    isSystemMsg: false,
    isTime: false,
    direction: 'in',
    ownerUin: Value(ownerUin),
  );

  Future<void> seedFive() async {
    for (final r in [
      msg(uin: 1, time: 100, text: 'a'),
      msg(uin: 1, time: 100, text: 'b'),
      msg(uin: 1, time: 101, text: 'c'),
      msg(uin: 1, time: 102, text: 'd'),
      msg(uin: 1, time: 102, text: 'e'),
    ]) {
      await db.insertMessage(r);
    }
  }

  group('最新页与游标分页', () {
    test('latestMessages 返回最新 N 条并按 time 升序', () async {
      await seedFive();
      final rows = await db.latestMessages(owner, key, limit: 3);
      expect(rows.map((r) => r.content).toList(), ['c', 'd', 'e']);
    });

    test('latestMessages 空会话返回空表', () async {
      expect(await db.latestMessages(owner, key, limit: 10), isEmpty);
    });

    test('latestMessages 会话隔离', () async {
      await db.insertMessage(msg(uin: 1, time: 100, text: 'other', sessionKey: 'friend_2002'));
      await seedFive();
      final rows = await db.latestMessages(owner, key, limit: 10);
      expect(rows.map((r) => r.content), isNot(contains('other')));
      expect(rows, hasLength(5));
    });

    test('messagesBefore 以 (time,id) 为游标，同秒消息不重不漏', () async {
      await seedFive();
      final all = await db.latestMessages(owner, key, limit: 10);
      // id: a=1,b=2,c=3,d=4,e=5；以 e(id=5) 为界取更早一页
      final page1 = await db.messagesBefore(
        owner,
        key,
        beforeTime: all.last.time,
        beforeId: all.last.id,
        limit: 10,
      );
      expect(page1.map((r) => r.content).toList(), ['a', 'b', 'c', 'd']);

      // 以 d(id=4) 为界：只回 a/b/c，不再包含同秒的 d
      final page2 = await db.messagesBefore(
        owner,
        key,
        beforeTime: all[3].time,
        beforeId: all[3].id,
        limit: 10,
      );
      expect(page2.map((r) => r.content).toList(), ['a', 'b', 'c']);
    });

    test('messagesBefore 严格不超过 limit，且返回升序', () async {
      await seedFive();
      final page = await db.messagesBefore(
        owner,
        key,
        beforeTime: 999,
        beforeId: 999,
        limit: 2,
      );
      expect(page, hasLength(2));
      expect(page.map((r) => r.time).toList(), [102, 102]);
      expect(page.map((r) => r.content).toList(), ['d', 'e']);
    });

    test('newestMessages 取最新一批（降序），修复"先取最早"', () async {
      await seedFive();
      final newest = await db.newestMessages(owner, limit: 2);
      expect(newest.map((r) => r.content).toList(), ['e', 'd']);
      expect(newest.first.time, 102);
    });

    test('messagesInRange 含端点且升序', () async {
      await seedFive();
      final rows = await db.messagesInRange(owner, key, from: 100, to: 101);
      expect(rows.map((r) => r.content).toList(), ['a', 'b', 'c']);
    });
  });

  group('幂等写入', () {
    test('同一逻辑消息重复写入只落一行', () async {
      final row = msg(uin: 9, time: 500, text: 'same');
      await db.insertMessageIdempotent(row);
      await db.insertMessageIdempotent(row);
      final rows = await db.latestMessages(owner, key, limit: 10);
      expect(rows.where((r) => r.content == 'same'), hasLength(1));
    });

    test('不同账号 / 会话不受唯一索引影响', () async {
      final row = msg(uin: 9, time: 500, text: 'same');
      await db.insertMessageIdempotent(row);
      await db.insertMessageIdempotent(msg(uin: 9, time: 500, text: 'same', ownerUin: 8));
      await db.insertMessageIdempotent(msg(uin: 9, time: 500, text: 'same', sessionKey: 'group_9'));
      final rows = await db.latestMessages(owner, key, limit: 10);
      expect(rows, hasLength(1));
    });
  });

  group('发件箱', () {
    ChatOutboxCompanion pending({
      int ownerUin = owner,
      String text = 'hi',
      int nextAt = 100,
    }) => ChatOutboxCompanion.insert(
      ownerUin: ownerUin,
      sessionKey: key,
      typeId: 1,
      sessionId: 1001,
      content: text,
      createdAt: 90,
      nextAttemptAt: nextAt,
    );

    test('入队、到期查询、失败计数与删除', () async {
      final id = await db.enqueueOutbox(pending(nextAt: 100));
      await db.enqueueOutbox(pending(text: 'later', nextAt: 200));
      expect(await db.outboxCount(owner), 2);

      final due = await db.dueOutbox(owner, 150);
      expect(due.map((r) => r.content).toList(), ['hi']);

      await db.markOutboxRetry(id, attempts: 2, nextAttemptAt: 300, lastError: 'timeout');
      final all = await db.allOutbox(owner);
      final retried = all.firstWhere((r) => r.content == 'hi');
      expect(retried.attempts, 2);
      expect(retried.lastError, 'timeout');
      expect((await db.dueOutbox(owner, 250)).map((r) => r.content), ['later']);

      await db.deleteOutbox(id);
      expect(await db.outboxCount(owner), 1);
    });

    test('按账号隔离', () async {
      await db.enqueueOutbox(pending());
      await db.enqueueOutbox(pending(ownerUin: 8));
      expect(await db.outboxCount(owner), 1);
      expect(await db.outboxCount(8), 1);
    });
  });

  group('存储维护', () {
    test('按时间删除只影响目标账号与目标会话', () async {
      await seedFive();
      await db.insertMessage(msg(uin: 2, time: 50, text: 'old', sessionKey: 'friend_2002'));
      await db.insertMessage(msg(uin: 1, time: 50, text: 'old-other-owner', ownerUin: 8));

      final removed = await db.deleteMessagesBefore(owner, 101);
      expect(removed, 3); // a/b(100) + 2002 会话的 old(50)
      expect(await db.countMessages(owner), 3); // c(101)/d(102)/e(102)
      expect(await db.countMessages(8), 1);
    });

    test('storageStats 返回页统计，vacuum 后可执行', () async {
      await seedFive();
      final stats = await db.storageStats();
      expect(stats.pageCount, greaterThan(0));
      expect(stats.pageSize, greaterThan(0));
      expect(stats.freePages, greaterThanOrEqualTo(0));
      await db.vacuum();
      final after = await db.storageStats();
      expect(after.pageCount, greaterThan(0));
    });
  });
}
