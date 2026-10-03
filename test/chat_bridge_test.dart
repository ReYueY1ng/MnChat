import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/chat/chat_bridge.dart';
import 'package:mnchat/chat/message_adapter.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';

/// 构造一条确定性的 [Message.text]（epoch 秒 → flutter_chat_core 毫秒）。
Message _msg(String id, int seconds, {String text = 'x', String authorId = '1'}) =>
    Message.text(
      id: id,
      authorId: authorId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
      text: text,
    );

void main() {
  group('computeChatOps（纯函数，按 id 计算）', () {
    test('(a) 纯前缀缺失 → InsertAll at index 0', () {
      final current = [_msg('m1', 100), _msg('m2', 200)];
      final target = [_msg('m0', 50), _msg('m1', 100), _msg('m2', 200)];

      final ops = computeChatOps(current, target);
      expect(ops, isA<InsertAll>());
      final ia = ops as InsertAll;
      expect(ia.index, 0);
      expect(ia.messages.map((m) => m.id).toList(), ['m0']);
    });

    test('(a2) 多条前缀缺失 → InsertAll 升序排序', () {
      final current = [_msg('m3', 300)];
      // target 故意乱序，验证 missing 被升序排序
      final target = [_msg('m2', 200), _msg('m1', 100), _msg('m3', 300)];

      final ops = computeChatOps(current, target);
      expect(ops, isA<InsertAll>());
      final ia = ops as InsertAll;
      expect(ia.index, 0);
      expect(ia.messages.map((m) => m.id).toList(), ['m1', 'm2']);
    });

    test('(b) 存在 stale → SetAll', () {
      final current = [_msg('m1', 100), _msg('m2', 200)];
      final target = [_msg('m2', 200), _msg('m3', 300)];

      final ops = computeChatOps(current, target);
      expect(ops, isA<SetAll>());
      expect((ops as SetAll).messages.map((m) => m.id).toList(), ['m2', 'm3']);
    });

    test('(c) 交错缺失（missing 比 current.first 新）→ SetAll', () {
      final current = [_msg('m1', 100), _msg('m3', 300)];
      final target = [_msg('m1', 100), _msg('m2', 200), _msg('m3', 300)];

      final ops = computeChatOps(current, target);
      expect(ops, isA<SetAll>());
      expect((ops as SetAll).messages.map((m) => m.id).toList(), ['m1', 'm2', 'm3']);
    });

    test('(d) 完全相同 → NoOp', () {
      final current = [_msg('m1', 100), _msg('m2', 200)];
      final target = [_msg('m1', 100), _msg('m2', 200)];

      expect(computeChatOps(current, target), isA<NoOp>());
    });

    test('(e) current 为空 + target 非空 → InsertAll at 0（全部"更旧"平凡成立）', () {
      final target = [_msg('m1', 100), _msg('m2', 200)];

      final ops = computeChatOps([], target);
      expect(ops, isA<InsertAll>());
      final ia = ops as InsertAll;
      expect(ia.index, 0);
      expect(ia.messages.map((m) => m.id).toList(), ['m1', 'm2']);
    });

    test('两者皆空 → NoOp', () {
      expect(computeChatOps([], []), isA<NoOp>());
    });

    test('同 id 内容变更（update）→ SetAll（Oracle 裁决：任何 update 走全量）', () {
      final current = [_msg('m1', 100, text: 'old')];
      final target = [_msg('m1', 100, text: 'new')];

      final ops = computeChatOps(current, target);
      expect(ops, isA<SetAll>());
      switch ((ops as SetAll).messages.single) {
        case TextMessage(:final text):
          expect(text, 'new');
        default:
          fail('期望 TextMessage');
      }
    });

    test('尾部追加（missing 比 current.first 新）→ SetAll（Path A 仅覆盖前缀）', () {
      final current = [_msg('m1', 100)];
      final target = [_msg('m1', 100), _msg('m2', 200)];

      final ops = computeChatOps(current, target);
      expect(ops, isA<SetAll>());
      expect((ops as SetAll).messages.map((m) => m.id).toList(), ['m1', 'm2']);
    });

    test('按 id 而非对象相等计算 missing/stale（同 id 不同实例不算缺失）', () {
      final current = [_msg('m1', 100, text: 'a')];
      // 同 id 同内容但不同实例 → 无差异
      final target = [_msg('m1', 100, text: 'a')];

      expect(computeChatOps(current, target), isA<NoOp>());
    });
  });

  group('stabilizeSameIds（消除同 id 内容变化，规避 flutter_chat_ui change 崩溃）', () {
    test('同 id 内容变化 → 沿用 current 里的实例', () {
      final cur = _msg('m1', 100, text: 'old');
      final target = [_msg('m1', 100, text: 'new'), _msg('m2', 200)];

      final out = stabilizeSameIds([cur], target);
      expect(out.map((m) => m.id).toList(), ['m1', 'm2']);
      expect(identical(out.first, cur), isTrue);
    });

    test('同 id 即使内容相同也沿用 current 实例（按 id 稳定，不比较内容）', () {
      final cur = _msg('m1', 100, text: 'a');
      final target = _msg('m1', 100, text: 'a');

      final out = stabilizeSameIds([cur], [target]);
      expect(identical(out.single, cur), isTrue);
    });

    test('无同 id → 原样返回 target（不复制）', () {
      final target = [_msg('m1', 100), _msg('m2', 200)];
      expect(identical(stabilizeSameIds(const [], target), target), isTrue);
    });

    test('仅新消息（无同 id 冲突）→ 原样返回 target', () {
      final cur = _msg('m1', 100);
      final target = [_msg('m1', 100), _msg('m2', 200)];
      final out = stabilizeSameIds([cur], target);
      expect(identical(out.first, cur), isTrue);
      expect(identical(out.last, target.last), isTrue);
    });
  });

  group('chatHistoryToMessages（映射 + 按 id 去重）', () {
    test('echo/push 同 id 只保留一条（确定性 id 去重契约）', () {
      final history = [
        ChatMessage(uin: 1, text: 'hi', time: 100),
        ChatMessage(uin: 1, text: 'hi', time: 100), // 同 (uin,time,text) → 同 id
        ChatMessage(uin: 1, text: 'yo', time: 200),
      ];

      final msgs = chatHistoryToMessages(history, ChatSessionType.friend, 123);
      expect(msgs, hasLength(2));
      expect(msgs.map((m) => m.id).toSet().length, 2);
    });

    test('保持升序稳定（historyOf 已升序，去重不改变相对顺序）', () {
      final history = [
        ChatMessage(uin: 1, text: 'a', time: 100),
        ChatMessage(uin: 1, text: 'b', time: 200),
        ChatMessage(uin: 1, text: 'c', time: 300),
      ];

      final msgs = chatHistoryToMessages(history, ChatSessionType.friend, 123);
      expect(msgs.map((m) => m.id).toList(), [
        chatMessageId(type: ChatSessionType.friend, sessionId: 123, uin: 1, timeSeconds: 100, text: 'a'),
        chatMessageId(type: ChatSessionType.friend, sessionId: 123, uin: 1, timeSeconds: 200, text: 'b'),
        chatMessageId(type: ChatSessionType.friend, sessionId: 123, uin: 1, timeSeconds: 300, text: 'c'),
      ]);
    });

    test('空历史 → 空列表', () {
      expect(chatHistoryToMessages([], ChatSessionType.friend, 123), isEmpty);
    });
  });

  group('ChatBridge（真实 ChatService(db: null)，无 Riverpod）', () {
    test('controllerFor 用初始历史创建控制器（seed 在 controllerFor 之前）', () {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);
      service.addLocalMessage(ChatSessionType.friend, 123, 'seed');

      final c = bridge.controllerFor(ChatSessionType.friend, 123);
      expect(c.messages, hasLength(1));

      final expected = chatMessageToMessage(
        service.historyOf(ChatSessionType.friend, 123).first,
        type: ChatSessionType.friend,
        sessionId: 123,
      );
      expect(c.messages, [expected]);

      // 幂等：同一会话再次调用返回同一实例
      expect(identical(bridge.controllerFor(ChatSessionType.friend, 123), c), isTrue);
      bridge.dispose();
    });

    test('controllerFor 之后 addLocalMessage → eventStream 触发 reconcile → 控制器获得新消息', () async {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);
      final c = bridge.controllerFor(ChatSessionType.friend, 123);
      expect(c.messages, isEmpty);

      service.addLocalMessage(ChatSessionType.friend, 123, 'hello');
      await pumpEventQueue();

      expect(c.messages, hasLength(1));
      final expected = chatMessageToMessage(
        service.historyOf(ChatSessionType.friend, 123).first,
        type: ChatSessionType.friend,
        sessionId: 123,
      );
      expect(c.messages, [expected]);
      bridge.dispose();
    });

    test('已有历史后再收到更新消息 → reconcile 仍正确追加（SetAll 路径）', () async {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);
      service.addLocalMessage(ChatSessionType.friend, 123, 'one');
      final c = bridge.controllerFor(ChatSessionType.friend, 123);
      expect(c.messages, hasLength(1));

      service.addLocalMessage(ChatSessionType.friend, 123, 'two');
      await pumpEventQueue();

      expect(c.messages, hasLength(2));
      final expected = [
        for (final m in service.historyOf(ChatSessionType.friend, 123))
          chatMessageToMessage(m, type: ChatSessionType.friend, sessionId: 123),
      ];
      expect(c.messages, expected);
      bridge.dispose();
    });

    test('重复投递同一逻辑消息 → 控制器中该 id 恰好一次（幂等）', () async {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);
      final c = bridge.controllerFor(ChatSessionType.friend, 123);

      service.addLocalMessage(ChatSessionType.friend, 123, 'hi');
      await pumpEventQueue();
      expect(c.messages, hasLength(1));

      // 模拟重复投递：同一事件处理两次（echo + 服务器确认推送）
      final event = ChatEvent(
        ChatSessionType.friend,
        123,
        service.historyOf(ChatSessionType.friend, 123).last,
      );
      bridge.handleEvent(event);
      bridge.handleEvent(event);

      final ids = c.messages.map((m) => m.id).toList();
      expect(ids, hasLength(1));
      expect(ids.toSet().length, 1);
      bridge.dispose();
    });

    test('无控制器的会话事件 → 不抛异常，之后创建控制器仍能拿到历史', () async {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);

      service.addLocalMessage(ChatSessionType.friend, 999, 'hi');
      await pumpEventQueue(); // 不应抛异常

      expect(bridge.controllerFor(ChatSessionType.friend, 999).messages, hasLength(1));
      bridge.dispose();
    });

    test('不同会话互不干扰（按 sessionKey 隔离）', () async {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);

      service.addLocalMessage(ChatSessionType.friend, 111, 'a');
      service.addLocalMessage(ChatSessionType.group, 222, 'b');
      await pumpEventQueue();

      final cf = bridge.controllerFor(ChatSessionType.friend, 111);
      final cg = bridge.controllerFor(ChatSessionType.group, 222);
      expect(cf.messages, hasLength(1));
      expect(cg.messages, hasLength(1));
      expect(identical(cf, cg), isFalse);
      bridge.dispose();
    });

    test('dispose 后事件不再触发 reconcile，且不抛异常', () async {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);
      final c = bridge.controllerFor(ChatSessionType.friend, 123);

      service.addLocalMessage(ChatSessionType.friend, 123, 'before');
      await pumpEventQueue();
      expect(c.messages, hasLength(1));

      bridge.dispose();

      service.addLocalMessage(ChatSessionType.friend, 123, 'after');
      await pumpEventQueue(); // 订阅已取消，不应抛异常
      expect(c.messages, hasLength(1)); // 未更新
    });

    test('dispose 后 controllerFor 不再返回旧控制器（map 已清空）', () {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);
      service.addLocalMessage(ChatSessionType.friend, 123, 'seed');
      final c = bridge.controllerFor(ChatSessionType.friend, 123);
      expect(c.messages, hasLength(1));

      bridge.dispose();

      // dispose 后 map 已清空 → 重新创建（新控制器，初始历史仍来自 service）
      final c2 = bridge.controllerFor(ChatSessionType.friend, 123);
      expect(identical(c2, c), isFalse);
      expect(c2.messages, hasLength(1));
    });
  });
}
