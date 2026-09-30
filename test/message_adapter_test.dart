import 'dart:convert';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/chat/message_adapter.dart';
import 'package:mnchat/core/models/emoji_catalog.dart'
    show isDynamicEmojiHint;
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
    test('extend_data 是礼物卡 → 走 Message.custom（否则只显示兜底文案）', () {
      final json = jsonEncode({
        'Type': 'SendFriendGift',
        'itemid': 43004,
        'num': 1,
        'addValue': 10,
        'src_name': '小明',
      });
      final ext = Uri.encodeQueryComponent(
        base64Encode(utf8.encode(json)),
      );
      final msg = chatMessageToMessage(
        ChatMessage(
          uin: 456,
          text: '收到来自「小明」的默契礼物',
          time: 1700000000,
          extendData: ext,
        ),
        type: ChatSessionType.friend,
        sessionId: 123,
      );
      expect(msg, isA<CustomMessage>());
      expect(msg.metadata?['extend'], ext);
    });

    test('普通文本（无卡片 extend_data）仍走 Message.text', () {
      final msg = chatMessageToMessage(
        ChatMessage(uin: 456, text: 'hello', time: 1700000000),
        type: ChatSessionType.friend,
        sessionId: 123,
      );
      expect(msg, isA<TextMessage>());
    });

    test('isLive → metadata.live（互动表情据此决定是否播动画）', () {
      final live = chatMessageToMessage(
        ChatMessage(uin: 456, text: '@IMFC&1_3', time: 1700000000, isLive: true),
        type: ChatSessionType.friend,
        sessionId: 123,
      );
      expect(live.metadata?['live'], isTrue);

      // 历史消息（从库里读出来的）不带标记 → 气泡只显示结果帧
      final history = chatMessageToMessage(
        ChatMessage(uin: 456, text: '@IMFC&1_3', time: 1700000000),
        type: ChatSessionType.friend,
        sessionId: 123,
      );
      expect(history.metadata?.containsKey('live'), isFalse);
    });

    test('isLive 是瞬态字段：不写进持久化 JSON', () {
      final m = ChatMessage(uin: 456, text: 'hi', time: 1700000000, isLive: true);
      expect(m.toJson().containsKey('is_live'), isFalse);
      expect(m.copyWith().isLive, isTrue);
    });

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

  group('动态表情：真身在 extend_data.interCode', () {
    String enc(Map<String, Object?> m) =>
        Uri.encodeQueryComponent(base64Encode(utf8.encode(jsonEncode(m))));

    test('decodeChatExtendData 解出 url_encode(base64(JSON))', () {
      final ext = enc({'nickname': '甲', 'shareType': 0, 'interCode': '[mdemo]2&1&x'});
      final m = decodeChatExtendData(ext);
      expect(m, isNotNull);
      expect(m!['nickname'], '甲');
      expect(m['interCode'], '[mdemo]2&1&x');
      expect(decodeChatExtendData('not-base64!!'), isNull);
      expect(decodeChatExtendData(null), isNull);
    });

    test('chat_notify 推送：从 extend_data 提取 interCode', () {
      const hint = '【您收到一条动态表情，请升级到最新版本查看】';
      final ext = enc({
        'nickname': '甲',
        'shareType': 0,
        'bubble': 0,
        'interCode': '[mdemo]2&10013&ani_expression_OK[/mdemo]',
      });
      final msg = ChatMessage.fromChatNotify({
        'src_uin': 123,
        'des_uin': 1,
        'chat_msg': hint,
        'send_time': 1700000000,
        'extend_data': ext,
      });
      expect(msg.text, hint); // 文本仍是低版本提示文案
      expect(msg.interCode, '[mdemo]2&10013&ani_expression_OK[/mdemo]'); // 真身在这里
    });

    test('extend_data 没有 interCode 时保持 null', () {
      final ext = enc({'nickname': '甲', 'shareType': 0});
      final msg = ChatMessage.fromChatNotify({
        'src_uin': 1,
        'chat_msg': '普通消息',
        'extend_data': ext,
      });
      expect(msg.interCode, isNull);
    });

    test('adapter 把 interCode 带进 metadata，供气泡渲染', () {
      const msg = ChatMessage(
        uin: 9,
        text: '【您收到一条动态表情，请升级到最新版本查看】',
        time: 1700000000,
        interCode: '[mdemo]2&10013&ani_expression_OK[/mdemo]',
      );
      final m = chatMessageToMessage(
        msg,
        type: ChatSessionType.friend,
        sessionId: 9,
      );
      expect(m.metadata?['interCode'], '[mdemo]2&10013&ani_expression_OK[/mdemo]');
    });

    test('老数据行：interCode 没解析过，但从 extend_data 兜底解出来', () {
      // 场景：这条消息是在「解析 interCode」之前收到的 —— 只存了 extend_data。
      final ext = enc({
        'nickname': '甲',
        'shareType': 0,
        'interCode': '[mdemo]2&10012&ani_expression_shuidiaole[/mdemo]',
      });
      final old = ChatMessage(
        uin: 9,
        text: '【您收到一条动态表情，请升级到最新版本查看】',
        time: 1700000000,
        extendData: ext, // interCode 为 null
      );
      expect(old.interCode, isNull);
      final m = chatMessageToMessage(
        old,
        type: ChatSessionType.friend,
        sessionId: 9,
      );
      // adapter 兜底解出 interCode → 气泡就能渲染表情而不是提示文案
      expect(
        m.metadata?['interCode'],
        '[mdemo]2&10012&ani_expression_shuidiaole[/mdemo]',
      );
    });

    test('emojiCodeForMessage：文本是低版本提示时取 interCode', () {
      const hint = '【您收到一条动态表情，请升级到最新版本查看】';
      expect(
        emojiCodeForMessage(
          text: hint,
          interCode: '[mdemo]2&10013&ani_expression_OK[/mdemo]',
        ),
        '[mdemo]2&10013&ani_expression_OK[/mdemo]',
      );
      expect(
        emojiCodeForMessage(text: hint, interCode: '@IMFC&1_3'),
        '@IMFC&1_3',
      );
      // 文本本身就是互动表情的 JSON 信封
      expect(
        emojiCodeForMessage(
          text: '{"content":"x","extend_data":"@IMFC&2_2"}',
          interCode: null,
        ),
        '{"content":"x","extend_data":"@IMFC&2_2"}',
      );
      // 普通文本 → null（行内表情仍由 RichTextView 处理）
      expect(emojiCodeForMessage(text: '看这个#A106', interCode: null), isNull);
      expect(emojiCodeForMessage(text: hint, interCode: ''), isNull);
      expect(emojiCodeForMessage(text: hint, interCode: 'garbage'), isNull);
    });

    // 真机抓到的 extend_data（用户日志原文）：尾部 `__` 是 `==` 填充。
    // 老解码器把 `_` 一律当 `/` → 尾部变 `//` → 乱码 → 整条消息退化成提示文案。
    const realExtend =
        'eyJidWJibGUiOjEsImludGVyQ29kZSI6IlttZGVtb10yJjEwMDEyJmFuaV9leHByZXNzaW9u'
        'X3NodWlkaWFvbGVbL21kZW1vXSIsIm5pY2tuYW1lIjoiTW9vblJlbG9hZGVkIiwic2hh'
        'cmVUeXBlIjowfQ__';

    test('真实 extend_data（尾部 _ 当填充）能解出 interCode', () {
      final m = decodeChatExtendData(realExtend);
      expect(m, isNotNull);
      expect(m!['nickname'], 'MoonReloaded');
      expect(m['bubble'], 1);
      expect(m['shareType'], 0);
      expect(m['interCode'], '[mdemo]2&10012&ani_expression_shuidiaole[/mdemo]');
    });

    test('该 payload 走完推送→气泡链路：解出「碎掉了」的表情代码', () {
      final msg = ChatMessage.fromChatNotify({
        'src_uin': 123,
        'des_uin': 1,
        'chat_msg': '【您收到一条动态表情，请升级到最新版本查看】',
        'send_time': 1700000000,
        'extend_data': realExtend,
      });
      expect(msg.interCode, '[mdemo]2&10012&ani_expression_shuidiaole[/mdemo]');
      final m = chatMessageToMessage(
        msg,
        type: ChatSessionType.friend,
        sessionId: 123,
      );
      expect(
        m.metadata?['interCode'],
        '[mdemo]2&10012&ani_expression_shuidiaole[/mdemo]',
      );
    });

    test('lenientPercentDecode：畸形 % 转义不抛异常', () {
      expect(lenientPercentDecode('a%20b'), 'a b');
      // 裸 % / 非法转义 → 当普通字符，别让整条消息退化
      expect(lenientPercentDecode('100%25的%zz'), '100%的%zz');
    });

    test('isDynamicEmojiHint：识别低版本提示文案', () {
      expect(isDynamicEmojiHint('【您收到一条动态表情，请升级到最新版本查看】'), isTrue);
      expect(isDynamicEmojiHint('   【您收到一条动态表情，请升级到最新版本查看】 '), isTrue);
      expect(isDynamicEmojiHint('普通消息'), isFalse);
      expect(isDynamicEmojiHint(null), isFalse);
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
