/// 玩家资料客户端 —— /miniw/profile/ 接口。
/// 移植自 MNClient `services/http_profile.py` (getProfileBatch3)。
/// 用途：批量拉取好友昵称/头像（friend_list 只返回 {mark,uin,relation}）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../crypto/md5_sign.dart' show httpGetS1Map;
import '../net/config.dart' show backendShequ, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart';
import '../protocol/lua_table.dart' show decodeHttpResponse;

/// 资料接口路径。
const String kProfilePath = 'miniw/profile/';

/// 玩家资料批量结果。
class PlayerProfile {
  final int uin;
  final String nickname;
  final String? avatarUrl;

  const PlayerProfile({
    required this.uin,
    required this.nickname,
    this.avatarUrl,
  });

  /// 从 getProfileBatch3 响应项解析。
  /// 结构（LuaTable）: {profile: {uin, RoleInfo: {NickName, ...},
  ///        header: {url}, header2: {url}, header3: {url}}, uin}
  ///
  /// 头像字段优先级：`header3` → `header2` → `header`。取不到则返回 null，
  /// 由 UI 回退到首字母占位。
  static PlayerProfile? fromItem(Map<String, Object?> item) {
    final profile = item['profile'];
    if (profile is! Map) return null;
    final p = profile.cast<String, Object?>();

    var uin2 = _firstInt(item, ['uin', 'Uin']);
    if (uin2 == 0) uin2 = _firstInt(p, ['uin', 'Uin']);
    if (uin2 == 0) return null;

    var nickname = '';
    final ri = p['RoleInfo'];
    if (ri is Map) {
      nickname = (ri.cast<String, Object?>())['NickName']?.toString() ?? '';
    }

    final avatar = _pickAvatar(p);

    return PlayerProfile(uin: uin2, nickname: nickname, avatarUrl: avatar);
  }

  /// 按 header3 → header2 → header 顺序取头像 URL。
  static String? _pickAvatar(Map<String, Object?> p) {
    for (final key in ['header3', 'header2', 'header']) {
      final h = p[key];
      if (h is Map) {
        final url = (h.cast<String, Object?>())['url'];
        if (url != null && url.toString().isNotEmpty) return url.toString();
      }
    }
    return null;
  }

  static int _firstInt(Map<String, Object?> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }
}

class ProfileClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;
  final String ver;
  final String apiId;
  final String lang;
  final String country;

  ProfileClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
    this.ver = '1.58.0',
    this.apiId = '110',
    this.lang = '0',
    this.country = 'CN',
  })  : _dio = dio ?? createDio(),
        baseUrl = baseUrl ??
            (kIsWeb ? backendShequ() : (kDefaultUrls['HttpMap'] ?? kDefaultBase));

  /// 批量拉取玩家资料（昵称/头像）。
  ///
  /// URL 构造（Python http_profile.py:_build_url）:
  ///   {HttpMap}miniw/profile/?act=getProfileBatch3&uin={uin}&op_uin_list={uins}
  ///   &ver=..&apiid=..&lang=..&country=..&time=X&auth=MD5(time+s2+uin)&s2t=Y
  ///
  /// 注意：响应是 **LuaTable 数组**（{[1]=..,[2]=..}），非 JSON——
  /// 用 decodeHttpResponse 解析（支持 LuaTable 顶层 List）。
  Future<List<PlayerProfile>> getProfileBatch3(List<int> uins) async {
    if (uins.isEmpty) return [];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final uinList = uins.map((u) => '$u').join(',');
    final url =
        '$base/$kProfilePath?act=getProfileBatch3&uin=$uin&op_uin_list=$uinList'
        '&ver=$ver&apiid=$apiId&lang=$lang&country=$country&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);

    // LuaTable 数组 → List；{code,data:[...]} → data
    Object? data = decoded;
    if (data is Map) {
      if (data['data'] is List) data = data['data'];
    }
    if (data is! List) return [];

    final out = <PlayerProfile>[];
    for (final item in data) {
      if (item is Map) {
        final p = PlayerProfile.fromItem(item.cast<String, Object?>());
        if (p != null) out.add(p);
      }
    }
    return out;
  }

  /// 批量拉取玩家**DIY 自定义头像**（游戏内主界面头像来源）。
  ///
  /// 反编译 `headinfosysmgr.lua:ReqPlayerHeadInfo`:
  ///   `{HttpMap}miniw/profile?&act=getPersonCenterHeadInfo&op_uin_list={uins}&{sign}`
  /// 响应结构: `{code:0, data:{ "<uin>": {use_diy, diy_header:{pre_url, pass_url, aduit_fail}, ...} }}`
  /// 返回 Map&lt;uin, DIY头像URL&gt;（仅 use_diy==1 且 pass_url/pre_url 非空）。
  Future<Map<int, String?>> getPersonCenterHeadInfo(List<int> uins) async {
    final out = <int, String?>{};
    if (uins.isEmpty) return out;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final uinList = uins.map((u) => '$u').join(',');
    final url =
        '$base/miniw/profile?&act=getPersonCenterHeadInfo&op_uin_list=$uinList&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);

    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) return out;

    for (final e in data.entries) {
      final u = int.tryParse('${e.key}');
      if (u == null || e.value is! Map) continue;
      final info = (e.value as Map).cast<String, Object?>();
      // 未开启 DIY 头像则跳过
      if (info['use_diy'] != 1) continue;
      final diy = info['diy_header'];
      if (diy is! Map) continue;
      final dh = diy.cast<String, Object?>();
      // pass_url=审核通过；pre_url=审核中（默认显示 pass，fallback pre）
      final pass = dh['pass_url']?.toString();
      final pre = dh['pre_url']?.toString();
      out[u] = (pass != null && pass.isNotEmpty)
          ? pass
          : (pre != null && pre.isNotEmpty ? pre : null);
    }
    return out;
  }
}