import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat/message_upserter.dart'
    show mergeHistory, preserveEmojiFields;

/// 历史整段替换时的扩展字段回填：
/// `chat_query` 回的是五元组 `[who, ts, text, extend, "0"]`（第 4 位就是 extend_data），
/// 但同一消息也可能先经推送入内存 —— 后来者没带字段时用已有的补，带了就别覆盖。
void main() {
  ChatMessage msg({String? interCode, String? extend, int time = 100}) =>
      ChatMessage(
        uin: 42,
        text: '【您收到一条动态表情，请升级到最新版本查看】',
        time: time,
        interCode: interCode,
        extendData: extend,
      );

  test('三元组历史缺 interCode 时，用旧消息补回', () {
    const code = '[mdemo]2&10013&ani_expression_OK[/mdemo]';
    final existing = [msg(interCode: code, extend: 'EXT')];
    final incoming = [msg()]; // 模拟没带字段的那条

    final out = preserveEmojiFields(incoming, existing);
    expect(out.single.interCode, code);
    expect(out.single.extendData, 'EXT');
  });

  test('离线队列带回的 extend_data 不被旧值覆盖', () {
    // 旧消息在内存里没带字段，新拉到的五元组带了 —— 必须保留新值。
    final existing = [msg()];
    final incoming = [msg(extend: 'NEW_EXT')];

    final out = preserveEmojiFields(incoming, existing);
    expect(out.single.extendData, 'NEW_EXT');
  });

  test('新消息自带 interCode 时不覆盖', () {
    const oldCode = '[mdemo]2&1&a[/mdemo]';
    const newCode = '[mdemo]2&1&b[/mdemo]';
    final out = preserveEmojiFields(
      [msg(interCode: newCode)],
      [msg(interCode: oldCode)],
    );
    expect(out.single.interCode, newCode);
  });

  test('时间/发送者不同则不匹配（不会串消息）', () {
    const code = '[mdemo]2&1&a[/mdemo]';
    final out = preserveEmojiFields(
      [msg(time: 200)],
      [msg(interCode: code, time: 100)],
    );
    expect(out.single.interCode, isNull);
  });

  test('旧消息没有表情字段时原样返回', () {
    final incoming = [msg()];
    final out = preserveEmojiFields(incoming, [msg()]);
    expect(out.single.interCode, isNull);
    expect(out, same(incoming));
  });

  test('没有旧缓存时原样返回', () {
    final incoming = [msg()];
    expect(preserveEmojiFields(incoming, null), same(incoming));
    expect(preserveEmojiFields(incoming, const []), same(incoming));
  });

  group('mergeHistory（历史拉回时与已有消息合并，不吞消息）', () {
    ChatMessage m(String text, int time) =>
        ChatMessage(uin: 42, text: text, time: time);

    test('本次未返回、但已在内存里的消息保留（chat_query 消费式读取）', () {
      final existing = [m('推送收到的', 300)];
      final incoming = [m('离线队列里的', 100)];

      final out = mergeHistory(incoming, existing);
      expect(out.map((e) => e.text), containsAll(['离线队列里的', '推送收到的']));
      expect(out, hasLength(2));
    });

    test('同 (uin,time,text) 去重，保留 incoming 的那份', () {
      final existing = [m('hi', 100)];
      final incomingMsg = m('hi', 100);
      final incoming = [incomingMsg];

      final out = mergeHistory(incoming, existing);
      expect(out, hasLength(1));
      expect(identical(out.single, incomingMsg), isTrue);
    });

    test('无旧历史时原样返回 incoming（不复制）', () {
      final incoming = [m('a', 1)];
      expect(mergeHistory(incoming, null), same(incoming));
      expect(mergeHistory(incoming, const []), same(incoming));
    });
  });
}
