/// 称号配置 / 运行时客户端。
///
/// 配置（名称 + 分类）来自远程 visual-cfg `title_manager`：
/// 反编译 `getLuaConfigFileInfo`（globaldata.lua:557）：
///   `{g_http_root}miniw/ma/{name}{debug}.lua`；
/// visual-cfg 用 **md5 文件名**，md5 来自 `configIndex.lua`（`CfgDownloadMgr` 的
/// `configIndex` 配置，`cfgdownloadmgr.lua:272`）。因此称号名称需两步：
///   ① GET `miniw/ma/configIndex.lua` → 取 `title_manager` 的 md5；
///   ② GET `miniw/ma/<md5>.lua` → 解析 `title_list`（ID→名称+sort）与
///      `title_typeList`（分类 id/name/sort）。
///
/// 已拥有称号 + 有效期来自**独立端点** `/miniw/title`（`CommonTitleService`）：
///   - `get_title_showdata`（`commontitleservice.lua:18-38`）→
///     `{owned:[{ID,StartTime,ExpireTime,Custom}], expired:[...], use_title}`；
///   - `wear_title` / `take_off_title`（`commontitleservice.lua:40-80`）。
/// URL 构造见 `commontitleservice.lua:169-186`（`/miniw/title?` + http_getParamMD5）。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart'
    show
        backendShequ,
        kApiId,
        kClientVersionStr,
        kDefaultBase,
        kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';
import 'config_text_cache.dart';

/// 本模块日志标签。
const String _logTag = 'Title';

/// 解析 `configIndex.lua`（`name = 'md5'`）→ { name: md5 }。
Map<String, String> parseConfigIndex(String text) {
  final out = <String, String>{};
  final re = RegExp(r"([A-Za-z_][\w]*)\s*=\s*'([0-9a-fA-F]{16})'");
  for (final m in re.allMatches(text)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

/// 一条称号配置（`title_manager.title_list` 项）。
class TitleConfigEntry {
  /// 称号 ID。
  final int id;

  /// 称号名称。
  final String name;

  /// 分类标识（`sort`）。页签按 `title_typeList[].id` 过滤 `sort == id`
  /// （`commontitleconfig.lua:70-83`、`playercenterv2headeditorctrl.lua:1748-1760`）。
  final int sort;

  const TitleConfigEntry({
    required this.id,
    required this.name,
    required this.sort,
  });
}

/// 称号分类页签（`title_manager.title_typeList` 项）。
///
/// `id` 是页签的 groupType（过滤 `title.sort == id`）；`sort` 仅用于页签排序。
class TitleType {
  final int id;
  final String name;
  final int sort;

  const TitleType({required this.id, required this.name, required this.sort});
}

/// 称号配置目录（逐条名称/sort + 分类列表）。
class TitleCatalog {
  /// ID → 配置条目。
  final Map<int, TitleConfigEntry> entries;

  /// 分类页签（未排序；用 [sortedTypes] 取排序后）。
  final List<TitleType> types;

  const TitleCatalog({this.entries = const {}, this.types = const []});

  /// 空目录（配置拉取失败时降级）。
  static const TitleCatalog empty = TitleCatalog();

  /// ID → 名称。
  Map<int, String> get names => {
    for (final e in entries.entries) e.key: e.value.name,
  };

  /// 按 `sort` 升序的分类页签。
  List<TitleType> get sortedTypes =>
      [...types]..sort((a, b) => a.sort.compareTo(b.sort));
}

/// 提取 `key = { ... }` 的最外层 `{...}` 块（支持嵌套大括号）。
String? _extractBlock(String text, String key) {
  final i = text.indexOf(key);
  if (i < 0) return null;
  final open = text.indexOf('{', i);
  if (open < 0) return null;
  var depth = 0;
  for (var j = open; j < text.length; j++) {
    final c = text[j];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return text.substring(open, j + 1);
    }
  }
  return null;
}

/// 解析 `title_manager` 配置的 `title_list` → { ID: TitleConfigEntry }。
///
/// 用「最内层 {} 块」逐个提取 ID/Name/sort，兼容字段顺序与单双引号。
/// 注意：`title_typeList` 项用小写 `id`/`name`，不会误入本解析（只认大写 `ID`）。
Map<int, TitleConfigEntry> parseTitleEntries(String text) {
  final out = <int, TitleConfigEntry>{};
  for (final m in RegExp(r'\{([^{}]*)\}').allMatches(text)) {
    final body = m.group(1)!;
    final idM = RegExp(r'\bID\s*=\s*(\d+)').firstMatch(body);
    final nameM = RegExp(
      r"""\bName\s*=\s*['"]([^'"]*)['"]""",
    ).firstMatch(body);
    if (idM == null || nameM == null) continue;
    final sortM = RegExp(r'\bsort\s*=\s*(\d+)').firstMatch(body);
    final id = int.parse(idM.group(1)!);
    out[id] = TitleConfigEntry(
      id: id,
      name: nameM.group(1)!,
      sort: sortM != null ? int.parse(sortM.group(1)!) : 0,
    );
  }
  return out;
}

/// 解析 `title_manager` 配置的 `title_typeList` → 分类列表。
List<TitleType> parseTitleTypes(String text) {
  final out = <TitleType>[];
  final block = _extractBlock(text, 'title_typeList');
  if (block == null) return out;
  for (final m in RegExp(r'\{([^{}]*)\}').allMatches(block)) {
    final body = m.group(1)!;
    final idM = RegExp(r'\bid\s*=\s*(\d+)').firstMatch(body);
    final nameM = RegExp(
      r"""\bname\s*=\s*['"]([^'"]*)['"]""",
    ).firstMatch(body);
    if (idM == null || nameM == null) continue;
    final sortM = RegExp(r'\bsort\s*=\s*(\d+)').firstMatch(body);
    out.add(
      TitleType(
        id: int.parse(idM.group(1)!),
        name: nameM.group(1)!,
        sort: sortM != null ? int.parse(sortM.group(1)!) : 0,
      ),
    );
  }
  return out;
}

/// 解析 `title_manager` 配置的 `title_list` → { ID: Name }（向后兼容）。
Map<int, String> parseTitleNames(String text) => {
  for (final e in parseTitleEntries(text).entries) e.key: e.value.name,
};

/// 称号配置客户端（进程内缓存 [TitleCatalog]）。
class TitleConfigClient {
  final Dio _dio;
  final String baseUrl;

  TitleConfigClient({Dio? dio, String? baseUrl})
    : _dio = dio ?? createDio(),
      baseUrl = baseUrl ?? (kIsWeb ? backendShequ() : kDefaultBase);

  /// 进程内缓存目录。
  static TitleCatalog? _cache;

  String _base() => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String> _getText(String url) async {
    // 同 PartnerClient：配置名带 md5 → 可永久缓存；先本地、未命中才请求并回写。
    final cached = await ConfigTextCache.instance.get(url);
    if (cached != null) return cached;
    final resp = await _dio.get(url);
    final d = resp.data;
    final text = d is String ? d : '$d';
    await ConfigTextCache.instance.put(url, text);
    return text;
  }

  /// 拉取并解析目录（缓存）。失败返回空目录（不缓存失败结果）。
  Future<TitleCatalog> catalog() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final index = parseConfigIndex(
        await _getText('${_base()}/miniw/ma/configIndex.lua'),
      );
      final md5 = index['title_manager'];
      if (md5 == null) return TitleCatalog.empty;
      final cfg = await _getText('${_base()}/miniw/ma/$md5.lua');
      return _cache = TitleCatalog(
        entries: parseTitleEntries(cfg),
        types: parseTitleTypes(cfg),
      );
    } catch (_) {
      return TitleCatalog.empty;
    }
  }

  /// 称号 id → 名称；无则 null。
  Future<String?> titleName(int titleId) async {
    if (titleId <= 0) return null;
    final names = (await catalog()).names;
    final name = names[titleId];
    return (name == null || name.isEmpty) ? null : name;
  }
}

/// 一条已拥有 / 已过期称号（`get_title_showdata` 的 `owned` / `expired` 项）。
class OwnedTitle {
  final int id;

  /// 生效时间（epoch 秒；>1e11 视为毫秒）。
  final int startTime;

  /// 到期时间（epoch 秒；<=0 = 永久）。
  final int expireTime;

  /// `Custom == 1` → 自定义称号。
  final bool custom;

  /// 是否已过期（来自 `expired` 列表）。
  final bool expired;

  const OwnedTitle({
    required this.id,
    this.startTime = 0,
    this.expireTime = -1,
    this.custom = false,
    this.expired = false,
  });

  /// 到期文案：`永久` 或 `YYYY.MM.DD`。
  String get expireLabel =>
      expireTime <= 0 ? '永久' : formatTitleDate(expireTime);

  /// 有效期区间 `起始--永久/到期`（对齐官方 `startStr .. "--" .. endStr`）。
  String get validRange {
    final start = startTime <= 0 ? '—' : formatTitleDate(startTime);
    return '$start--$expireLabel';
  }
}

/// epoch（秒或毫秒）→ `YYYY.MM.DD`（对齐官方 `os.date("%Y.%m.%d")`）。
String formatTitleDate(int epoch) {
  var secs = epoch;
  if (secs > 100000000000) secs ~/= 1000; // 毫秒 → 秒
  final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y.$m.$d';
}

int _titleInt(Object? v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

/// `get_title_showdata` 响应（owned / expired / use_title）。
class TitleShowData {
  final List<OwnedTitle> owned;
  final List<OwnedTitle> expired;

  /// 当前佩戴称号 ID；null = 未佩戴。
  final int? useTitleId;

  const TitleShowData({
    this.owned = const [],
    this.expired = const [],
    this.useTitleId,
  });

  /// 全部称号（已拥有在前，已过期在后）。
  List<OwnedTitle> get all => [...owned, ...expired];

  /// 解析 `data`（`{owned:[...], expired:[...], use_title:{ID}}`）。
  static TitleShowData parse(Map<String, Object?> data) {
    List<OwnedTitle> list(Object? v, {required bool expired}) {
      final out = <OwnedTitle>[];
      if (v is! List) return out;
      for (final e in v) {
        if (e is! Map) continue;
        final m = e.cast<String, Object?>();
        final id = _titleInt(m['ID'] ?? m['id']);
        if (id <= 0) continue;
        final custom = m['Custom'] ?? m['custom'];
        out.add(
          OwnedTitle(
            id: id,
            startTime: _titleInt(m['StartTime'] ?? m['start_time']),
            expireTime: _titleInt(
              m['ExpireTime'] ?? m['expire_time'],
              fallback: -1,
            ),
            custom: custom == 1 || custom == true,
            expired: expired,
          ),
        );
      }
      return out;
    }

    final use = data['use_title'];
    var useId = 0;
    if (use is Map) useId = _titleInt(use['ID'] ?? use['id']);
    return TitleShowData(
      owned: list(data['owned'], expired: false),
      expired: list(data['expired'], expired: true),
      useTitleId: useId > 0 ? useId : null,
    );
  }
}

/// 称号运行时客户端 —— `/miniw/title`（`commontitleservice.lua:169-186`）。
///
/// 签名与 family / personal_center 一致（http_getParamMD5）；响应信封
/// `{ret:0, data:{...}}`（`commontitleservice.lua:23-29`）。
class TitleClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  TitleClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
  }) : _dio = dio ?? createDio(),
       baseUrl =
           baseUrl ??
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
    final md5 = httpGetParamMd5(
      all,
      timeVal: now,
      s2: s2,
      s2t: s2t,
      key: httpGetParamKey,
    );
    final parts = <String>[
      ...all.entries.map(
        (e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}',
      ),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    return '$base/miniw/title?${parts.join('&')}&md5=$md5';
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

  /// 已拥有 / 已过期称号 + 当前佩戴（`get_title_showdata`）。
  Future<TitleShowData> getOwnedTitles() async {
    final ret = await _get(_url('get_title_showdata'), 'get_title_showdata');
    final code = ret['ret'] ?? ret['code'];
    if (code is num && code != 0) return const TitleShowData();
    final data = ret['data'];
    return data is Map
        ? TitleShowData.parse(data.cast<String, Object?>())
        : const TitleShowData();
  }

  /// 佩戴称号（`wear_title`，参数 `title_id`）。
  Future<bool> wearTitle(int titleId) async {
    final ret = await _get(
      _url('wear_title', {'title_id': '$titleId'}),
      'wear_title',
    );
    final code = ret['ret'] ?? ret['code'];
    return code is num && code == 0;
  }

  /// 取下称号（`take_off_title`，参数 `title_id`）。
  Future<bool> takeOffTitle(int titleId) async {
    final ret = await _get(
      _url('take_off_title', {'title_id': '$titleId'}),
      'take_off_title',
    );
    final code = ret['ret'] ?? ret['code'];
    return code is num && code == 0;
  }
}
