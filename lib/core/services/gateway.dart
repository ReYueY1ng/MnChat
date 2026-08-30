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
/// 排序后的 key=value 对（排除 notAuth 字段）拼接 + ROOM_AUTH_KEY 求 MD5。
String buildFriendRequestUrl({
  required String server,
  required String path,
  required int uin,
  required int apiId,
  required String ver,
  required String country,
  required String lang,
  required String s2,
  required String s2t,
  required String cmd,
  Map<String, String>? extraParams,
  Set<String>? notAuthKeys,
}) {
  final params = <String, String>{
    'apiid': '$apiId',
    'country': country,
    'lang': lang,
    's2t': s2t,
    'uin': '$uin',
    'ver': ver,
    'cmd': cmd,
    ...?extraParams,
  };
  final sorted = params.keys.toList()..sort();
  final canonical = sorted
      .where((k) => !(notAuthKeys?.contains(k) ?? false))
      .map((k) => '$k=${params[k]}')
      .join('&');
  final sign = md5Sign([canonical, roomAuthKey]);
  final query = sorted.map((k) => '$k=${Uri.encodeQueryComponent(params[k]!)}').join('&');
  return '${_rstripSlash(server)}$path?$query&auth=$sign';
}

/// 群组请求 URL 构造器 (newfriendservice.lua CreateGroupChatRequest)。
/// 签名：http_get_s1(time, s2, uin, s2t)。
String buildGroupUrl({
  required String server,
  required String path,
  required int uin,
  required String ver,
  required String apiId,
  required String act,
  required String s2,
  required String s2t,
  Map<String, String>? extraParams,
}) {
  final httpGetS1_ = httpGetS1(DateTime.now().millisecondsSinceEpoch ~/ 1000, s2, uin, s2t);
  final params = <String, String>{
    'uin': '$uin',
    'ver': ver,
    'apiid': apiId,
    'log': 'null',
    'act': act,
    'json': '1',
    ...?extraParams,
  };
  final sorted = params.keys.toList()..sort();
  final query = sorted.map((k) => '$k=${Uri.encodeQueryComponent(params[k]!)}').join('&');
  return '${_rstripSlash(server)}$path?$query&$httpGetS1_';
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