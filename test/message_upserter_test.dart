import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat/message_upserter.dart'
    show preserveEmojiFields;

/// 历史整段替换时的表情字段回填：
/// `chat_query` 只回 `[who, ts, text]` 三元组（没有 extend_data），
/// 不补回来就会把收到的动态表情冲成「请升级到最新版本查看」。
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
    final incoming = [msg()]; // 模拟 chat_query 回的裸三元组

    final out = preserveEmojiFields(incoming, existing);
    expect(out.single.interCode, code);
    expect(out.single.extendData, 'EXT');
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
}
