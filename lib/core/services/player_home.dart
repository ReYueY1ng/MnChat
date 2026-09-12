/// 玩家主页客户端 —— /miniw/personal_center（主页信息）与 /miniw/posting（关系）。
///
/// 移植自反编译源码 playercenterv2homepageservice.lua：
///   - get_user_homepage(uin, target, module_list)：主页各模块数据
///   - add_visit_record(uin, target, prize)：访问（+送礼物）
///   - query_target_relation(op_uin, target_list)：查询关注/粉丝关系
/// 签名用 http_getParamMD5（与 dynamics 相同）。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart'
    show backendShequ, kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;

/// 主页模块 id（对齐 playerCenterV2Config.moduleList）。
class PlayerHomeModule {
  static const int roleInfo = 1;
  static const int avatar = 2;
  static const int posting = 3; // 动态
  static const int skin = 4;
  static const int avatarCollect = 5;
  static const int achieve = 6;
  static const int headFrame = 7;
  static const int charm = 8; // 魅力
  static const int title = 9; // 称号
  static const int enjoyMatch = 10;
  static const int map = 11;
  static const int partner = 12; // 好友关系/搭档
  static const int achieve2 = 13;
  static const int socialSign = 16; // 交友标签
  static const int family = 17; // 家族
  static const int favoriteFolder = 18;
  static const int multimedia = 19;

  /// 默认请求的核心模块（逗号分隔字符串）。
  static const String defaultList = '1,2,3,8,9,16,17,12';
}

/// 玩家主页客户端。
class PlayerHomeClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  PlayerHomeClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
  })  : _dio = dio ?? createDio(),
        baseUrl = baseUrl ??
            (kIsWeb ? backendShequ() : (kDefaultUrls['HttpCommon'] ?? kDefaultBase));

  /// 通用签名 URL（可指定相对路径）。
  String _url(String path, String act, [Map<String, String> params = const {}]) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final all = <String, String>{
      'act': act,
      'uin': '$uin',
      'apiid': kApiId,
      'ver': kClientVersionStr,
      'country': 'CN',
      'lang': '0',
      ...params,
    };
    final md5 = httpGetParamMd5(all,
        timeVal: now, s2: s2, s2t: s2t, key: httpGetParamKey);
    final parts = <String>[
      ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    return '$base/$path?${parts.join('&')}&md5=$md5';
  }

  Future<Map<String, Object?>> _get(String url) async {
    debugPrint('[PlayerHome] url: $url');
    final resp = await _dio.get(url);
    final raw = resp.data;
    debugPrint('[PlayerHome] RAW: $raw');
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// 拉取玩家主页数据（act=get_user_homepage，路径 personal_center）。
  /// [moduleList] 逗号分隔的模块 id。返回完整 data map。
  Future<Map<String, Object?>> getUserHomepage(
    int targetUin, {
    String moduleList = PlayerHomeModule.defaultList,
  }) async {
    final url = _url('miniw/personal_center', 'get_user_homepage', {
      'target': '$targetUin',
      'module_list': moduleList,
    });
    final ret = await _get(url);
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return {};
    }
    final data = ret['data'];
    if (data is Map) return data.cast<String, Object?>();
    return {};
  }

  /// 访问主页（act=add_visit_record）。[prize]=1 附带送花等。
  Future<bool> addVisitRecord(int targetUin, {int prize = 0}) async {
    final url = _url('miniw/personal_center', 'add_visit_record', {
      'target': '$targetUin',
      'prize': '$prize',
    });
    final ret = await _get(url);
    return (ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) == 0;
  }

  /// 查询与目标玩家的关注/粉丝关系（act=query_target_relation，路径 posting）。
  /// 返回 data（key=uin 字符串 → 关系掩码字符串）。
  Future<Map<String, String>> queryTargetRelation(
      int opUin, List<int> targets) async {
    if (targets.isEmpty) return {};
    final url = _url('miniw/posting', 'query_target_relation', {
      'op_uin': '$opUin',
      'target_list': targets.join(','),
    });
    final ret = await _get(url);
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return {};
    }
    final data = ret['data'];
    final out = <String, String>{};
    if (data is Map) {
      for (final e in data.entries) {
        out['${e.key}'] = '${e.value}';
      }
    }
    return out;
  }
}
