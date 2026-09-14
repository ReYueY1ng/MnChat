/// 社交签名（交友标签）客户端 —— /miniw/personal_center。
/// 移植自反编译源码 newfriendservice.lua：
///   - get_social_sign(target) / get_social_sign_batch(uin_list)：读他人签名
///   - set_social_lab(game_lab, social_lab)：设置我的签名
/// 签名用 http_getParamMD5（与 dynamics 相同），路径 personal_center。
///
/// 签名数据 {social_lab, game_lab}（id），文本映射来自游戏动态配置
/// FriendShipDeclaration（statusTag/likeTag: [{id, tag}]）。本地内置常见
/// 标签表（对齐游戏默认配置），未知 id 回退为"标签#id"。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart'
    show backendShequ, kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';

/// 本模块日志标签。
const String _logTag = 'SocialSign';

const String kPersonalCenterPath = 'miniw/personal_center';

/// 常见社交标签（statusTag，想要…）。
const List<Map<String, Object>> kSocialTags = [
  {'id': 1, 'tag': '一起建房子'},
  {'id': 2, 'tag': '一起打BOSS'},
  {'id': 3, 'tag': '一起玩迷你币'},
  {'id': 4, 'tag': '一起跑酷'},
  {'id': 5, 'tag': '一起种田'},
  {'id': 6, 'tag': '一起做机关'},
  {'id': 7, 'tag': '一起拆家'},
  {'id': 8, 'tag': '一起做地图'},
];

/// 常见游戏标签（likeTag，喜欢玩…）。
const List<Map<String, Object>> kGameTags = [
  {'id': 1, 'tag': '生存模式'},
  {'id': 2, 'tag': '创造模式'},
  {'id': 3, 'tag': '跑酷地图'},
  {'id': 4, 'tag': '解密地图'},
  {'id': 5, 'tag': '对战地图'},
  {'id': 6, 'tag': '别墅地图'},
  {'id': 7, 'tag': '养成地图'},
  {'id': 8, 'tag': '休闲地图'},
];

/// 按 id 取标签文本；未知回退 "标签#id"。
String socialTagText(int id) {
  if (id <= 0) return '';
  for (final t in kSocialTags) {
    if (t['id'] == id) return '${t['tag']}';
  }
  return '标签#$id';
}

String gameTagText(int id) {
  if (id <= 0) return '';
  for (final t in kGameTags) {
    if (t['id'] == id) return '${t['tag']}';
  }
  return '标签#$id';
}

/// 签名展示文案："想要X，喜欢Y"。
String formatDeclaration(int socialLab, int gameLab) {
  final parts = <String>[];
  if (socialLab != 0) parts.add('想要${socialTagText(socialLab)}');
  if (gameLab != 0) parts.add('喜欢${gameTagText(gameLab)}');
  return parts.isEmpty ? '' : parts.join('，');
}

/// 社交签名客户端。
class SocialSignClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  SocialSignClient({
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
    return '$base/$kPersonalCenterPath?${parts.join('&')}&md5=$md5';
  }

  Future<Map<String, Object?>> _get(String act,
      [Map<String, String> params = const {}]) async {
    final url = _url(act, params);
    log.debug('$act url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('$act RAW: $raw', tag: _logTag);
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// 读单个 uin 的签名。返回 {social_lab, game_lab}；失败返回空。
  Future<SocialDeclaration?> getSocialSign(int targetUin) async {
    final ret = await _get('get_social_sign', {'target': '$targetUin'});
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return null;
    }
    final data = ret['data'];
    if (data is Map) {
      return SocialDeclaration.fromMap(data.cast<String, Object?>());
    }
    return null;
  }

  /// 批量读签名。返回 uin → 签名。
  Future<Map<int, SocialDeclaration>> getSocialSignBatch(List<int> uins) async {
    if (uins.isEmpty) return {};
    final ret =
        await _get('get_social_sign_batch', {'uin_list': uins.join(',')});
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return {};
    }
    final out = <int, SocialDeclaration>{};
    final data = ret['data'];
    if (data is Map) {
      for (final e in data.entries) {
        final u = int.tryParse('${e.key}');
        if (u == null || e.value is! Map) continue;
        out[u] = SocialDeclaration.fromMap(e.value.cast<String, Object?>());
      }
    }
    return out;
  }

  /// 设置我的签名。social_lab=0 或 game_lab=0 表示不设置该项。
  Future<bool> setSocialLab({required int socialLab, required int gameLab}) async {
    final ret = await _get('set_social_lab', {
      'social_lab': '$socialLab',
      'game_lab': '$gameLab',
    });
    final code = ret['code'] ?? ret['ret'];
    return code is num && code == 0;
  }
}

/// 社交签名数据。
class SocialDeclaration {
  final int socialLab;
  final int gameLab;

  const SocialDeclaration({required this.socialLab, required this.gameLab});

  bool get isEmpty => socialLab == 0 && gameLab == 0;

  String get text => formatDeclaration(socialLab, gameLab);

  static SocialDeclaration fromMap(Map<String, Object?> m) {
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return SocialDeclaration(
      socialLab: i(m['social_lab'] ?? m['socialLab']),
      gameLab: i(m['game_lab'] ?? m['gameLab']),
    );
  }
}
