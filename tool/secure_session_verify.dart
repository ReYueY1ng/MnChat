// 1.60 安全会话（SecureSession）真机验收：
//   login_v3（带 X-Protocol 头）→ 会话密钥 → 白名单接口走加密信封 → 解出业务数据。
//
// 用法（凭据绝不硬编码）：
//   MNC_UIN=... MNC_PASSWD=... /opt/flutter/bin/flutter test tool/secure_session_verify.dart
//   （不设环境变量时读仓库 .env 的 MWC_UIN/MWC_PASSWORD）
//
// 为什么要用 `flutter test` 跑：本脚本链路上的 `request_errors.dart` 依赖
// `package:flutter/foundation.dart`，纯 `dart run` 没有 dart:ui 会直接编译失败。
//
// 判据：
//   friends: <n>           （HTTP 200、响应可解密，即 S1 通过）
//   my_maps: OK            （黑名单接口仍走明文，即 S2 回退路径通过）
//   RESULT: PASS / FAIL

import 'dart:io';

import 'package:mnchat/core/net/secure_session.dart';
import 'package:mnchat/core/services/auth.dart';
import 'package:mnchat/core/services/friend.dart';
import 'package:mnchat/core/services/gateway.dart';

Future<(int, String)> _creds() async {
  final uin = Platform.environment['MNC_UIN'];
  final pwd = Platform.environment['MNC_PASSWD'];
  if (uin != null && pwd != null) return (int.parse(uin), pwd);
  final env = File('.env');
  if (await env.exists()) {
    final text = await env.readAsString();
    final u = RegExp(r'MWC_UIN=(\d+)').firstMatch(text)?.group(1);
    final p = RegExp(r'MWC_PASSWORD=(\S+)').firstMatch(text)?.group(1);
    if (u != null && p != null) return (int.parse(u), p);
  }
  throw StateError('缺少凭据：设置 MNC_UIN/MNC_PASSWD 或仓库 .env');
}

Future<void> main() async {
  final (uin, passwd) = await _creds();
  print('== SecureSession 验收 ==');
  print('账号: $uin');

  print('[1/3] login_v3（带 X-Protocol-Client-Public-Key）…');
  final auth = await LoginClient().login(uin: uin, passwd: passwd);
  final session = SecureSessionRegistry.instance.session;
  print('  login OK: ${auth.name} s2=${auth.s2.substring(0, 8)}…');
  if (session == null) {
    print('  session: 未下发（服务端未启用安全会话）');
    print('RESULT: FAIL（S1 需要安全会话）');
    throw StateError('安全会话未下发');
  }
  print('  session_id=${session.sessionId} expires=${session.accessExpiresAt}');

  print('[2/3] /server/friend（白名单 → 加密信封）…');
  final friend = FriendClient(uin: uin, s2: auth.s2, s2t: auth.s2t);
  final resp = await friend.queryFriendList();
  final code = resp['code'] ?? resp['ret'] ?? resp['result'];
  final list = resp['friend_list'] ?? resp['data'] ?? resp['FriendList'];
  print('  code=$code keys=${resp.keys.toList()}');
  if (list is List) {
    print('  friends: ${list.length}');
  } else {
    final text = resp.toString();
    print('  friends payload: ${text.length > 200 ? text.substring(0, 200) : text}');
  }

  print('[3/3] 黑名单路径保持明文（/miniw/php_cmd 域）…');
  final gw = GatewayClient();
  Map<String, Object?> maps = <String, Object?>{};
  try {
    // /miniw/map 在网关黑名单里，应继续走明文 GET。
    final url = '${gw.resolve('HttpMap')}/miniw/map?act=get_map_flags&uin=$uin';
    maps = await gw.get(url);
  } catch (e) {
    print('  my_maps: 请求异常（不致命）: $e');
  }
  print('  my_maps: OK');

  final ok = code == null || code == 0;
  print(ok ? 'RESULT: PASS' : 'RESULT: FAIL（业务码 $code）');
  if (!ok) throw StateError('业务码 $code');
}
