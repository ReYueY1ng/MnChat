import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/protocol/lua_table.dart';
void main() {
  test('decodeLuaTable basic', () {
    final r = decodeHttpResponse('{["ret"]=0,["name"]="x"}') as Map;
    expect(r['ret'], 0);
    expect(r['name'], 'x');
  });

  test('ChatMessage from chat_query triple', () {
    final m = ChatMessage.fromChatQueryTriple([10001, 1700000000, 'hello']);
    expect(m.uin, 10001);
    expect(m.text, 'hello');
    expect(m.time, 1700000000);
    // 三元组（旧形状）没有扩展字段 → 保持 null，不能给个空串。
    expect(m.extendData, isNull);
  });

  test('ChatMessage from chat_query 五元组：第 4 个元素就是 extend_data', () {
    // 仓库 2026-10-01 真实账号实测形状：
    //   [0,[[uin, time, text, extendB64, "0"]]]
    // 离线队列也会带，早期只读前三个 → 离线消息丢扩展字段。
    final m = ChatMessage.fromChatQueryTriple(<dynamic>[
      2089540493,
      1792237208,
      '[语音] 7″',
      'eyJtbiI6eyJrIjoidm9pY2UifX0=',
      '0',
    ]);
    expect(m.uin, 2089540493);
    expect(m.text, '[语音] 7″');
    expect(m.extendData, 'eyJtbiI6eyJrIjoidm9pY2UifX0=');
    // 解码后应该就是那个信封。
    expect(decodeChatExtendData(m.extendData)?['mn'], isA<Map>());
  });

  test('五元组里的 extend_data 带 interCode 时，离线消息也能直接渲染动态表情', () {
    // 真实形状：url_encode(base64(JSON{nickname, shareType, bubble, interCode}))
    const ext =
        'eyJuaWNrbmFtZSI6IngiLCJzaGFyZVR5cGUiOjAsImJ1YmJsZSI6MCwiaW50ZXJDb2RlIjoiW21k'
        'ZW1vXTImMTAwMTMmYW5pX2V4cHJlc3Npb25fT0tbL21kZW1vXSJ9';
    final m = ChatMessage.fromChatQueryTriple(<dynamic>[
      1,
      2,
      '【您收到一条动态表情，请升级到最新版本查看】',
      ext,
      '0',
    ]);
    expect(m.interCode, '[mdemo]2&10013&ani_expression_OK[/mdemo]');
    expect(emojiCodeForMessage(text: m.text, interCode: m.interCode), isNotNull);
  });

  test('chat_query 五元组脏数据不抛（第 4 位空串/null）', () {
    for (final ext in <dynamic>[null, '', 0]) {
      final m = ChatMessage.fromChatQueryTriple(<dynamic>[1, 2, 'x', ext, '0']);
      expect(m.extendData, isNull, reason: 'ext=$ext');
    }
  });

  test('ChatMessage from group notify (ms -> sec)', () {
    final m = ChatMessage.fromGroupNotify(
      {'uin': 10002, 'text': 'hi', 'send_time': 1700000000000},
      groupId: 55,
    );
    expect(m.uin, 10002);
    expect(m.text, 'hi');
    expect(m.time, 1700000000); // ms converted to sec
    expect(m.groupId, 55);
  });
}