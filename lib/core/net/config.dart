/// Mini World 服务端点 URL 配置。
/// 移植自 MNClient `net/urlresolver.py` DEFAULT_URLS。
library;

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