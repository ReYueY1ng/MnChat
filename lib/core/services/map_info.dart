/// 地图信息客户端 —— `/miniw/map` 的 `act=get_map_list_info`。
///
/// 用途：消息中心「作品互动」卡片的作品名 —— 游戏把通知里 `data.map_id`
/// 的 owid 批量查名后填进卡片文案（`ReqMapInfo`，
/// mapservice.lua:5193-5290 → `InteractiveMsgDataMgr:MergeMapsinfo` /
/// `GetMapinfo`，interactivemsgdatamgr.lua:358-372）。
///
/// 实测（2026-10-05，心跳签名）：多个 owid 用 `-` 连接
/// （mapservice.lua:5239-5244 的 `owids_str` 拼法），用 `,` 连接查不到任何
/// 东西；响应以**纯数字 owid** 为键，名称在 `[owid].select.name`；
/// 全部查不到时只回 `{"urls": [...]}`。
library;

import 'package:dio/dio.dart';

import '../net/config.dart' show kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';
import 'gateway.dart' show buildMiniwParamMd5Url;
import 'request_errors.dart' show reportIfFailed;

/// 本模块日志标签。
const String _logTag = 'MapInfo';

/// 地图信息路径（带尾斜杠：实测形态）。
const String kMapInfoPath = 'miniw/map/';

/// 多个 owid 的连接符（mapservice.lua:5239-5244）。
const String kMapIdSeparator = '-';

/// 纯解析：`get_map_list_info` 响应 → {owid: 名称}。
///
/// 响应形如 `{"66241560236659": {"select": {"name": "一个幸运方块生存"}}}`；
/// 非 Map 条目（例如只有 `urls`）、缺 `name` 的条目一律跳过，绝不抛异常。
Map<String, String> parseMapNames(Object? decoded) {
  if (decoded is! Map) return const <String, String>{};
  final out = <String, String>{};
  for (final e in decoded.entries) {
    final v = e.value;
    if (v is! Map) continue;
    final vm = v.cast<String, Object?>();
    final select = vm['select'];
    final name = (select is Map
            ? select.cast<String, Object?>()['name']
            : vm['name'])
        ?.toString() ??
        '';
    if (name.isEmpty) continue;
    out['${e.key}'] = name;
  }
  return out;
}

/// 地图信息客户端（未登录时由 provider 返回 null）。
class MapInfoClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  MapInfoClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
  })  : _dio = dio ?? createDio(),
        baseUrl = baseUrl ?? (kDefaultUrls['HttpCommon'] ?? kDefaultBase);

  /// 批量查作品名。空入参 → 空 map；传输/解析异常由调用方兜（UI 退化为不显示作品名）。
  Future<Map<String, String>> fetchMapNames(List<String> owids) async {
    final ids = <String>[
      for (final id in owids)
        if (id.isNotEmpty) id,
    ];
    if (ids.isEmpty) return const <String, String>{};
    final url = buildMiniwParamMd5Url(
      baseUrl: baseUrl,
      path: '/$kMapInfoPath',
      params: {
        'act': 'get_map_list_info',
        'fn_list': ids.join(kMapIdSeparator),
      },
      uin: uin,
      s2: s2,
      s2t: s2t,
    );
    log.debug('get_map_list_info：${ids.length} 个 owid（已脱敏）', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    reportIfFailed(url, decoded);
    return parseMapNames(decoded);
  }
}
