import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/chat/message_adapter.dart';
import 'package:mnchat/core/models/messages.dart';

void main() {
  group('chatMessageId', () {
    test('同输入 → 相同 id（确定性，跨重启稳定）', () {
      expect(
        chatMessageId(
            type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hello'),
        chatMessageId(
            type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hello'),
      );
    });

    test('不同 text → 不同 id', () {
      final a = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'a');
      final b = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'b');
      expect(a, isNot(b));
    });

    test('不同 timeSeconds → 不同 id', () {
      final a = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hi');
      final b = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000001, text: 'hi');
      expect(a, isNot(b));
    });

    test('不同 uin → 不同 id', () {
      final a = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hi');
      final b = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 789, timeSeconds: 1700000000, text: 'hi');
      expect(a, isNot(b));
    });

    test('不同 session → 不同 id', () {
      final a = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hi');
      final b = chatMessageId(
          type: ChatSessionType.group, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hi');
      expect(a, isNot(b));
    });

    // 回显/推送去重契约：同一会话内 (uin, time, text) 相同的消息（乐观回显 vs 服务器确认推送）
    // 必须映射到同一个 id，桥接层才能去重。
    test('同会话相同 (uin,time,text) → 相同 id（echo/push 去重契约）', () {
      expect(
        chatMessageId(
            type: ChatSessionType.friend, sessionId: 999, uin: 456, timeSeconds: 1700000000, text: 'hi'),
        chatMessageId(
            type: ChatSessionType.friend, sessionId: 999, uin: 456, timeSeconds: 1700000000, text: 'hi'),
      );
    });

    test('编码为可读确定性字符串（含 sessionKey/uin/time/text 原始值）', () {
      final id = chatMessageId(
          type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hi');
      expect(id, 'm:friend_123:456:1700000000:hi');
    });
  });

  group('chatMessageToMessage', () {
    test('系统消息（isSystemMsg）→ Message.system，authorId=system，秒→毫秒转换正确', () {
      final m = ChatMessage(uin: 1000, text: '欢迎加入群聊', time: 1700000000, isSystemMsg: true);
      final msg = chatMessageToMessage(m, type: ChatSessionType.group, sessionId: 42);

      switch (msg) {
        case SystemMessage(:final id, :final authorId, :final createdAt, :final text):
          expect(authorId, 'system');
          expect(text, '欢迎加入群聊');
          expect(id, chatMessageId(
              type: ChatSessionType.group, sessionId: 42, uin: 1000, timeSeconds: 1700000000, text: '欢迎加入群聊'));
          // epoch 秒 → flutter_chat_core 毫秒：1700000000s → 1700000000000ms
          expect(createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
          expect(createdAt?.millisecondsSinceEpoch, 1700000000000);
        default:
          fail('期望 Message.system，实际 ${msg.runtimeType}');
      }
    });

    test('文本消息 → Message.text，authorId=uin 字符串，createdAt 正确，状态字段不设置', () {
      final m = ChatMessage(uin: 456, text: 'hello', time: 1700000000);
      final msg = chatMessageToMessage(m, type: ChatSessionType.friend, sessionId: 123);

      switch (msg) {
        case TextMessage(:final id, :final authorId, :final createdAt, :final text):
          expect(authorId, '456');
          expect(text, 'hello');
          expect(id, chatMessageId(
              type: ChatSessionType.friend, sessionId: 123, uin: 456, timeSeconds: 1700000000, text: 'hello'));
          expect(createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
          // 不设置 sentAt/deliveredAt/seenAt/reactions
          expect(msg.sentAt, isNull);
          expect(msg.deliveredAt, isNull);
          expect(msg.seenAt, isNull);
          expect(msg.reactions, isNull);
          expect(msg.replyToMessageId, isNull);
        default:
          fail('期望 Message.text，实际 ${msg.runtimeType}');
      }
    });
  });

  group('chatUserFor', () {
    test('提供 nickname → 使用 nickname', () {
      final u = chatUserFor(456, nickname: '小明', avatarUrl: 'https://cdn/x.png');
      expect(u.id, '456');
      expect(u.name, '小明');
      expect(u.imageSource, 'https://cdn/x.png');
    });

    test('无 nickname → 回退 uin 字符串', () {
      final u = chatUserFor(456);
      expect(u.id, '456');
      expect(u.name, '456');
    });

    test('avatarUrl 为 null → imageSource 透传 null', () {
      final u = chatUserFor(456, nickname: '小明');
      expect(u.imageSource, isNull);
    });
  });

  group('sessionKey', () {
    test(r'格式 ${type.name}_$id（与 chat_mapper.sessionKeyOf 一致）', () {
      expect(sessionKey(ChatSessionType.friend, 123), 'friend_123');
      expect(sessionKey(ChatSessionType.group, 456), 'group_456');
      expect(sessionKey(ChatSessionType.system, 1), 'system_1');
    });
  });
}
