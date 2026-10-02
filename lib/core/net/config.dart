/// Mini World 服务端点 URL 配置。
/// 移植自 MNClient `net/urlresolver.py` DEFAULT_URLS。
library;

const String kDefaultBase = 'https://shequ.mini1.cn:8081/';
const int kCltVersion = 80384;
const String kApiId = '110';

/// 客户端版本字符串（`url_addParams` 的 `ver`）。
///
/// 取值对齐当前游戏客户端的 `ver` 即可。
///
/// **不要再把它当成接口门禁。** 曾据单次观察写下「`miniw/bestpartner` 用
/// 1.58.0 必回 `code=9`、1.59.0 才下发数据」，该结论已撤回：`code=9`
/// (`NO_ROUTE`) / `code=23` (`WAITTING`) 是**按账号申请队列**的瞬时失败，
/// 任何版本、任何参数集单打一次都可能命中，带间隔重复才能看出真实比例。
/// 把它当版本要求会导致「换回旧版本号就以为接口坏了」这类误判。
const String kClientVersionStr = '1.59.0';
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

// ── 后端地址 ──────────────────────────────────────────────────────────────────
// 真实 mini1 host 直连（仅 Linux / Android 原生平台）。

/// 登录服务器（login_v3，调用方叠加端口随机池）。
String backendLogin() => 'https://$kLoginHost:14100';

/// WS 配置端点 base（调用方拼 `/update/?...`）。
String backendWsConfig() => 'http://wskacchm.mini1.cn:4000';

/// 主 HTTP 网关（shequ，friend/group/profile/rpc 等）。
String backendShequ() => kDefaultBase.replaceAll(RegExp(r'/$'), '');

/// ChatPush 负载均衡（minilb/alloc、minilb/rpc）。
String backendChatpush(int env) =>
    kChatpushLbUrls[env] ?? 'https://chatpush.mini1.cn:19602';