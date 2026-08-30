/// Mini World HTTP 网关客户端 —— 所有 /miniw/* /server/* 请求的统一出口。
/// 移植自 MNClient `services/friend.py` + `net/lua_table.py`。
library;

import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart';
import '../net/config.dart';
import '../protocol/lua_table.dart';

/// 网关响应解码：先 JSON 后 LuaTable，异常时返回 null 结构。
Object? decodeGatewayResponse(String text) {
  try {
    return decodeHttpResponse(text);
  } on LuaTableDecodeError {
    return <String, Object?>{};
  }
}

/// Dart 版 rstrip('/')。
String _rstripSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// CreateFriendRequest URL 构造器 (friendservice.lua:259-296)。
/// 与 Python MNClient `_build_friend_url` 完全对齐：
/// all_params = {cmd} + 调用方 params；签名 = md5(排除 notAuth 的
/// 排序后 key=value 拼接 + ROOM_AUTH_KEY)。**不自动注入任何字段**。
String buildFriendRequestUrl({
  required String server,
  required String path,
  required String cmd,
  Map<String, String> params = const {},
  Set<String>? notAuthKeys,
}) {
  final allParams = <String, String>{'cmd': cmd, ...params};
  final sorted = allParams.keys.toList()..sort();
  // URL query: 排序后 urlencode（空格→+，与 Python urlencode 一致）
  final query = sorted
      .map((k) => '$k=${Uri.encodeQueryComponent(allParams[k]!)}')
      .join('&');
  // canonical（签名串）: 排除 notAuth 字段，用原始值（不 urlencode）
  final canonical = sorted
      .where((k) => !(notAuthKeys?.contains(k) ?? false))
      .map((k) => '$k=${allParams[k]}')
      .join('&');
  final sign = md5Sign([canonical, roomAuthKey]);
  return '${_rstripSlash(server)}$path?$query&auth=$sign';
}

/// 群组请求 URL 构造器 (friendservice.lua CreateGroupChatRequest)。
/// 与 Python MNClient `http_group.py:_build_url` 完全对齐：
/// query = act + 调用方 params（不排序、不自动注入），签名 = http_get_s1。
String buildGroupUrl({
  required String server,
  required String path,
  required String s2,
  required String s2t,
  required int uin,
  required String act,
  Map<String, String>? extraParams,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final sign = httpGetS1(now, s2, uin, s2t);
  final parts = <String>['act=$act'];
  for (final e in (extraParams ?? {}).entries) {
    parts.add('${e.key}=${e.value}');
  }
  final query = parts.join('&');
  return '${_rstripSlash(server)}$path?$query&$sign';
}

/// 统一 GET 请求（网关路径，自动带 UA）。
class GatewayClient {
  final Dio _dio;
  final Map<String, String> _urls;

  GatewayClient({Dio? dio, Map<String, String>? urls})
      : _dio = dio ??
            Dio(BaseOptions(
              headers: {'User-Agent': kUa},
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _urls = {...kDefaultUrls, ...?urls};

  /// 解析 URL key → base URL。
  String resolve(String key) => _urls[key] ?? kDefaultBase;

  /// GET 并解码响应（JSON → LuaTable 兼容）。
  Future<Map<String, Object?>> get(String url,
      {Map<String, String>? query}) async {
    final resp = await _dio.get(url, queryParameters: query);
    final data = decodeGatewayResponse(resp.data as String? ?? '');
    if (data is Map) return data.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// POST 并解码响应。
  Future<Map<String, Object?>> post(String url,
      {Object? data, String? contentType}) async {
    final resp = await _dio.post(url,
        data: data, options: Options(contentType: contentType));
    final decoded = decodeGatewayResponse(resp.data as String? ?? '');
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }
}