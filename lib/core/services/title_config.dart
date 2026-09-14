/// 称号配置客户端 —— 远程 visual-cfg `title_manager`。
///
/// 反编译 `getLuaConfigFileInfo`（globaldata.lua:557）：
///   `{g_http_root}miniw/ma/{name}{debug}.lua`；
/// visual-cfg 用 **md5 文件名**，md5 来自 `configIndex.lua`（`CfgDownloadMgr` 的
/// `configIndex` 配置，`cfgdownloadmgr.lua:272`）。
///
/// 因此称号名称需两步：
///   ① GET `miniw/ma/configIndex.lua` → 取 `title_manager` 的 md5；
///   ② GET `miniw/ma/<md5>.lua` → 解析 `title_list` 的 `ID → Name`。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../net/config.dart' show backendShequ, kDefaultBase;
import '../net/http_factory.dart' show createDio;

/// 解析 `configIndex.lua`（`name = 'md5'`）→ { name: md5 }。
Map<String, String> parseConfigIndex(String text) {
  final out = <String, String>{};
  final re = RegExp(r"([A-Za-z_][\w]*)\s*=\s*'([0-9a-fA-F]{16})'");
  for (final m in re.allMatches(text)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

/// 解析 `title_manager` 配置的 `title_list` → { ID: Name }。
///
/// 用「最内层 {} 块」逐个提取 ID/Name，兼容字段顺序与单双引号。
Map<int, String> parseTitleNames(String text) {
  final out = <int, String>{};
  for (final m in RegExp(r'\{([^{}]*)\}').allMatches(text)) {
    final body = m.group(1)!;
    final idM = RegExp(r'\bID\s*=\s*(\d+)').firstMatch(body);
    final nameM = RegExp(r"""\bName\s*=\s*['"]([^'"]*)['"]""").firstMatch(body);
    if (idM != null && nameM != null) {
      out[int.parse(idM.group(1)!)] = nameM.group(1)!;
    }
  }
  return out;
}

/// 称号配置客户端（进程内缓存 title_list）。
class TitleConfigClient {
  final Dio _dio;
  final String baseUrl;

  TitleConfigClient({Dio? dio, String? baseUrl})
    : _dio = dio ?? createDio(),
      baseUrl = baseUrl ?? (kIsWeb ? backendShequ() : kDefaultBase);

  /// 进程内缓存：ID → Name。
  static Map<int, String>? _cache;

  String _base() => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String> _getText(String url) async {
    final resp = await _dio.get(url);
    final d = resp.data;
    return d is String ? d : '$d';
  }

  /// 拉取并解析 title_list（缓存）。失败返回已缓存值或空 map。
  Future<Map<int, String>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final index = parseConfigIndex(
        await _getText('${_base()}/miniw/ma/configIndex.lua'),
      );
      final md5 = index['title_manager'];
      if (md5 == null) return {};
      final cfg = await _getText('${_base()}/miniw/ma/$md5.lua');
      return _cache = parseTitleNames(cfg);
    } catch (_) {
      return {};
    }
  }

  /// 称号 id → 名称；无则 null。
  Future<String?> titleName(int titleId) async {
    if (titleId <= 0) return null;
    final names = await _load();
    final name = names[titleId];
    return (name == null || name.isEmpty) ? null : name;
  }
}
