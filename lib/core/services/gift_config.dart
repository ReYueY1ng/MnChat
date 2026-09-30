/// 礼物配置客户端 —— visual-cfg `new_give_gift_config`（目录）+ `items`（道具名/图标）。
///
/// 与 `TitleConfigClient` / `DeclarationConfigClient` 同一套机制：
/// 先读 `miniw/ma/configIndex.lua` 拿到配置文件的 md5，再取 `miniw/ma/<md5>.lua`，
/// 本地按 url 缓存（配置名带 md5，可长期复用）。
library;

import 'package:dio/dio.dart';

import '../models/gift_catalog.dart';
import '../net/config.dart' show kDefaultBase;
import '../net/http_factory.dart' show createDio;
import 'config_text_cache.dart';
import 'title_config.dart' show parseConfigIndex;

/// 礼物目录客户端（进程内缓存目录）。
class GiftConfigClient {
  final Dio _dio;
  final String baseUrl;

  GiftConfigClient({Dio? dio, String? baseUrl})
    : _dio = dio ?? createDio(),
      baseUrl = baseUrl ?? kDefaultBase;

  static GiftCatalog? _cache;

  String _base() => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String> _getText(String url) async {
    final cached = await ConfigTextCache.instance.get(url);
    if (cached != null) return cached;
    final resp = await _dio.get(url);
    final d = resp.data;
    final text = d is String ? d : '$d';
    await ConfigTextCache.instance.put(url, text);
    return text;
  }

  /// 拉取并解析礼物目录（失败返回空目录，不缓存失败结果）。
  Future<GiftCatalog> catalog() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final index = parseConfigIndex(
        await _getText('${_base()}/miniw/ma/configIndex.lua'),
      );
      final cfgMd5 = index['new_give_gift_config'];
      if (cfgMd5 == null) return GiftCatalog.empty;
      final raw = await _getText('${_base()}/miniw/ma/$cfgMd5.lua');
      final catalog = parseGiftCatalog(raw);
      if (catalog.isEmpty) return GiftCatalog.empty;

      // 道具名/图标（拿不到就只显示编号）。
      var merged = catalog;
      final itemsMd5 = index['items'];
      if (itemsMd5 != null) {
        try {
          merged = mergeGiftNames(
            catalog,
            parseItemDefs(await _getText('${_base()}/miniw/ma/$itemsMd5.lua')),
          );
        } catch (_) {
          // 忽略：名称只是锦上添花
        }
      }
      return _cache = merged;
    } catch (_) {
      return GiftCatalog.empty;
    }
  }
}
