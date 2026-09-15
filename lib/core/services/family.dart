/// 家族(家庭/Family)服务客户端 —— /miniw/family 接口。
/// 移植自反编译源码 familyservice.lua (getUrl 用 act + http_getParamMD5 签名)。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart' show backendShequ, kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';

/// 本模块日志标签。
const String _logTag = 'Family';

const String kCountry = 'CN';
const String kLang = '0';

const String kFamilyPath = 'miniw/family';

/// 家族成员。
class FamilyMember {
  final int uin;
  final String nickname;
  final String? avatar;
  final int identity; // 1=族长(leader)
  final bool online;

  const FamilyMember({
    required this.uin,
    required this.nickname,
    this.avatar,
    this.identity = 0,
    this.online = false,
  });

  bool get isLeader => identity == 1;

  static FamilyMember fromJson(Map<String, Object?> m) => FamilyMember(
        uin: (m['uin'] ?? m['Uin'] ?? 0) is num
            ? ((m['uin'] ?? m['Uin'] ?? 0) as num).toInt()
            : int.tryParse('${m['uin'] ?? m['Uin'] ?? 0}') ?? 0,
        nickname: m['NickName']?.toString() ?? m['nickname']?.toString() ?? '',
        avatar: m['header']?.toString() ?? m['avatar']?.toString(),
        identity: (m['identity'] as num?)?.toInt() ?? 0,
        online: m['online'] == 1 || m['online'] == true,
      );
}

/// 家族信息。
class FamilyInfo {
  final int familyId;
  final String name;
  final int leaderUin;
  final String? icon;
  final String? notice;
  final List<FamilyMember> members;
  final int memberCount;

  const FamilyInfo({
    required this.familyId,
    required this.name,
    this.leaderUin = 0,
    this.icon,
    this.notice,
    this.members = const [],
    this.memberCount = 0,
  });

  static FamilyInfo? fromJson(Map<String, Object?> m) {
    final fid = (m['family_id'] ?? m['familyId'] ?? m['id'] ?? 0);
    if (fid is! num || fid.toInt() == 0) return null;
    final members = <FamilyMember>[];
    final ml = m['members'];
    if (ml is List) {
      for (final e in ml) {
        if (e is Map) members.add(FamilyMember.fromJson(e.cast<String, Object?>()));
      }
    }
    int leader = 0;
    for (final mem in members) {
      if (mem.isLeader) {
        leader = mem.uin;
        break;
      }
    }
    if (leader == 0) {
      // 注意：`?? 0` 必须保留在强转表达式内，否则字段全缺时会把 null 当成
      // num 强转（脏响应直接抛异常，见 family_list_parse_test）。
      leader = (m['leader_uin'] ?? m['owner'] ?? 0) is num
          ? ((m['leader_uin'] ?? m['owner'] ?? 0) as num).toInt()
          : 0;
    }
    return FamilyInfo(
      familyId: fid.toInt(),
      name: m['family_name']?.toString() ?? m['name']?.toString() ?? '家族',
      leaderUin: leader,
      icon: m['icon']?.toString() ?? m['head_url']?.toString(),
      notice: m['notice']?.toString(),
      members: members,
      memberCount: (m['member_count'] as num?)?.toInt() ?? members.length,
    );
  }
}

/// 解析 `get_family_list` 响应，返回我加入的全部家族（按响应顺序去重）。
///
/// 兼容官方响应的多种信封：顶层即家族 / `{family:{...}}` /
/// `{families:[...]}` / `{data:[...]}` / `{data:{...}}`（与
/// `ui/family_page.dart` 的取值口径一致）。脏数据（非 Map / 缺 family_id）
/// 直接跳过，解析不出时返回空列表，绝不抛异常。
List<FamilyInfo> parseFamilyList(Map<String, Object?> resp) {
  final out = <FamilyInfo>[];
  final seen = <int>{};
  void collect(Object? node) {
    if (node is! Map) return;
    final m = node.cast<String, Object?>();
    final self = FamilyInfo.fromJson(m);
    if (self != null) {
      if (seen.add(self.familyId)) out.add(self);
      return;
    }
    for (final key in const ['family', 'families', 'data']) {
      final inner = m[key];
      if (inner is List) {
        for (final e in inner) {
          collect(e);
        }
      } else if (inner is Map) {
        collect(inner);
      }
    }
  }

  collect(resp);
  return out;
}

/// 当前展示家族（`get_show_family` 响应 / 主页 `family` 模块 `data`）。
class FamilyShowInfo {
  final int familyId;
  final String name;
  const FamilyShowInfo({required this.familyId, required this.name});
}

/// 解析「当前展示家族」。
///
/// 兼容信封：`{data:{family_id,name}}` / `{family:{...}}` / 顶层对象；
/// 无 `family_id`（未展示任何家族）→ null。展示家族字段 `{family_id, name,
/// leader_uin, level, hide_flag}`（`familymgr.lua:387-398`、
/// `familydata.lua:548-554`）。
FamilyShowInfo? parseShowFamily(Map<String, Object?> resp) {
  FamilyShowInfo? found;
  void collect(Object? node) {
    if (found != null || node is! Map) return;
    final m = node.cast<String, Object?>();
    final fid = m['family_id'] ?? m['familyId'] ?? m['id'];
    if (fid is num && fid.toInt() > 0) {
      found = FamilyShowInfo(
        familyId: fid.toInt(),
        name: m['family_name']?.toString() ?? m['name']?.toString() ?? '家族',
      );
      return;
    }
    for (final key in const ['data', 'family']) {
      collect(m[key]);
    }
  }

  collect(resp);
  return found;
}

/// 家族客户端。
class FamilyClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  FamilyClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
  })  : _dio = dio ?? createDio(),
        baseUrl = baseUrl ??
            (kIsWeb ? backendShequ() : (kDefaultUrls['HttpCommon'] ?? kDefaultBase));

  String _url(String act, [Map<String, String> params = const {}]) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 通用鉴权参数（url_addParams 注入，同时进 md5 与 URL）
    final all = <String, String>{
      'act': act,
      'uin': '$uin',
      'apiid': kApiId,
      'ver': kClientVersionStr,
      'country': kCountry,
      'lang': kLang,
      ...params,
    };
    final md5 = httpGetParamMd5(all, timeVal: now, s2: s2, s2t: s2t, key: httpGetParamKey);
    // 对齐 Lua http_getParamMD5：URL 需带 time/s2t/encrypt_ver（不含 s2）供服务器复算。
    final parts = <String>[
      ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    return '$base/$kFamilyPath?${parts.join('&')}&md5=$md5';
  }

  Future<Map<String, Object?>> _get(String url, String act) async {
    log.debug('$act url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('$act RAW: $raw', tag: _logTag);
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// 我加入的家族列表。
  Future<Map<String, Object?>> getFamilyList({int? target}) =>
      _get(_url('get_family_list', {if (target != null) 'target': '$target'}), 'get_family_list');

  /// 家族详情。
  Future<Map<String, Object?>> getFamilyDetail(Object familyId) =>
      _get(_url('get_family_detail', {'family_id': '$familyId'}), 'get_family_detail');

  /// 当前展示家族（act=get_show_family，参数 uin）。
  ///
  /// 对齐 `familyservice.lua:628-637` + `familydata.lua:477-494`；响应
  /// `{ret/code:0, data:{family_id,name,...}}`。
  Future<Map<String, Object?>> getShowFamily() =>
      _get(_url('get_show_family'), 'get_show_family');

  /// 切换展示家族（act=set_show_family，参数 family_id）。
  ///
  /// 对齐 `familyservice.lua:617-626` + `familydata.lua:531-546`
  /// （`playercenterv2headeditorctrl.lua:1720-1734` 的 `Btn_family_setClick`）。
  Future<Map<String, Object?>> setShowFamily(Object familyId) => _get(
    _url('set_show_family', {'family_id': '$familyId'}),
    'set_show_family',
  );

  /// 家庭接口是否成功（响应 `{ret/code:0}`，对齐 `__AsyncRequest` 的
  /// `code = ret.ret or ret.code`，`familyservice.lua:688`）。
  static bool isSuccess(Map<String, Object?> resp) {
    final code = resp['ret'] ?? resp['code'];
    return code is num && code == 0;
  }

  /// 申请加入家族。
  Future<Map<String, Object?>> applyJoin(Object familyId) =>
      _get(_url('apply_join', {'family_id': '$familyId'}), 'apply_join');

  /// 通过/拒绝入族申请 (act=accept_join)。
  /// 对齐 familyservice.lua AcceptJoin：reject=1 拒绝，nil/0 通过；
  /// clear 传 1 时通过后清空其余申请。
  Future<Map<String, Object?>> acceptJoin({
    required Object target,
    required Object familyId,
    bool reject = false,
    bool clear = false,
  }) {
    final params = <String, String>{
      'target': '$target',
      'family_id': '$familyId',
      'reject': reject ? '1' : '0',
      'clear': clear ? '1' : '0',
    };
    return _get(_url('accept_join', params), 'accept_join');
  }

  /// 邀请好友加入家族 (act=invite)。
  Future<Map<String, Object?>> invite(Object target, Object familyId) =>
      _get(_url('invite', {'target': '$target', 'family_id': '$familyId'}), 'invite');

  /// 退出家族。
  Future<Map<String, Object?>> quit(Object familyId) =>
      _get(_url('quit', {'family_id': '$familyId'}), 'quit');

  /// 转让族长。
  Future<Map<String, Object?>> transLeader(Object familyId, Object target) =>
      _get(_url('trans_leader', {'family_id': '$familyId', 'target': '$target'}), 'trans_leader');

  /// 发家族消息。
  Future<Map<String, Object?>> sendFamilyMsg(Object familyId, String msg) =>
      _get(_url('send_family_msg', {'family_id': '$familyId', 'msg': msg}), 'send_family_msg');

  /// 拉家族消息列表。
  Future<Map<String, Object?>> getFamilyMsgList(Object familyId, {int offset = 0}) =>
      _get(_url('get_family_msg_list', {'family_id': '$familyId', 'offset': '$offset'}), 'get_family_msg_list');
}
