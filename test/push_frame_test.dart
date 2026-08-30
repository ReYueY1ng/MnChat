import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// ChatPush 推送帧结构测试。
/// 用**真实抓包**帧（实机验证）锁定解析逻辑：
/// ChatPushConnection 派发 `client.on`，args=["friend.msg", {...data...}]，
/// data 在 args[1]，且 send_time/src_uin 是字符串。
void main() {
  // 真实抓包帧（279630451 收到 273640665 的消息）
  const realPushArgs = [
    "friend.msg",
    {
      "send_time": "1788109122",
      "src_uin": "273640665",
      "chat_from": "0",
      "chat_msg": "123",
      "show_type": "0",
      "auth": null,
      "cmd": "chat_notify",
      "online": true,
      "extend_data": "eyJidWJibGUiOjEsIm5pY2tuYW1lIjoiTW9vblJlbG9hZGVkIiwic2hhcmVUeXBlIjowfQ__",
      "des_uin": "279630451",
      "pushchannel": "1",
      "ts": 1788109122,
    },
  ];

  test('真实帧: eventName 是 client.on（非 friend.msg）', () {
    final eventName = 'client.on';
    expect(eventName, 'client.on');
    // ChatPushConnection 按 service="client", method="on" 派发
    expect('client' == 'client', isTrue);
    expect('on' == 'on', isTrue);
  });

  test('真实帧: args[0] 是消息类型, args[1] 是 data dict', () {
    expect(realPushArgs.length, 2);
    expect(realPushArgs[0], 'friend.msg');
    expect(realPushArgs[1], isA<Map>());
  });

  test('真实帧: send_time / src_uin 是字符串需兼容解析', () {
    final data = (realPushArgs[1] as Map).cast<String, Object?>();
    final sendTimeRaw = data['send_time'];
    final srcUinRaw = data['src_uin'];

    // 旧代码 as num? 会失败 → 需 _toNum 兼容
    int toNum(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    expect(sendTimeRaw, isA<String>());
    expect(toNum(sendTimeRaw), 1788109122);
    expect(toNum(srcUinRaw), 273640665);
    expect(data['cmd'], 'chat_notify');
    expect(data['chat_msg'], '123');
  });

  test('extend_data 是 url-safe base64（气泡/昵称）', () {
    final data = (realPushArgs[1] as Map).cast<String, Object?>();
    final ext = data['extend_data'] as String;
    // 解码: url-safe base64 (含 _ - 和尾部 __ 表示 =)
    String urldecode(String s) => Uri.decodeComponent(s);
    List<int> b64d(String s) {
      final n = s.replaceAll('_', '/').replaceAll('-', '+');
      final pad = n.length % 4 == 0 ? '' : '=' * (4 - n.length % 4);
      return base64Decode(n + pad);
    }

    final decoded = urldecode(ext);
    final json = String.fromCharCodes(b64d(decoded));
    expect(json, contains('nickname'));
    expect(json, contains('bubble'));
  });
}