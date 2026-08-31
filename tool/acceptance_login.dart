// 真实登录验收脚本 —— 验证 Dart 移植的 Mini World 协议链路。
//
// 凭据来源（绝不硬编码入库）：
//   1. 环境变量 MNC_UIN / MNC_PASSWD
//   2. /home/yuey1ng/mini/MNClient/config.yaml（本机 MNClient 配置）
//
// 用法:
//   fvm dart run tool/acceptance_login.dart
//
// 链路: login_v3 → WS 心跳取 s2/s2t → ChatPush alloc → 连接 gate → 拉好友列表
//
// 注意: 需要在 Flutter 项目环境运行（依赖 dio/web_socket_channel）。

import 'dart:io';

import 'package:mnchat/core/services/auth.dart';
import 'package:mnchat/core/services/chatpush.dart';
import 'package:mnchat/core/services/friend.dart';
import 'package:mnchat/core/services/group.dart';

Future<(int, String)> _resolveCreds() async {
  final envUin = Platform.environment['MNC_UIN'];
  final envPwd = Platform.environment['MNC_PASSWD'];
  if (envUin != null && envPwd != null) {
    return (int.parse(envUin), envPwd);
  }
  // 读 MNClient config.yaml（本机逆向项目配置）
  final cfgPath = '/home/yuey1ng/mini/MNClient/config.yaml';
  final f = File(cfgPath);
  if (await f.exists()) {
    final text = await f.readAsString();
    final uin = RegExp(r'uin:\s*(\d+)').firstMatch(text)?.group(1);
    final passwd = RegExp(r'passwd:\s*"?([^"\n]+)"?').firstMatch(text)?.group(1);
    if (uin != null && passwd != null) {
      return (int.parse(uin), passwd.trim());
    }
  }
  throw StateError('No credentials. Set MNC_UIN/MNC_PASSWD env or MNClient config.yaml');
}

Future<void> main() async {
  final (uin, passwd) = await _resolveCreds();
  print('== MnChat 协议验收 ==');
  print('目标账号: $uin');

  // ── 1. login_v3 ────────────────────────────────────────────────────────
  print('\n[1/7] login_v3 …');
  final login = LoginClient();
  final auth = await login.login(uin: uin, passwd: passwd);
  print('  登录成功: 昵称=${auth.name} s2=${auth.s2.substring(0, 8)}… '
      's2t=${auth.s2t} jwt_len=${auth.jwt.length}');

  // ── 2. WS 心跳取 s2/s2t ───────────────────────────────────────────────
  print('[2/7] WS 心跳 …');
  final ws = WsConnection();
  var s2 = auth.s2;
  var s2t = auth.s2t;
  try {
    final (hbs2, hbs2t) = await ws.fetchS2(jwt: auth.jwt, uin: uin);
    s2 = hbs2;
    s2t = hbs2t;
    print('  心跳成功: s2=$s2 s2t=$s2t');
  } catch (e) {
    print('  (WS 心跳失败，沿用 login_v3 sign: $e)');
  }

  // ── 3. ChatPush alloc（用心跳 s2/s2t）────────────────────────────────
  print('[3/7] ChatPush alloc …');
  final chatpush = ChatPushClient();
  final (host, token) = await chatpush.alloc(uin: uin, s2: s2, s2t: s2t, jwt: auth.jwt);
  print('  alloc 成功: host=$host token=${token.substring(0, 8)}…');

  // ── 4. 连接 gate + 心跳 ───────────────────────────────────────────────
  print('[4/7] 连接 ChatPush gate …');
  final conn = await chatpush.connectGate(
    host: host,
    token: token,
    uin: uin,
    onPush: (push) => print('  [PUSH] ${push.eventName}: ${push.args}'),
  );
  // 等 2 秒收心跳/推送
  await Future.delayed(const Duration(seconds: 2));
  print('  gate 已连接，等待推送中…');
  await conn.close();

  // ── 5. 好友列表 ───────────────────────────────────────────────────────
  print('[5/7] 好友列表 (HTTP) …');
  final friend = FriendClient(uin: uin, s2: s2, s2t: s2t);
  final resp = await friend.queryFriendList();
  final data = resp['data'];
  if (data is Map) {
    final list = data['FriendList'] ?? data['list'] ?? data['friendlist'];
    if (list is List) {
      print('  好友数: ${list.length}');
      for (final item in list.take(5)) {
        if (item is Map) {
          print('    - ${item['NickName'] ?? item['nickname']} (uin=${item['Uin'] ?? item['uin']})');
        }
      }
    } else {
      print('  好友列表响应结构: $data');
    }
  } else {
    print('  好友响应: $resp');
  }

  // ── 6. 群列表 ────────────────────────────────────────────────────────
  print('[6/7] 群列表 (HTTP) …');
  final group = GroupClient(uin: uin, s2: s2, s2t: s2t);
  final gresp = await group.queryUserGroups();
  print('  query_user_groups: $gresp');

  // ── 7. 发送消息（请求构造验证，目标为不存在 uin → 应返回业务错误）──────
  print('[7/7] 发送消息 (send_chat_msg) …');
  final sendResp = await friend.sendChatMsg(
    desUin: 100001, // 非好友目标；验证签名/格式被服务器接受（业务错误而非签名错误）
    msg: 'MnChat acceptance test',
  );
  print('  send_chat_msg: $sendResp');
  // 对照：Python MNClient 参考实现对同一请求返回 {result: 2} ——
  // 该码是"目标非好友"的业务响应，非签名错误。两者一致证明 Dart 移植正确。

  print('\n== 验收完成 ==');
  exit(0);
}