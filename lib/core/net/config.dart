/// Mini World 服务端点 URL 配置。
/// 移植自 MNClient `net/urlresolver.py` DEFAULT_URLS。
library;

import 'package:flutter/foundation.dart' show kIsWeb;

const String kDefaultBase = 'https://shequ.mini1.cn:8081/';
const int kCltVersion = 80384;
const String kApiId = '110';
const String kClientVersionStr = '1.58.0';
const String kUa = 'Rainbow/1.0 (Windows_RT; U; Linux 6.2; zh)';

/// 登录服务器
const String kLoginHost = 'wskacchm.mini1.cn';
const List<int> kLoginPorts = [14100, 14110, 14120, 14130, 14140, 14150];
const String kLoginPath = '/man_machine/login_v3';

/// WS 配置（s2/s2t 心跳）
const String kWsConfigUrl = 'http://wskacchm.mini1.cn:4000/update/';

/// ChatPush 负载均衡器 URL（按环境）
const Map<int, String> kChatpushLbUrls = {
  0: 'https://chatpush.mini1.cn:19602', // prod
  1: 'http://120.24.64.132:19601', // test
  2: 'http://211.159.183.137:19601', // env 2
  10: 'http://chatpush.miniworldgame.com:19601', // miniworldgame
  11: 'http://shequ.miniworldplus.com:19090', // shequ
};

const Map<String, String> kDefaultUrls = {
  'Http': kDefaultBase,
  'HttpMap': kDefaultBase,
  'HttpMail': kDefaultBase,
  'HttpCommon': kDefaultBase,
  'HttpFriend': kDefaultBase,
  'HttpFriendGroup': kDefaultBase,
  'HttpDevelopStore': kDefaultBase,
  'HttpCheckString': kDefaultBase,
  'HttpPlayerArchive': kDefaultBase,
  'HttpArchiveBackSvr': kDefaultBase,
  'HttpQuickupRent': kDefaultBase,
  'HttpQuickupRentApi': kDefaultBase,
  'HttpCreditScore': 'https://credit-api.mini1.cn/',
  'HttpVersion': 'http://static-www.mini1.cn/version/pc/',
  'HttpGetToken': kDefaultBase,
};

// ── 平台感知后端地址 ──────────────────────────────────────────────────────────
// 原生：真实 mini1 host 直连。Web：同源代理前缀（本地 tool/web_proxy.dart
// 把 /mw/<backend>/* 转发到对应后端），从而规避浏览器 CORS。
// Uri.base.origin = 当前页面 origin（如 http://localhost:8080）。

/// 登录服务器（login_v3。原生用端口随机池；Web 由代理固定转发到 14100）。
String backendLogin() => kIsWeb
    ? '${Uri.base.origin}/mw/login'
    : 'https://$kLoginHost:14100';

/// WS 配置端点 base（调用方拼 `/update/?...`）。
String backendWsConfig() => kIsWeb
    ? '${Uri.base.origin}/mw/wsconfig'
    : 'http://wskacchm.mini1.cn:4000';

/// 主 HTTP 网关（shequ，friend/group/profile/rpc 等）。
String backendShequ() =>
    kIsWeb ? '${Uri.base.origin}/mw/shequ' : kDefaultBase.replaceAll(RegExp(r'/$'), '');

/// ChatPush 负载均衡（minilb/alloc、minilb/rpc）。
String backendChatpush(int env) => kIsWeb
    ? '${Uri.base.origin}/mw/chatpush'
    : (kChatpushLbUrls[env] ?? 'https://chatpush.mini1.cn:19602');