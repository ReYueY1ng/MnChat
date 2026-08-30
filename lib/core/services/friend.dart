/// 好友服务客户端 —— /server/friend 接口。
/// 移植自 MNClient `services/friend.py`（NewFriendClient + CreateFriendRequest）。
library;

import '../crypto/md5_sign.dart' show md5Token;
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
    this.pushChannel = '',
    this.gameSessionId = '',
    this.cid = '',
  }) : _gw = gateway ?? GatewayClient();

  Future<Map<String, Object?>> _get(String url) => _gw.get(url);

  /// 发送聊天消息 (cmd=send_chat_msg)。msg 标记 not_auth 不参与签名。
  /// 参数集与 Python friend.py:404-448 完全一致。
  Future<Map<String, Object?>> sendChatMsg({
    required Object desUin,
    required String msg,
    int showType = 1,
    int? msgtype,
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
      's2t': s2t,
      'show_type': '$showType',
      'src_uin': '$uin',
      'time': '$now',
      'token': token,
      'ver': ver,
      'pushchannel': pushChannel,
      'game_session_id': gameSessionId,
      'cid': cid,
    };
    if (msgtype != null) {
      params['msgtype'] = '$msgtype';
      params['uin'] = '${uinOverride ?? uin}';
    }
    if (extendData != null) {
      params['extend_data'] = extendData.toString();
    }

    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'send_chat_msg',
      params: params,
      notAuthKeys: {'msg'},
    );
    return _get(url);
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
}