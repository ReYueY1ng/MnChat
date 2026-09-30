import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat/push_dispatcher.dart';
import 'package:mnchat/core/services/chatpush.dart';

/// ChatPushDispatcher 行为测试：重点锁定「动态/互动表情的真身在
/// extend_data.interCode」这条链路 —— 之前只解了文本，气泡就只显示
/// 「【您收到一条动态表情，请升级到最新版本查看】」。
void main() {
  /// 构造只关心好友消息 upsert 的 dispatcher。
  (ChatPushDispatcher, List<ChatMessage>) makeDispatcher({int myUin = 1}) {
    final upserted = <ChatMessage>[];
    final d = ChatPushDispatcher(
      getMyUin: () => myUin,
      upsertFriendMessage: (uin, m) => upserted.add(m),
      upsertGroupMessage: (_, _) {},
      loadSessions: () async {},
      emitSessionSnapshot: () {},
      getConn: () => null,
      friendSessions: {},
    );
    return (d, upserted);
  }

  /// 按真机编码构造 extend_data：url_encode(base64(JSON))。
  String encodeExtend(Map<String, Object?> m) =>
      Uri.encodeQueryComponent(base64Encode(utf8.encode(jsonEncode(m))));

  test('chat_notify 带 interCode：消息保留表情代码（而非只解文本）', () {
    final (d, upserted) = makeDispatcher();
    d.handlePush(
      ChatPushPush('client', 'on', [
        'friend.msg',
        {
          'cmd': 'chat_notify',
          'src_uin': '42',
          'des_uin': '1',
          'send_time': '1788109122',
          'chat_msg': '【您收到一条动态表情，请升级到最新版本查看】',
          'extend_data': encodeExtend({
            'nickname': '甲',
            'shareType': 0,
            'bubble': 0,
            'interCode': '[mdemo]2&10013&ani_expression_OK[/mdemo]',
          }),
        },
      ]),
    );

    expect(upserted.length, 1);
    expect(upserted.single.uin, 42);
    expect(upserted.single.text, '【您收到一条动态表情，请升级到最新版本查看】');
    expect(upserted.single.interCode, '[mdemo]2&10013&ani_expression_OK[/mdemo]');
  });

  test('chat_notify 普通消息：interCode 为 null，文本不变', () {
    final (d, upserted) = makeDispatcher();
    d.handlePush(
      ChatPushPush('client', 'on', [
        'friend.msg',
        {
          'cmd': 'chat_notify',
          'src_uin': '42',
          'des_uin': '1',
          'send_time': '1788109122',
          'chat_msg': '你好',
        },
      ]),
    );
    expect(upserted.single.text, '你好');
    expect(upserted.single.interCode, isNull);
  });

  test('收件人不是我 → 忽略', () {
    final (d, upserted) = makeDispatcher(myUin: 7);
    d.handlePush(
      ChatPushPush('client', 'on', [
        'friend.msg',
        {
          'cmd': 'chat_notify',
          'src_uin': '42',
          'des_uin': '1',
          'chat_msg': 'x',
        },
      ]),
    );
    expect(upserted, isEmpty);
  });
}
