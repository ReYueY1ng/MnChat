// 接收/推送链路验证：登录 279630451 → 连接 ChatPush → 监听 friend.msg 下行。
// 请从 273640665 给 279630451 发一条消息，看推送是否到达。
import 'dart:convert';
import 'dart:io';
import 'package:mnchat/core/services/auth.dart';
import 'package:mnchat/core/services/chatpush.dart';

Future<void> main() async {
  final uin = int.parse(Platform.environment['MNC_UIN']!);
  final passwd = Platform.environment['MNC_PASSWD']!;
  final login = LoginClient();
  final auth = await login.login(uin: uin, passwd: passwd);
  final ws = WsConnection();
  final (s2, s2t) = await ws.fetchS2(jwt: auth.jwt, uin: uin);
  print('登录 OK: ${auth.name}');

  final cp = ChatPushClient();
  final (host, token) = await cp.alloc(uin: uin, s2: s2, s2t: s2t, jwt: auth.jwt);
  print('ChatPush alloc: $host');

  final conn = await cp.connectGate(
    host: host, token: token, uin: uin,
    authToken: auth.jwt,
    onPush: (p) {
      stdout.writeln('>>> [PUSH] ${p.eventName}');
      stdout.writeln('>>>   args=${jsonEncode(p.args)}');
    },
  );
  stdout.writeln('==== 监听中：请从 273640665 给 $uin 发一条消息（60 秒）====');
  for (var i = 0; i < 60; i++) {
    await Future.delayed(const Duration(seconds: 1));
    if (i % 10 == 9) stdout.writeln('  ...${i + 1}s 连接正常');
  }
  stdout.writeln('监听结束');
  await conn.close();
  exit(0);
}
