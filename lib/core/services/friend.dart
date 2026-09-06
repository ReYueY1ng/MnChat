/// 好友服务客户端 —— /server/friend 接口。
/// 移植自 MNClient `services/friend.py`（NewFriendClient + CreateFriendRequest）。
library;

import '../crypto/md5_sign.dart' show httpGetRealNameMobileSum, md5Token;
import 'gateway.dart';

/// 好友服务 URL 路径。
const String kFriendPath = '/server/friend';

/// 好友客户端。
class FriendClient {
  final int uin;
  final String s2;
  final String s2t;
  final GatewayClient _gw;
  final String apiId;
  final String ver;
  final String country;
  final String lang;
  final String pushChannel;
  final String gameSessionId;
  final String cid;

  FriendClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    GatewayClient? gateway,
    this.apiId = '110',
    this.ver = '1.58.0',
    this.country = 'CN',
    this.lang = '0',
    this.pushChannel = '1', // 真实客户端 get_push_chat_push_channel() 配置值（通常 1）
    this.gameSessionId = '',
    this.cid = '',
  }) : _gw = gateway ?? GatewayClient();

  Future<Map<String, Object?>> _get(String url) => _gw.get(url);

  /// 发送聊天消息 (cmd=send_chat_msg)。msg 标记 not_auth 不参与签名。
  /// 参数集对齐反编译源码 mainchatinterface.lua:131-132（真实客户端总是带
  /// uin=src_uin、msgtype=1，且 **URL 末尾追加 http_getRealNameMobileSum(text)
  /// 的 mmsum/cthash** —— 缺 cthash 服务器返回 result:2）。
  Future<Map<String, Object?>> sendChatMsg({
    required Object desUin,
    required String msg,
    int showType = 1,
    int msgtype = 1, // 1=文本（Lua 原码固定 msgtype=1）
    Object? extendData,
    Object? uinOverride,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);

    final params = <String, String>{
      'apiid': apiId,
      'country': country,
      'des_uin': '$desUin',
      'encrypt_ver': '1',
      'lang': lang,
      'msg': msg,
      'msgtype': '$msgtype',
      's2t': s2t,
      'show_type': '$showType',
      'src_uin': '$uin',
      'time': '$now',
      'token': token,
      'uin': '${uinOverride ?? uin}',
      'ver': ver,
      'pushchannel': pushChannel,
      'game_session_id': gameSessionId,
      'cid': cid,
    };
    if (extendData != null) {
      params['extend_data'] = extendData.toString();
    }

    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'send_chat_msg',
      params: params,
      // 注意: msg **必须参与签名**（穷举验证 cmd+msg 都入签名 →
      // {"send_time":..,"result":0} 成功；排除 msg 签名 → result:2）。
      // 但 extend_data 是 **notAuth**（反编译源码 CreateFriendRequest.addparam
      // 强制 extend_data.notAuth=true）→ 出现在 URL 但不参与签名。
      notAuthKeys: {'extend_data'},
    );
    // URL 末尾追加 http_getRealNameMobileSum(msg) 的 mmsum/cthash（实名/内容校验）
    final sum = httpGetRealNameMobileSum(
      msg,
      uin: uin,
      s2t: s2t,
      nowVal: now,
    );
    return _get('$url&$sum');
  }

  /// 好友列表 (cmd=query_friend_list)。与 Python friend.py:450-466 一致。
  /// 注意：query_friend_list 的 params **不含 s2t**。
  Future<Map<String, Object?>> queryFriendList({String? relation}) async {
    final params = <String, String>{
      'uin': '$uin',
      'apiid': apiId,
      'ver': ver,
      'country': country,
      'lang': lang,
    };
    if (relation != null) params['relation'] = relation;
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'query_friend_list',
      params: params,
    );
    return _get(url);
  }

  /// 查询最近一起玩过的伙伴 (cmd=query_recent_partner)。
  /// 与 Python friend.py:494-514 一致。
  Future<Map<String, Object?>> queryRecentPartner() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    final params = <String, String>{
      'apiid': apiId,
      'country': country,
      'lang': lang,
      's2t': s2t,
      'time': '$now',
      'token': token,
      'uin': '$uin',
      'ver': ver,
    };
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'query_recent_partner',
      params: params,
    );
    return _get(url);
  }

  /// 发送好友申请 (cmd=apply_friend)。[from] 为来源统计：0=扫码/1=迷你号/5=其他。
  /// 对齐反编译源码 friendservice.lua ReqAddFriendSync (2171+)，含 token 签名。
  Future<Map<String, Object?>> applyFriend({
    required Object desUin,
    String from = '5',
    String? rpExt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    final params = <String, String>{
      'apiid': apiId,
      'country': country,
      'des_uin': '$desUin',
      'from': from,
      'lang': lang,
      'pushchannel': pushChannel,
      's2t': s2t,
      'src_uin': '$uin',
      'time': '$now',
      'token': token,
      'uin': '$uin',
      'ver': ver,
      'game_session_id': gameSessionId,
      'cid': cid,
    };
    if (rpExt != null) params['rp_ext'] = rpExt;
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'apply_friend',
      params: params,
    );
    return _get(url);
  }

  /// 通过好友申请 (cmd=accept_apply)。对齐 friendservice.lua ReqAgreeAddFriend (2304+)。
  Future<Map<String, Object?>> acceptApply({required Object desUin}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    final params = <String, String>{
      'apiid': apiId,
      'country': country,
      'des_uin': '$desUin',
      'lang': lang,
      'pushchannel': pushChannel,
      's2t': s2t,
      'src_uin': '$uin',
      'time': '$now',
      'token': token,
      'uin': '$uin',
      'ver': ver,
      'game_session_id': gameSessionId,
      'cid': cid,
    };
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'accept_apply',
      params: params,
    );
    return _get(url);
  }

  /// 拒绝好友申请 (cmd=reject_apply)。对齐 friendservice.lua ReqRejectAddFriend (2406+)。
  Future<Map<String, Object?>> rejectApply({required Object desUin}) async {
    final params = <String, String>{
      'apiid': apiId,
      'country': country,
      'des_uin': '$desUin',
      'lang': lang,
      'pushchannel': pushChannel,
      'src_uin': '$uin',
      'ver': ver,
      'game_session_id': gameSessionId,
      'cid': cid,
    };
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'reject_apply',
      params: params,
    );
    return _get(url);
  }
}
