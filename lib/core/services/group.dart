/// 群聊服务客户端 —— /miniw/group 接口。
/// 移植自 MNClient `services/http_group.py` + `services/friend.py` 群方法
/// + 反编译源码 friendservice.lua (ReqLastTenGroupChatMessage 等)。
library;

import 'dart:convert';

import '../crypto/encoding.dart' show luaUrlEncode, urlsafeB64Urldecode, urlsafeB64Urlencode;
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

  /// 踢出群成员 (act=quit_group + op_uin)，群主专用。
  ///
  /// 对齐 friendservice.lua `ReqKickChatGroup` (5563)：复用的是 `quit_group`
  /// 动作，靠 `op_uin` 区分踢谁（自己退群时不带 op_uin）。
  /// extend_data = url_encode(base64(JSON{Type:"KickGroup",GroupID,GroupCreator,
  /// KickUins,group_name}))。
  Future<Map<String, Object?>> kickMembers({
    required Object groupId,
    required List<int> uins,
    int groupCreator = 0,
    String groupName = '',
    int pushChannel = 1,
  }) {
    final opUins = uins.join(',');
    final extend = <String, Object?>{
      'Type': 'KickGroup',
      'GroupID': '$groupId',
      'GroupCreator': groupCreator,
      'KickUins': opUins,
      'group_name': groupName,
    };
    return _call('quit_group', {
      'group_id': '$groupId',
      'op_uin': opUins,
      'extend_data': _encodeExtendData(extend),
      'json': '1',
      'pushchannel': '$pushChannel',
    });
  }

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

  // ── 群申请（对齐 newfriendservice.lua / friendservice.lua）───────────────

  /// 拉取"邀请我入群"的申请列表 (act=query_user_groups_apply_list)。
  /// 返回 data[]，字段：group_id, creator, group_name, invitor,
  /// group_iconid, group_icontype, MemberNum。
  Future<Map<String, Object?>> queryGroupApplyList() =>
      _call('query_user_groups_apply_list', {'json': '1'});

  /// 同意入群申请 (act=agree_group_apply)。成功 ret==0；ret==4 表示群已解散。
  Future<Map<String, Object?>> agreeGroupApply(Object groupId) =>
      _call('agree_group_apply', {'group_id': '$groupId', 'json': '1'});

  /// 拒绝入群申请 (act=reject_group_apply)。成功 ret==0；ret==4 表示群已解散。
  Future<Map<String, Object?>> rejectGroupApply(Object groupId) =>
      _call('reject_group_apply', {'group_id': '$groupId', 'json': '1'});

  /// 移除退群记录 (act=del_group_quit_list，对齐 ReqAgreeGroupMsg)。
  Future<Map<String, Object?>> delGroupQuitList(Object groupId) =>
      _call('del_group_quit_list', {'group_id': '$groupId', 'json': '1'});

  // ── 建群 / 邀请入群（对齐 friendservice.lua ReqCreateChatGroup / ReqInviteToChatGroup）

  /// 创建群 (act=create_group)。
  ///
  /// [members] 初始成员 uin 列表（含自己）；[iconId]/[iconType] 群图标；
  /// [join]=1 允许成员自行邀请好友入群。
  /// 参数对齐反编译 ReqCreateChatGroup：members=逗号分隔、group_name 先
  /// url_encode、extend_data=url_encode(base64(JSON{Type,Lord,GroupName,
  /// IconID,IconType,MemberList}))、join、json=1。
  Future<Map<String, Object?>> createGroupWithMembers({
    required String groupName,
    required List<int> members,
    int iconId = 2,
    int iconType = 1,
    int join = 0,
    int pushChannel = 1,
  }) {
    final memberList = members.join(',');
    final encodedName = luaUrlEncode(groupName);
    final extend = <String, Object?>{
      'Type': 'CreateGroup',
      'Lord': '$uin',
      'GroupName': encodedName,
      'IconID': iconId,
      'IconType': iconType,
      'MemberList': memberList,
    };
    final encodeJsonStr = _encodeExtendData(extend);
    return _call('create_group', {
      'members': memberList,
      'group_name': encodedName,
      'group_icontype': '$iconType',
      'group_iconid': '$iconId',
      'join': '$join',
      'extend_data': encodeJsonStr,
      'json': '1',
      'pushchannel': '$pushChannel',
    });
  }

  /// 邀请好友入群 (act=join_group + op_uin)。
  ///
  /// 对齐 ReqInviteToChatGroup：op_uin=逗号分隔目标 uin，extend_data=
  /// url_encode(base64(JSON{Type=InviteGroup,GroupID,GroupName,Lord,
  /// isAllowMemberInvite,uin1,uin2,name1,MemberList}))。
  Future<Map<String, Object?>> inviteToGroup({
    required Object groupId,
    required List<int> uins,
    String groupName = '',
    int lord = 0,
    int isAllowMemberInvite = 0,
    int pushChannel = 1,
  }) {
    final opUins = uins.join(',');
    final extend = <String, Object?>{
      'Type': 'InviteGroup',
      'GroupID': '$groupId',
      'GroupName': groupName,
      'Lord': '$lord',
      'isAllowMemberInvite': isAllowMemberInvite,
      'uin1': '$uin',
      'uin2': opUins,
      'name1': '',
      'MemberList': '',
    };
    final encodeJsonStr = _encodeExtendData(extend);
    return _call('join_group', {
      'group_id': '$groupId',
      'op_uin': opUins,
      'extend_data': encodeJsonStr,
      'json': '1',
      'pushchannel': '$pushChannel',
    });
  }

  // ── 群设置 / 成员管理（对齐 friendservice.lua ReqGotoTopGroup 等）──────────

  /// 群置顶/取消置顶 (act=set_group_top)。对齐 ReqGotoTopGroup (6805)。
  Future<Map<String, Object?>> setGroupTop(Object groupId,
          {required bool top}) =>
      _call('set_group_top', {
        'group_id': '$groupId',
        'status': top ? '1' : '0',
        'json': '1',
      });

  /// 群消息免打扰（服务端）(act=set_slient_group)。[ignore]=true 屏蔽本群消息。
  /// 对齐 friendservice.lua `ReqIgnoreGroup` (6734)（动作名是游戏里的 `slient` 拼写）。
  Future<Map<String, Object?>> setGroupIgnore(Object groupId,
          {required bool ignore}) =>
      _call('set_slient_group', {
        'group_id': '$groupId',
        'status': ignore ? '1' : '0',
        'json': '1',
      });

  /// 修改群资料 (act=update_group)：群名 / 群头像。
  ///
  /// 对齐 friendservice.lua `ReqUpdateInfoChatGroup` (5627)：
  /// group_name 走 url_encode（同 [createGroupWithMembers]，由调用方完成），
  /// extend_data = url_encode(base64(JSON{Type:"UpdateGroupInfo",GroupID,
  /// GroupName,iconType,iconID}))。
  Future<Map<String, Object?>> updateGroupInfo({
    required Object groupId,
    required String groupName,
    required int iconId,
    required int iconType,
    int pushChannel = 1,
  }) {
    final encodedName = luaUrlEncode(groupName);
    final extend = <String, Object?>{
      'Type': 'UpdateGroupInfo',
      'GroupID': '$groupId',
      'GroupName': groupName,
      'iconType': iconType,
      'iconID': iconId,
    };
    return _call('update_group', {
      'group_id': '$groupId',
      'group_name': encodedName,
      'group_icontype': '$iconType',
      'group_iconid': '$iconId',
      'extend_data': _encodeExtendData(extend),
      'json': '1',
      'auto_join': '0',
      'pushchannel': '$pushChannel',
    });
  }

  /// 禁言/取消禁言群成员 (act=set_silent)。
  /// 对齐 ReqGroupChatSetSilent (5782)：status=1 禁言。
  Future<Map<String, Object?>> setSilent(
    Object groupId, {
    required Object opUin,
    required bool silent,
  }) =>
      _call('set_silent', {
        'group_id': '$groupId',
        'op_uin': '$opUin',
        'status': silent ? '1' : '0',
        'json': '1',
      });

  /// 屏蔽/取消屏蔽某成员消息 (act=set_ban)。
  /// 对齐 ReqIgnoreSomeGroupMember (6685)：ban=1 屏蔽。
  Future<Map<String, Object?>> setBan(
    Object groupId, {
    required Object opUin,
    required bool ban,
  }) =>
      _call('set_ban', {
        'group_id': '$groupId',
        'op_uin': '$opUin',
        'ban': ban ? '1' : '0',
        'json': '1',
      });

  /// 举报群成员 (act=report_group_user)。对齐 ReqGroupChatReport (6912)。
  Future<Map<String, Object?>> reportGroupUser(
    Object groupId, {
    required Object opUin,
  }) =>
      _call('report_group_user', {
        'group_id': '$groupId',
        'op_uin': '$opUin',
        'json': '1',
        'pushchannel': '1',
      });

  /// 一键拒绝全部入群申请 (act=reject_group_apply_all)。
  /// 对齐 ReqRejectAllAddGroup (6875)。
  Future<Map<String, Object?>> rejectGroupApplyAll(Object groupId) =>
      _call('reject_group_apply_all', {'group_id': '$groupId', 'json': '1'});

  /// 查询退群记录 (act=query_user_groups_quit_list)。
  /// 对齐 friendservice.lua:5917。用于"被移出/退出的群"提醒列表。
  Future<Map<String, Object?>> queryUserGroupsQuitList() =>
      _call('query_user_groups_quit_list', {'json': '1'});

  /// 设置是否允许群成员邀请我入群 (act=update_user_groups, auto_join)。
  /// 对齐 ReqOpenAutoEnterToGroup (6596)。
  Future<Map<String, Object?>> updateUserGroupsAutoJoin(
          {required bool allow}) =>
      _call('update_user_groups', {
        'json': '1',
        'auto_join': allow ? '1' : '0',
      });

  /// 设置是否允许他人邀请我入群 (act=update_user_groups, join)。
  /// 对齐 friendservice.lua:6646。
  Future<Map<String, Object?>> updateUserGroupsJoin({required bool allow}) =>
      _call('update_user_groups', {
        'json': '1',
        'join': allow ? '1' : '0',
      });

  // ── 内部 ─────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _call(String act, [Map<String, String> params = const {}]) =>
      _get(_groupUrl(act, params));

  String _groupUrl(String act, [Map<String, String> extra = const {}]) =>
      buildGroupUrl(
        server: _gw.resolve('HttpFriendGroup'),
        path: kGroupPath,
        s2: s2,
        s2t: s2t,
        uin: uin,
        act: act,
        extraParams: {
          ...extra,
          'country': country,
          'lang': lang,
        },
      );

  /// extend_data 编码链：url_decode → base64_decode → JSON。
  static Map<String, Object?>? _decodeExtendData(String raw) {
    final urldecoded = Uri.decodeComponent(raw);
    final bytes = urlsafeB64Urldecode(urldecoded);
    final text = utf8.decode(bytes);
    final decoded = jsonDecode(text);
    if (decoded is Map) return decoded.cast<String, Object?>();
    return null;
  }

  /// extend_data 编码：JSON → base64 → url_encode（对齐 friendservice.lua）。
  static String _encodeExtendData(Map<String, Object?> data) {
    final jsonStr = jsonEncode(data);
    final b64 = urlsafeB64Urlencode(utf8.encode(jsonStr));
    return Uri.encodeQueryComponent(b64);
  }
}