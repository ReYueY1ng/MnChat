/// Mini World HTTP 网关客户端 —— 所有 /miniw/* /server/* 请求的统一出口。
/// 移植自 MNClient `services/friend.py` + `net/lua_table.py`。
library;

import 'package:dio/dio.dart';

import '../crypto/encoding.dart' show luaUrlEncode;
import '../crypto/md5_sign.dart';
import '../net/config.dart'
    show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart';
import '../protocol/lua_table.dart';
import '../utils/log.dart' show redactUrl;
import 'request_errors.dart' show RequestErrorBus, labelFromUrl, reportIfFailed;

/// 网关响应解码：先 JSON 后 LuaTable；解析失败时上报并把空表返回给调用方。
///
/// 与 [decodeHttpResponse] 只差一点：**解析失败不再静默**。
///
/// `decodeHttpResponse` 会在响应体既不是 JSON 也不是 LuaTable 时抛
/// [LuaTableDecodeError]，以前这里把它吞成 `{}` —— 调用方只看到「空数据」，
/// 分不清是「服务端本来没数据」还是「响应解析挂了」。现在连同 [url] 一起报到
/// [RequestErrorBus]，UI 的失败角标里能看到是哪个请求、什么原因。
///
/// 空响应体仍然按 `{}` 返回且**不算失败**：变更类接口成功时就返回 200 无 body。
Object? decodeGatewayResponse(String text, {String? url}) {
  try {
    return decodeHttpResponse(text);
  } on LuaTableDecodeError catch (e) {
    RequestErrorBus.instance.report(
      label: url == null ? '响应解析' : labelFromUrl(url),
      endpoint: url == null ? '' : redactUrl(url),
      message: '响应既非 JSON 也非 LuaTable：${e.message}',
    );
    return <String, Object?>{};
  }
}

/// Dart 版 rstrip('/')。
String _rstripSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// CreateFriendRequest URL 构造器 (friendservice.lua:947-1010)。
///
/// 实测对齐（穷举验证，send_chat_msg 返回 {"send_time":..,"result":0} 为成功）：
/// - **所有参数（含 cmd、msg）都参与签名**（msg 无 notAuth 标记）
/// - 签名串用 **Lua urlEncode 转义后的值**（同反编译 addparam url_escape）
/// - URL query 同样排序 + urlencode
String buildFriendRequestUrl({
  required String server,
  required String path,
  required String cmd,
  Map<String, String> params = const {},
  Set<String>? notAuthKeys,
}) {
  final allParams = <String, String>{'cmd': cmd, ...params};
  final sorted = allParams.keys.toList()..sort();
  // URL query: 排序后 urlencode
  final query = sorted
      .map((k) => '$k=${Uri.encodeQueryComponent(allParams[k]!)}')
      .join('&');
  // canonical（签名串）: 全部参与（除非显式 notAuth），值用 Lua urlEncode 转义
  final canonical = sorted
      .where((k) => !(notAuthKeys?.contains(k) ?? false))
      .map((k) => '$k=${luaUrlEncode(allParams[k]!)}')
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

/// `/miniw/*` 参数签名 GET 的完整 URL（对齐反编译 `http_getParamMD5` + `url_addParams`）。
///
/// 关键点：真机请求在**业务参数之外**永远再带一组全局参数
/// （`uin / ver / apiid / lang / country / server_ts`，见 `http.lua:117-186`），
/// 而且这组参数**既进签名、也进 query**。漏掉它们会：
/// - 服务器缺 `uin` → **HTTP 400**（线上「表情已拥有列表拉取失败」就是这个）；
/// - 即使不 400，md5 也与服务器算的不一致。
///
/// 另外对齐签名细节：`s2` 只进签名不进 query；`json` 在排除表里（所以追加的
/// `json=1` 不参与签名）；`encrypt_ver=3` 两者都有。
String buildMiniwParamMd5Url({
  required String baseUrl,
  required String path,
  required Map<String, String> params,
  required int uin,
  required String s2,
  required String s2t,
  String ver = kClientVersionStr,
  String apiId = kApiId,
  String lang = '0',
  String country = 'CN',
  List<String> trailing = const [],
  int? now,
}) {
  final ts = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final all = <String, String>{
    // url_addParams("") 注入的全局参数
    'uin': '$uin',
    'ver': ver,
    'apiid': apiId,
    'lang': lang,
    'country': country,
    'server_ts': '$ts',
    ...params,
  };
  final md5 = httpGetParamMd5(all, timeVal: ts, s2: s2, s2t: s2t);
  final parts = <String>[
    ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
    'time=$ts',
    's2t=$s2t',
    'encrypt_ver=3',
  ];
  final base = _rstripSlash(baseUrl);
  final cleanPath = path.startsWith('/') ? path : '/$path';
  final tail = trailing.isEmpty ? '' : '&${trailing.join('&')}';
  return '$base$cleanPath?${parts.join('&')}&md5=$md5$tail';
}

/// 统一 GET 请求（网关路径，自动带 UA）。
class GatewayClient {
  final Dio _dio;
  final Map<String, String> _urls;

  GatewayClient({Dio? dio, Map<String, String>? urls})
      : _dio = dio ?? createDio(),
        _urls = {...kDefaultUrls, ...?urls};

  /// 解析 URL key → base URL。
  /// 取配置真实地址；未配置时回退到 [kDefaultBase]。
  String resolve(String key) => _urls[key] ?? kDefaultBase;

  /// GET 并解码响应（JSON → LuaTable 兼容）。
  ///
  /// 业务码非 0（`code`/`ret`/`result`）与响应体解析失败都会上报给 UI 的失败提示。
  Future<Map<String, Object?>> get(String url,
      {Map<String, String>? query}) async {
    final resp = await _dio.get(url, queryParameters: query);
    final data = _decodeBody(resp.data, url);
    reportIfFailed(url, data);
    if (data is Map) return data.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// POST 并解码响应。业务码非 0 与解析失败同样上报。
  Future<Map<String, Object?>> post(String url,
      {Object? data, String? contentType}) async {
    final resp = await _dio.post(url,
        data: data, options: Options(contentType: contentType));
    final decoded = _decodeBody(resp.data, url);
    reportIfFailed(url, decoded);
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// 解响应体。dio 的默认 `ResponseType.json` 会把 JSON content-type 的响应
  /// 直接解成 Map/List，其余情况留 String —— 原来这里写死
  /// `resp.data as String?`，服务端一旦回 JSON content-type 就是未捕获的
  /// CastError。与其余 client 的 `raw is String ? ... : raw` 保持一致。
  Object? _decodeBody(Object? data, String url) =>
      data is String ? decodeGatewayResponse(data, url: url) : data;
}