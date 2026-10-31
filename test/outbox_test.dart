// 发件箱契约：入队去重、退避、失败保留、成功清理、手动重试、快照计数。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat/outbox.dart';
import 'package:mnchat/core/storage/app_database.dart';

import 'support/harness.dart';

class _Sender {
  _Sender(this.outcomes);

  /// true=成功，false=抛异常。
  final List<bool> outcomes;
  final List<OutboxMessage> sent = [];

  Future<bool> call(OutboxMessage m) async {
    sent.add(m);
    final ok = outcomes.isNotEmpty ? outcomes.removeAt(0) : false;
    if (!ok) throw StateError('boom');
    return true;
  }
}

void main() {
  const owner = 7;

  group('退避', () {
    test('指数增长并封顶，抖动由随机源决定', () {
      expect(
        outboxBackoff(0, random: () => 1.0),
        const Duration(seconds: 2),
      );
      expect(
        outboxBackoff(3, random: () => 1.0),
        const Duration(seconds: 16),
      );
      expect(
        outboxBackoff(20, random: () => 1.0),
        const Duration(minutes: 5),
      );
      // 全抖动：随机 0 时下界 1ms，绝不返回 0。
      expect(outboxBackoff(4, random: () => 0.0).inMilliseconds, 1);
    });
  });

  group('入队与快照', () {
    late AppDatabase db;
    late TestClock clock;
    late _Sender sender;
    late OutboxService outbox;

    setUp(() {
      db = newTestDb();
      clock = TestClock();
      sender = _Sender([]);
      outbox = OutboxService(
        getDb: () => db,
        getMyUin: () => owner,
        send: sender.call,
        now: clock.now,
        random: () => 1.0,
        autoFlush: false,
      );
    });

    tearDown(() async {
      outbox.dispose();
      await db.close();
    });

    test('同一会话/正文短时间内重复入队只保留一条', () async {
      await outbox.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'hello',
      );
      await outbox.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'hello',
      );
      expect(await db.outboxCount(owner), 1);

      // 超过去重窗口后，同一句话可以合法地再发一次。
      clock.advance(const Duration(seconds: 10));
      await outbox.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'hello',
      );
      expect(await db.outboxCount(owner), 2);
    });

    test('快照按会话计数', () async {
      await outbox.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'a',
      );
      await outbox.enqueue(
        type: ChatSessionType.group,
        sessionId: 2002,
        text: 'b',
      );
      final snap = await outbox.snapshot();
      expect(snap.total, 2);
      expect(snap.countFor('friend_1001'), 1);
      expect(snap.countFor('group_2002'), 1);
      expect(snap.countFor('friend_9999'), 0);
    });

    test('未登录不入队', () async {
      final anon = OutboxService(
        getDb: () => db,
        getMyUin: () => 0,
        send: sender.call,
        now: clock.now,
        autoFlush: false,
      );
      addTearDown(anon.dispose);
      await anon.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'x',
      );
      expect(await db.outboxCount(owner), 0);
    });
  });

  group('冲刷与重试', () {
    late AppDatabase db;
    late TestClock clock;
    late _Sender sender;
    late OutboxService outbox;

    setUp(() {
      db = newTestDb();
      clock = TestClock();
      sender = _Sender([false, true]);
      outbox = OutboxService(
        getDb: () => db,
        getMyUin: () => owner,
        send: sender.call,
        now: clock.now,
        random: () => 1.0,
        autoFlush: false,
      );
    });

    tearDown(() async {
      outbox.dispose();
      await db.close();
    });

    Future<void> enqueue(String text) => outbox.enqueue(
      type: ChatSessionType.friend,
      sessionId: 1001,
      text: text,
    );

    test('失败保留并记次数/原因，退避到期后成功则删除', () async {
      await enqueue('retry-me');
      // 入队时 nextAttemptAt = 入队 +2s，先越过它。
      clock.advance(const Duration(seconds: 3));
      expect(await outbox.flushDue(), 0);

      var rows = await db.allOutbox(owner);
      expect(rows, hasLength(1));
      expect(rows.single.attempts, 1);
      expect(rows.single.lastError, contains('boom'));
      expect(rows.single.nextAttemptAt, greaterThan(clock.now().millisecondsSinceEpoch ~/ 1000));

      // 未到期不重试。
      expect(await outbox.flushDue(), 0);
      expect(sender.sent, hasLength(1));

      clock.advance(const Duration(minutes: 10));
      expect(await outbox.flushDue(), 1);
      rows = await db.allOutbox(owner);
      expect(rows, isEmpty);
      expect(sender.sent, hasLength(2));
      expect(sender.sent.last.text, 'retry-me');
    });

    test('手动重试忽略退避，一次清空本会话', () async {
      final sender2 = _Sender([true, true]);
      final manual = OutboxService(
        getDb: () => db,
        getMyUin: () => owner,
        send: sender2.call,
        now: clock.now,
        autoFlush: false,
      );
      addTearDown(manual.dispose);
      await manual.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'a',
      );
      clock.advance(const Duration(seconds: 5));
      await manual.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'b',
      );
      expect(await manual.retrySession('friend_1001'), 2);
      expect(await db.outboxCount(owner), 0);
    });

    test('达到最大次数后不再自动重试，但保留给手动重试', () async {
      final always = _Sender(List<bool>.generate(OutboxService.maxAttempts, (_) => false));
      final failing = OutboxService(
        getDb: () => db,
        getMyUin: () => owner,
        send: always.call,
        now: clock.now,
        random: () => 1.0,
        autoFlush: false,
      );
      addTearDown(failing.dispose);
      await failing.enqueue(
        type: ChatSessionType.friend,
        sessionId: 1001,
        text: 'never',
      );
      // 首次到期时间是入队 +2s（刚刚入队时还没到期）。
      clock.advance(const Duration(seconds: 3));
      for (var i = 0; i < OutboxService.maxAttempts; i++) {
        await failing.flushDue();
        clock.advance(const Duration(hours: 1));
      }
      final rows = await db.allOutbox(owner);
      expect(rows, hasLength(1));
      expect(rows.single.attempts, OutboxService.maxAttempts);
      final nowSec = clock.now().millisecondsSinceEpoch ~/ 1000;
      expect(rows.single.nextAttemptAt, greaterThanOrEqualTo(nowSec + 23 * 3600));
      // 未到期 → 自动冲刷不再动它。
      expect(await failing.flushDue(), 0);
      expect(await failing.retrySession('friend_1001'), 0);
    });
  });
}
