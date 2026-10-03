/// 好友服务客户端 —— /server/friend 接口。
/// 移植自 MNClient `services/friend.py`（NewFriendClient + CreateFriendRequest）。
library;

import 'dart:convert';

import '../crypto/md5_sign.dart' show httpGetRealNameMobileSum, md5Token;
import '../models/friend_tag.dart' show encodeFriendLabel;
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
    int issys = 0, // 1=系统类分享消息（对齐 ReqSendInviteChatMessage）
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
    if (issys != 0) params['issys'] = '$issys';
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

  // ── 黑名单（对齐 friendservice.lua ReqAddBlacklist / ReqRemoveBlacklist / ReqClearBlacklist）

  /// 加入黑名单 (cmd=handle_black, op_type=1)。
  Future<Map<String, Object?>> addBlacklist(Object desUin) =>
      _handleBlack(desUin, 1);

  /// 移出黑名单 (cmd=handle_black, op_type=0)。
  Future<Map<String, Object?>> removeBlacklist(Object desUin) =>
      _handleBlack(desUin, 0);

  Future<Map<String, Object?>> _handleBlack(Object desUin, int opType) async {
    final params = <String, String>{
      'apiid': apiId,
      'country': country,
      'des_uin': '$desUin',
      'lang': lang,
      'op_type': '$opType',
      'src_uin': '$uin',
      'ver': ver,
      'game_session_id': gameSessionId,
      'cid': cid,
    };
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'handle_black',
      params: params,
    );
    return _get(url);
  }

  /// 清空黑名单 (cmd=clear_black)。
  Future<Map<String, Object?>> clearBlacklist() async {
    final params = <String, String>{
      'src_uin': '$uin',
    };
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      cmd: 'clear_black',
      params: params,
    );
    return _get(url);
  }

  // ── 关注 / 粉丝（对齐 friendservice.lua ReqFollowPlayer / get_user_fans_list）

  /// 关注/取关玩家 (cmd=attention_friend)。[follow]=true 关注。
  /// 对齐 ReqFollowPlayer：op_type 1=关注 0=取关，含 token 签名。
  Future<Map<String, Object?>> attentionFriend(Object desUin,
      {required bool follow}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    final params = <String, String>{
      'apiid': apiId,
      'country': country,
      'des_uin': '$desUin',
      'lang': lang,
      'op_type': follow ? '1' : '0',
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
      cmd: 'attention_friend',
      params: params,
    );
    return _get(url);
  }

  /// 拉取我的粉丝列表 (cmd=get_user_fans_list)。
  /// 对齐 playercenterv2fanctrl.lua:63：仅传 uin。响应 `{result,fans_list:[{uin}]}`。
  Future<Map<String, Object?>> queryFansList() async {
    final params = <String, String>{
      'uin': '$uin',
    };
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      params: params,
      cmd: 'get_user_fans_list',
    );
    return _get(url);
  }

  /// 拉取我关注的人列表 (cmd=get_user_attention_list)。
  /// 对齐 playercenterv2focusctrl.lua:157：仅传 uin。响应
  /// `{result,attention_list:[{uin}]}`。
  Future<Map<String, Object?>> queryAttentionList() async {
    final params = <String, String>{
      'uin': '$uin',
    };
    final url = buildFriendRequestUrl(
      server: _gw.resolve('HttpFriend'),
      path: kFriendPath,
      params: params,
      cmd: 'get_user_attention_list',
    );
    return _get(url);
  }

  // ── 好友设置服务端同步（对齐 friendservice.lua / newfriendservice.lua）────
  //
  // 说明：下面多数 cmd 的真实客户端参数集为
  //   apiid / cmd / des_uin / flag / s2t / src_uin / time / token / uin / ver
  // 签名规则见 CreateFriendRequest（friendservice.lua:962-1040）：参数按 key
  // 排序，非 notAuth 参数拼 `k=v` 后追加房间密钥做 md5。

  /// 通用带签名 GET（[params] 为业务参数，cmd 由本方法补）。
  Future<Map<String, Object?>> _call(
    String cmd,
    Map<String, String> params, {
    Set<String>? notAuthKeys,
  }) =>
      _get(
        buildFriendRequestUrl(
          server: _gw.resolve('HttpFriend'),
          path: kFriendPath,
          cmd: cmd,
          params: params,
          notAuthKeys: notAuthKeys,
        ),
      );

  /// 通用带签名 POST（JSON body，如 batch_* 系列）。
  Future<Map<String, Object?>> _callPost(
    String cmd,
    Map<String, String> params,
    String jsonBody, {
    Set<String>? notAuthKeys,
  }) =>
      _gw.post(
        buildFriendRequestUrl(
          server: _gw.resolve('HttpFriend'),
          path: kFriendPath,
          cmd: cmd,
          params: params,
          notAuthKeys: notAuthKeys,
        ),
        data: jsonBody,
        contentType: 'application/json',
      );

  /// 好友置顶/取消置顶 (cmd=set_sort_flag)。[flag]=1 置顶。
  /// 对齐 friendservice.lua ReqFriendTop (7425)。
  Future<Map<String, Object?>> setSortFlag(Object desUin, {required bool top}) =>
      _call('set_sort_flag', {
        'apiid': apiId,
        'des_uin': '$desUin',
        'flag': top ? '1' : '0',
        ..._signed(),
      });

  /// 设置单个好友的上线提醒 (cmd=set_online_notify_flag)。[flag]=1 开启。
  /// 对齐 friendservice.lua ReqSetFriendOnlineNotifyFlag (7530)。
  Future<Map<String, Object?>> setOnlineNotifyFlag(
    Object desUin, {
    required bool on,
  }) =>
      _call('set_online_notify_flag', {
        'apiid': apiId,
        'des_uin': '$desUin',
        'flag': on ? '1' : '0',
        ..._signed(),
      });

  /// 批量设置上线提醒 (cmd=batch_set_online_notify_flag)。
  /// 对齐 friendservice.lua ReqSetFriendOnlineNotifyFlagBatch (7563)：
  /// query 带 flag/签名，body 为 `{"des_uin_list":[...]}`（POST JSON）。
  Future<Map<String, Object?>> batchSetOnlineNotifyFlag(
    List<int> uins, {
    required bool on,
  }) =>
      _callPost(
        'batch_set_online_notify_flag',
        {
          'apiid': apiId,
          'flag': on ? '1' : '0',
          ..._signed(),
        },
        jsonEncode({'des_uin_list': uins}),
      );

  /// 修改好友备注 (cmd=set_note)。[note] 为空表示清除备注。
  /// 对齐 friendservice.lua ReqModifyFriendNote (7628)。
  Future<Map<String, Object?>> setNote(Object desUin, String note) =>
      _call('set_note', {
        'apiid': apiId,
        'des_uin': '$desUin',
        'note': note,
        ..._signed(),
      });

  /// 查询"拒绝陌生人加好友"开关 (cmd=get_closeapply_flag)。
  /// 对齐 friendservice.lua ReqGetFriendApply (7711)：country/lang 为 notAuth。
  Future<Map<String, Object?>> getCloseapplyFlag() => _call(
    'get_closeapply_flag',
    {'apiid': apiId, 'country': country, 'lang': lang, ..._signed()},
    notAuthKeys: {'country', 'lang'},
  );

  /// 设置"拒绝陌生人加好友"开关 (cmd=set_closeapply_flag)。[flag]=1 开启。
  /// 对齐 friendservice.lua ReqSetFriendApply (7734)：country/lang 为 notAuth。
  Future<Map<String, Object?>> setCloseapplyFlag({required bool on}) => _call(
    'set_closeapply_flag',
    {
      'apiid': apiId,
      'country': country,
      'flag': on ? '1' : '0',
      'lang': lang,
      ..._signed(),
    },
    notAuthKeys: {'country', 'lang'},
  );

  /// 一键拒绝全部好友申请 (cmd=reject_apply_all)。
  /// 对齐 friendservice.lua ReqRejectAllAddFriend (2504)：无 s2t/token。
  Future<Map<String, Object?>> rejectApplyAll() => _call('reject_apply_all', {
    'pushchannel': pushChannel,
    'src_uin': '$uin',
    'game_session_id': gameSessionId,
    'cid': cid,
  });

  /// 拍一拍 (cmd=take_pat)。对齐 friendservice.lua ReqSendPat (2935)：
  /// 仅 cmd/des_uin/s2t/time/token/uin（无 apiid/ver/src_uin）。
  Future<Map<String, Object?>> takePat(Object desUin) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    return _call('take_pat', {
      'des_uin': '$desUin',
      's2t': s2t,
      'time': '$now',
      'token': token,
      'uin': '$uin',
    });
  }

  /// 附近的人 (cmd=get_nearby)。[page] 从 1 起。
  /// 对齐 friendservice.lua ReqNearbyFriends (1283) / nearbyfriendserver.lua:33。
  Future<Map<String, Object?>> getNearby({
    required int page,
    required double latitude,
    required double longitude,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    return _call('get_nearby', {
      'cur_page': '$page',
      'latitude': '$latitude',
      'longitude': '$longitude',
      'uin': '$uin',
      's2t': s2t,
      'time': '$now',
      'token': token,
    });
  }

  /// 上报定位 (cmd=report_location)。对齐 nearbyfriendserver.lua:201。
  Future<Map<String, Object?>> reportLocation({
    required double latitude,
    required double longitude,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    return _call('report_location', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'uin': '$uin',
      's2t': s2t,
      'time': '$now',
      'token': token,
    });
  }

  /// 是否允许附近的人加我 (cmd=allow_add_by_nearby)。对齐 nearbyfriendserver.lua:238。
  Future<Map<String, Object?>> allowAddByNearby({required bool allow}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    return _call('allow_add_by_nearby', {
      'flag': allow ? '1' : '0',
      'uin': '$uin',
      's2t': s2t,
      'time': '$now',
      'token': token,
    });
  }

  /// 查询"是否允许附近的人加我" (cmd=get_add_by_nearby_flag)。
  /// 对齐 nearbyfriendserver.lua:217。
  Future<Map<String, Object?>> getAddByNearbyFlag() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5Token(now, s2, uin);
    return _call('get_add_by_nearby_flag', {
      'uin': '$uin',
      's2t': s2t,
      'time': '$now',
      'token': token,
    });
  }

  // ── 好友标签 / 分组（对齐 newfriendservice.lua:597-760）──────────────────
  //
  // 标签文案在协议里是 base64 编码（EncodeFriendLabel/DecodeFriendLabel）；
  // 标签池 query_friend_label_pool → {result:0, label_list:[{tag_id,label,uin_list}]}。

  /// 查询标签池 (cmd=query_friend_label_pool)。
  ///
  /// **不能带 `src_uin`。** 2026-10-02 真实账号实测（同一链路先用
  /// `query_friend_list` 做阳性对照，3/3 成功；每个形状重复 3 次、间隔 2.5s
  /// 以避开网关按账号排队）：
  /// - 带 `src_uin`（原形状）→ `{"result":2}`，稳定复现；
  /// - 去掉 `src_uin` → `{"result":0,"label_list":{…}}`，拿到真实负载；
  /// - 补 `country`/`lang`/`encrypt_ver`/`op_type`/`tag_id`、或改走 POST，
  ///   都不改变 result=2；而把命令名拼错（get_friend_label_pool 等）返回的是
  ///   **空 body**。
  ///
  /// 另一个坑：`{"result":2}` 里的 2 是**好友服务自己的**业务码，不是网关的
  /// UNKNOW_SERVICE（网关码表在 `errorcode.lua`，只有 `code`/`ret` 适用）。
  Future<Map<String, Object?>> queryFriendLabelPool() => _call(
    'query_friend_label_pool',
    {'apiid': apiId, ..._signed(includeSrcUin: false)},
  );

  /// 新增/删除标签池中的标签 (cmd=set_friend_label_pool)。
  /// [opType]=1 新增（需 [label]）；[opType]=0 删除（需 [tagId]）。
  ///
  /// 两道门都是实测出来的（2026-10-02 真实账号，自己的标签池）：
  ///
  /// 1. **不能带 `src_uin`**（同 [queryFriendLabelPool]）：带上删除回
  ///    `{"result":2}`，去掉换成业务码 45（不存在的 tag_id）。
  /// 2. **`label` 的 base64 不能带 `=` 补位**：同一个标签名，带补位回
  ///    `{"result":2}`，去掉补位回 `{"result":0,"tag_id":…}`；传明文回 47。
  ///    补 country/lang、换参数名 `tag_label`、加 src_uin 都无效。
  ///    [encodeFriendLabel] 已负责去补位，所以调用方不用管。
  Future<Map<String, Object?>> setFriendLabelPool({
    required int opType,
    String? label,
    int? tagId,
  }) {
    final params = <String, String>{
      'apiid': apiId,
      'op_type': opType == 1 ? '1' : '0',
      ..._signed(includeSrcUin: false),
    };
    if (opType == 1) {
      // 走 models/friend_tag.dart 的口径：base64 **不带 `=` 补位**。
      // 带补位服务端直接回 {"result":2}（实测：同一个标签名 probe 带补位失败、
      // 去补位成功）。这里以前自己 inline 了一次 base64Encode，漏掉了这个口径。
      params['label'] = encodeFriendLabel(label ?? '');
    } else if (tagId != null) {
      params['tag_id'] = '$tagId';
    }
    return _call('set_friend_label_pool', params);
  }

  /// 批量给好友打/去标签 (cmd=batch_set_friend_label)。
  /// [opType]=1 打标签（需 [tagId]）/ 0 去标签。body `{"des_uin_list":[...]}`。
  Future<Map<String, Object?>> batchSetFriendLabel(
    List<int> uins, {
    required int opType,
    int? tagId,
  }) {
    final params = <String, String>{
      'apiid': apiId,
      'op_type': opType == 1 ? '1' : '0',
      'src_uin': '$uin',
      ..._signed(),
    };
    if (tagId != null) params['tag_id'] = '$tagId';
    return _callPost(
      'batch_set_friend_label',
      params,
      jsonEncode({'des_uin_list': uins}),
    );
  }

  /// 批量清除好友标签 (cmd=batch_clear_friend_labels)。
  Future<Map<String, Object?>> batchClearFriendLabels(List<int> uins) =>
      _callPost(
        'batch_clear_friend_labels',
        {'apiid': apiId, 'src_uin': '$uin', ..._signed()},
        jsonEncode({'des_uin_list': uins}),
      );

  /// 好友设置类 cmd 的公共签名参数（s2t/src_uin/time/token/uin/ver）。
  /// 通用签名参数。
  ///
  /// [includeSrcUin] 默认带 `src_uin`；少数 cmd 带上它反而被服务端拒
  /// （见 [queryFriendLabelPool]），由调用方显式关掉。
  Map<String, String> _signed({bool includeSrcUin = true}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      's2t': s2t,
      if (includeSrcUin) 'src_uin': '$uin',
      'time': '$now',
      'token': md5Token(now, s2, uin),
      'uin': '$uin',
      'ver': ver,
    };
  }
}
