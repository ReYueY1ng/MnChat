// 综合发送验证: 带完整 extend_data 发送 → 立即 chat_query 查回
import 'dart:convert';
import 'dart:io';
import 'package:mnchat/core/services/auth.dart';
import 'package:mnchat/core/services/chatpush.dart';
import 'package:mnchat/core/services/friend.dart';
import 'package:mnchat/core/crypto/md5_sign.dart';
import 'package:mnchat/core/net/http_factory.dart';

Future<void> main() async {
  final uin = int.parse(Platform.environment['MNC_UIN']!);
  final passwd = Platform.environment['MNC_PASSWD']!;
  final login = LoginClient();
  final auth = await login.login(uin: uin, passwd: passwd);
  final ws = WsConnection();
  final (s2, s2t) = await ws.fetchS2(jwt: auth.jwt, uin: uin);
  print('登录 OK: ${auth.name}');

  final fc = FriendClient(uin: uin, s2: s2, s2t: s2t);

  // 真实客户端 extend_data = url_encode(base64(JSON{nickname,shareType,bubble,interCode}))
  final tShare = {'nickname': auth.name, 'shareType': 0, 'bubble': 0, 'interCode': null};
  final extRaw = base64Encode(utf8.encode(jsonEncode(tShare)));
  final ext = Uri.encodeQueryComponent(extRaw);

  // 1) 带完整参数发送
  final msg = 'MnChat 消息投递验证';
  final r = await fc.sendChatMsg(desUin: 273640665, msg: msg, extendData: ext);
  print('发送: $r');
  await Future.delayed(const Duration(seconds: 2));

  // 2) 立即 chat_query 查回
  final cp = ChatPushClient();
  final seq = DateTime.now().microsecondsSinceEpoch % 100000;
  final msec = DateTime.now().millisecondsSinceEpoch % 100000000;
  try {
    final q = await cp.rpcHttp(uin: uin, s2: s2, s2t: s2t,
      message: ['buddysvr', 'chat_query', seq, msec, [273640665], <String, Object?>{}]);
    final s = jsonEncode(q ?? '');
    print('chat_query(${s.length} chars): ${s.substring(0, s.length > 300 ? 300 : s.length)}');
  } catch (e) {
    print('chat_query ERR: $e');
  }
  exit(0);
}
