/// 社交签名（交友标签）客户端 —— /miniw/personal_center。
/// 移植自反编译源码 newfriendservice.lua：
///   - get_social_sign(target) / get_social_sign_batch(uin_list)：读他人签名
///   - set_social_lab(game_lab, social_lab)：设置我的签名
/// 签名用 http_getParamMD5（与 dynamics 相同），路径 personal_center。
///
/// 签名数据 {social_lab, game_lab}（id），文本映射来自 visual-cfg
/// `FriendShipDeclaration`（statusTag/likeTag: [{id, tag}]，见
/// [DeclarationConfigClient]）；内置表 [kSocialTags]/[kGameTags] 只是拉不到
/// 配置时的兜底。
library;

import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart'
    show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import 'title_config.dart' show extractLuaBlock, parseConfigIndex;
import 'config_text_cache.dart' show ConfigTextCache;
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

/// 签名展示文案："想要X，喜欢Y"（对齐 `NewFriendMgr:GetDeclaration`，用中文顿号连接）。
///
/// 标签文案优先用服务端配置（[catalog]），拿不到才回退内置表。
String formatDeclaration(
  int socialLab,
  int gameLab, {
  DeclarationCatalog? catalog,
}) {
  final parts = <String>[];
  if (socialLab != 0) {
    parts.add('想要${catalog?.socialText(socialLab) ?? socialTagText(socialLab)}');
  }
  if (gameLab != 0) {
    parts.add('喜欢${catalog?.gameText(gameLab) ?? gameTagText(gameLab)}');
  }
  return parts.isEmpty ? '' : parts.join('，');
}

/// 交友宣言标签目录（服务端 visual-cfg `FriendShipDeclaration`）。
///
/// 标签文案**由服务端下发**（`NewFriendCfg:GetRelationConfig` →
/// `VisualCfgMgr:ReqCfg("FriendShipDeclaration")`），配置里的 `statusTag` /
/// `likeTag` 才是"想要…/喜欢…"的真实选项；内置的 [kSocialTags]/[kGameTags]
/// 只是拿不到配置时的兜底，id 与文案都可能和线上不一致。
class DeclarationCatalog {
  /// 想要…（`statusTag`）：id → 文案。
  final Map<int, String> socialTags;

  /// 喜欢…（`likeTag`）：id → 文案。
  final Map<int, String> gameTags;

  const DeclarationCatalog({
    required this.socialTags,
    required this.gameTags,
  });

  static const DeclarationCatalog empty = DeclarationCatalog(
    socialTags: <int, String>{},
    gameTags: <int, String>{},
  );

  bool get isEmpty => socialTags.isEmpty && gameTags.isEmpty;

  String socialText(int id) => socialTags[id] ?? socialTagText(id);

  String gameText(int id) => gameTags[id] ?? gameTagText(id);

  /// 选项列表（id, 文案），按 id 升序；空则回退内置表。
  List<(int, String)> get socialOptions => socialTags.isEmpty
      ? [for (final t in kSocialTags) (t['id'] as int, '${t['tag']}')]
      : (socialTags.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1)));

  List<(int, String)> get gameOptions => gameTags.isEmpty
      ? [for (final t in kGameTags) (t['id'] as int, '${t['tag']}')]
      : (gameTags.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1)));
}

/// 解析 `FriendShipDeclaration` 配置 → `(想要标签, 喜欢标签)`（id → 文案）。
///
/// 结构：`{ statusTag = { {id=1, tag='…'}, … }, likeTag = { … } }`，
/// 读法与 `NewFriendMgr:GetDeclaration`（`v.id` / `v.tag`）一致。
(Map<int, String>, Map<int, String>) parseDeclarationTags(String text) {
  Map<int, String> tags(String key) {
    final block = extractLuaBlock(text, key);
    if (block == null) return const <int, String>{};
    final out = <int, String>{};
    for (final m in RegExp(r'\{([^{}]*)\}').allMatches(block)) {
      final body = m.group(1)!;
      final idM = RegExp(r'\bid\s*=\s*(\d+)').firstMatch(body);
      final tagM = RegExp(r"""\btag\s*=\s*['\"]([^'\"]*)['\"]""").firstMatch(body);
      if (idM == null || tagM == null) continue;
      out[int.parse(idM.group(1)!)] = tagM.group(1)!;
    }
    return out;
  }

  return (tags('statusTag'), tags('likeTag'));
}

/// 交友宣言标签配置客户端（visual-cfg `FriendShipDeclaration`）。
class DeclarationConfigClient {
  final Dio _dio;
  final String baseUrl;

  DeclarationConfigClient({Dio? dio, String? baseUrl})
    : _dio = dio ?? createDio(),
      baseUrl = baseUrl ?? kDefaultBase;

  /// 进程内缓存。
  static DeclarationCatalog? _cache;

  String _base() => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String> _getText(String url) async {
    // 配置名带 md5 → 可永久缓存；先本地、未命中才请求并回写（同 TitleConfigClient）。
    final cached = await ConfigTextCache.instance.get(url);
    if (cached != null) return cached;
    final resp = await _dio.get(url);
    final d = resp.data;
    final text = d is String ? d : '$d';
    await ConfigTextCache.instance.put(url, text);
    return text;
  }

  /// 拉取并解析标签表（缓存）。失败返回空目录（不缓存失败结果）。
  Future<DeclarationCatalog> catalog() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final index = parseConfigIndex(
        await _getText('${_base()}/miniw/ma/configIndex.lua'),
      );
      final md5 = index['FriendShipDeclaration'];
      if (md5 == null) return DeclarationCatalog.empty;
      final cfg = await _getText('${_base()}/miniw/ma/$md5.lua');
      final (status, like) = parseDeclarationTags(cfg);
      final catalog = DeclarationCatalog(
        socialTags: status,
        gameTags: like,
      );
      if (catalog.isEmpty) return DeclarationCatalog.empty;
      return _cache = catalog;
    } catch (_) {
      return DeclarationCatalog.empty;
    }
  }
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
        baseUrl =
            baseUrl ?? (kDefaultUrls['HttpCommon'] ?? kDefaultBase);

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

  /// 用服务端标签目录格式化（拿得到配置时用它）。
  String textWith(DeclarationCatalog catalog) =>
      formatDeclaration(socialLab, gameLab, catalog: catalog);

  static SocialDeclaration fromMap(Map<String, Object?> m) {
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return SocialDeclaration(
      socialLab: i(m['social_lab'] ?? m['socialLab']),
      gameLab: i(m['game_lab'] ?? m['gameLab']),
    );
  }
}
