/// 群聊服务客户端 —— /miniw/group 接口。
/// 移植自 MNClient `services/http_group.py` + `services/friend.py` 群方法
/// + 反编译源码 friendservice.lua (ReqLastTenGroupChatMessage 等)。
library;

import 'dart:convert';

import '../crypto/encoding.dart' show urlsafeB64Urldecode;
import 'gateway.dart';

/// 群聊 URL 路径。
const String kGroupPath = '/miniw/group';

/// 群客户端。
class GroupClient {
  final int uin;
  final String s2;
  final String s2t;
  final GatewayClient _gw;
  final String apiId;
  final String ver;
  final String country;
  final String lang;

  GroupClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    GatewayClient? gateway,
    this.apiId = '110',
    this.ver = '1.58.0',
    this.country = 'CN',
    this.lang = '0',
  }) : _gw = gateway ?? GatewayClient();

  Future<Map<String, Object?>> _get(String url) => _gw.get(url);
  Future<Map<String, Object?>> _post(String url, Object? body,
      {String? contentType}) => _gw.post(url, data: body, contentType: contentType);

  // ── 群操作 ───────────────────────────────────────────────────────────────

  /// 创建群。
  Future<Map<String, Object?>> createGroup(Map<String, String> params) =>
      _call('create_group', params);

  /// 查询群信息。
  Future<Map<String, Object?>> queryGroup(Object groupId) =>
      _call('query_group', {'group_id': '$groupId'});

  /// 解散群。
  Future<Map<String, Object?>> dissolveGroup(Object groupId) =>
      _call('dissolve_group', {'group_id': '$groupId'});

  /// 加入群。
  Future<Map<String, Object?>> joinGroup(Map<String, String> params) =>
      _call('join_group', params);

  /// 发送加群申请。
  Future<Map<String, Object?>> sendGroupApply(Map<String, String> params) =>
      _call('send_group_apply', params);

  /// 退出群。
  Future<Map<String, Object?>> quitGroup(Object groupId) =>
      _call('quit_group', {'group_id': '$groupId'});

  /// 转让群主。
  Future<Map<String, Object?>> transferGroup(Map<String, String> params) =>
      _call('transfer_group', params);

  /// 查询我加入的群列表。
  Future<Map<String, Object?>> queryUserGroups() => _call('query_user_groups');

  /// 修改群资料/成员。
  Future<Map<String, Object?>> updateGroup(Map<String, String> params) =>
      _call('update_group', params);

  // ── 消息 ─────────────────────────────────────────────────────────────────

  /// 发送群消息。
  Future<Map<String, Object?>> sendMsg({
    required Object groupId,
    required String text,
    int msgtype = 1,
    Object? extendData,
  }) {
    final params = <String, String>{
      'group_id': '$groupId',
      'msgtype': '$msgtype',
      'text': text,
    };
    if (extendData != null) params['extend_data'] = '$extendData';
    return _call('send_msg', params);
  }

  /// 拉取群聊历史（最近约 10 条）。
  /// 返回 data[] 每项需 url_decode → base64_decode → JSON。
  Future<List<Map<String, Object?>>> sendCacheMsg(Object groupId) async {
    final resp = await _call('send_cache_msg', {'group_id': '$groupId'});
    final data = resp['data'];
    if (data is! List) return [];
    final out = <Map<String, Object?>>[];
    for (final item in data) {
      if (item is String) {
        try {
          final decoded = _decodeExtendData(item);
          if (decoded != null) out.add(decoded);
        } catch (_) {
          // skip malformed cache msg
        }
      }
    }
    return out;
  }

  /// 群未读红点。
  Future<Map<String, Object?>> groupRedDotInfo(Map<String, Object?> queryInfo) =>
      _post(_groupUrl('group_red_dot_info'),
          jsonEncode({'query_info': queryInfo}),
          contentType: 'application/json;charset:utf-8');

  // ── 内部 ─────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _call(String act, [Map<String, String> params = const {}]) =>
      _get(_groupUrl(act, params));

  String _groupUrl(String act, [Map<String, String> extra = const {}]) =>
      buildGroupUrl(
        server: _gw.resolve('HttpFriendGroup'),
        path: kGroupPath,
        uin: uin,
        ver: ver,
        apiId: apiId,
        act: act,
        s2: s2,
        s2t: s2t,
        extraParams: {
          ...extra,
          'country': country,
          'lang': lang,
        },
      );

  /// extend_data 解码链：url_decode → base64_decode → JSON。
  static Map<String, Object?>? _decodeExtendData(String raw) {
    final urldecoded = Uri.decodeComponent(raw);
    final bytes = urlsafeB64Urldecode(urldecoded);
    final text = utf8.decode(bytes);
    final decoded = jsonDecode(text);
    if (decoded is Map) return decoded.cast<String, Object?>();
    return null;
  }
}