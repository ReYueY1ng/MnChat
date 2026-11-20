/// 把网关请求就地改写成 1.60 安全会话信封的 Dio 拦截器。
///
/// 只在满足全部条件时介入，否则请求原样发出（服务端若回退协议，行为与旧版一致）：
/// 1. 存在已激活的 [SecureSession]（登录下发了 `session` 且未被登出）；
/// 2. 目标是 mini1 网关（host 以 `mini1.cn` 结尾）；
/// 3. 路径命中白名单且不在黑名单（[shouldSecurePath]）。
///
/// 改写内容（协议见 MNReverse `docs/RE/1.60_secure_session_http.md`）：
/// - 方法固定为 `POST`（外层方法只认 POST，否则 40002）；
/// - 查询串搬进加密 JSON 的 `query` 字段，URL 上不再保留；
/// - 追加 `X-Protocol-Version/App-ID/Encrypted/Access/UIN/Api-Name/Api-Value/Nonce`；
/// - `Content-Type: application/octet-stream`，body 为密文。
///
/// access_token 的 TTL 只有 **900 秒**（游戏端实测，见会话文档）：所以
/// - 发请求前若临近过期（[SecureSession.needsRefresh]）先续期；
/// - 仍撞到 401（40101/40102）时续期后用新 token **重发一次**。
///
/// 响应侧：`X-Protocol-Encrypted: 1` 时用 rx 密钥解密，必要时 gunzip，
/// 再把明文塞回 `response.data`，让既有 `decodeGatewayResponse` 继续工作。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/log.dart' show log;
import 'secure_session.dart';

/// 拦截器写进 `RequestOptions.extra` 的键：本次请求的封包元信息。
const String kSecureRequestExtraKey = 'mnchat.secureSession';

/// 改写前的原始（明文）请求，401 重发时用它重建请求。
const String kSecurePlainExtraKey = 'mnchat.secureSessionPlain';

/// 已经因 401 重发过一次，避免续期失效时无限循环。
const String kSecureRetriedExtraKey = 'mnchat.secureSessionRetried';

class _SecureRequestMeta {
  final String path;
  final String apiName;
  final String apiValue;
  const _SecureRequestMeta(this.path, this.apiName, this.apiValue);
}

/// 改写前的明文请求快照。
class _PlainRequest {
  final String url;
  final String method;
  final String apiName;
  final String apiValue;
  final String query;
  final String body;
  final Map<String, dynamic> headers;
  const _PlainRequest({
    required this.url,
    required this.method,
    required this.apiName,
    required this.apiValue,
    required this.query,
    required this.body,
    required this.headers,
  });
}

class SecureSessionInterceptor extends Interceptor {
  final SecureSessionRegistry registry;

  /// 重发用：`onError` 里拿不到发起请求的那个 Dio，构造时注入。
  Dio? _dio;

  SecureSessionInterceptor({SecureSessionRegistry? registry})
      : registry = registry ?? SecureSessionRegistry.instance;

  /// 绑定宿主 Dio（`createDio()` 里调用），让 401 重发能走完整拦截器链。
  void attach(Dio dio) => _dio = dio;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = registry.session;
    if (!registry.active || session == null) {
      handler.next(options);
      return;
    }
    final uri = options.uri;
    if (!uri.host.endsWith('mini1.cn')) {
      handler.next(options);
      return;
    }
    if (!shouldSecurePath(uri.path)) {
      handler.next(options);
      return;
    }
    // 已经封过包（重发流程里由 onError 重新构造）就跳过。
    if (options.extra[kSecureRequestExtraKey] != null) {
      handler.next(options);
      return;
    }

    final method = options.method.toUpperCase();
    if (method != 'GET' && method != 'POST') {
      handler.next(options);
      return;
    }

    final query = uri.query;
    final (apiName, apiValue) = apiNameValueFromQuery(query);
    final plain = _PlainRequest(
      url: uri.toString(),
      method: method,
      apiName: apiName,
      apiValue: apiValue,
      query: query,
      body: _bodyText(options.data),
      headers: Map<String, dynamic>.from(options.headers),
    );

    // 临近过期先续期；续期失败则继续用旧 token（401 还有兜底）。
    registry
        .ensureFresh()
        .then((fresh) => _sealAndContinue(options, handler, fresh, plain))
        .catchError((Object e, StackTrace st) {
          log.warn('安全会话续期失败（沿用旧 token）: $e', tag: 'Net');
          _sealAndContinue(options, handler, session, plain);
        });
  }

  void _sealAndContinue(
    RequestOptions options,
    RequestInterceptorHandler handler,
    SecureSession session,
    _PlainRequest plain,
  ) {
    session
        .seal(
          path: Uri.parse(plain.url).path,
          apiName: plain.apiName,
          apiValue: plain.apiValue,
          method: plain.method.toLowerCase(),
          query: plain.query,
          body: plain.body,
        )
        .then((sealed) {
          final (cipher, nonce) = sealed;
          options.extra[kSecureRequestExtraKey] =
              _SecureRequestMeta(
                Uri.parse(plain.url).path,
                plain.apiName,
                plain.apiValue,
              );
          options.extra[kSecurePlainExtraKey] = plain;
          options.method = 'POST';
          // 清掉查询串：参数已经在密文里。用完整 URL（含 scheme/host），
          // 因为调用方常用绝对 URL 字符串发请求，baseUrl 可能是空的。
          options.path = Uri.parse(plain.url).replace(query: '').toString();
          options.queryParameters = const {};
          options.data = cipher;
          options.responseType = ResponseType.bytes;
          options.headers.remove('content-type');
          options.headers['Content-Type'] = 'application/octet-stream';
          options.headers['X-Protocol-Version'] = kSecureProtocolVersion;
          options.headers['X-Protocol-App-ID'] = kSecureProtocolAppId;
          options.headers['X-Protocol-Encrypted'] = '1';
          options.headers['X-Protocol-Access'] = session.accessToken;
          options.headers['X-Protocol-UIN'] = '${session.uin}';
          options.headers['X-Protocol-Api-Name'] = plain.apiName;
          options.headers['X-Protocol-Api-Value'] = plain.apiValue;
          options.headers['X-Protocol-Nonce'] = nonce;
          handler.next(options);
        })
        .catchError((Object e, StackTrace st) {
          // 加密失败不能让请求直接消失：报错并交回调用方（由 onError 统一上报）。
          log.warn('安全会话封装失败: $e', tag: 'Net');
          handler.reject(
            DioException(
              requestOptions: options,
              error: e,
              stackTrace: st,
              message: '安全会话封装失败: $e',
            ),
            true,
          );
        });
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final meta = response.requestOptions.extra[kSecureRequestExtraKey];
    final session = registry.session;
    if (meta is! _SecureRequestMeta || session == null) {
      handler.next(response);
      return;
    }
    if (response.headers.value('X-Protocol-Encrypted') != '1') {
      handler.next(response);
      return;
    }

    final data = response.data;
    final bytes = data is Uint8List
        ? data
        : data is List<int>
            ? Uint8List.fromList(data)
            : Uint8List(0);
    final nonce = response.headers.value('X-Protocol-Nonce') ?? '';
    if (nonce.isEmpty) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: '安全会话响应缺少 X-Protocol-Nonce',
        ),
        true,
      );
      return;
    }

    session
        .open(
          path: meta.path,
          apiValue: meta.apiValue,
          cipherText: bytes,
          nonceBase64Url: nonce,
          contentEncoding: response.headers.value('X-Protocol-Content-Encoding'),
        )
        .then((clear) {
          final text = utf8.decode(clear, allowMalformed: true);
          response.data = text;
          response.headers.set('content-type', 'application/json');
          handler.next(response);
        })
        .catchError((Object e, StackTrace st) {
          log.warn('安全会话解封失败: $e', tag: 'Net');
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: e,
              stackTrace: st,
              message: '安全会话解封失败: $e',
            ),
            true,
          );
        });
  }

  /// 401 兜底：确认是 token 过期/无效就续期并用新 token 重发 **一次**。
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final meta = err.requestOptions.extra[kSecureRequestExtraKey];
    final plain = err.requestOptions.extra[kSecurePlainExtraKey];
    final dio = _dio;
    if (meta is! _SecureRequestMeta ||
        plain is! _PlainRequest ||
        dio == null ||
        registry.session == null) {
      handler.next(err);
      return;
    }
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    if (err.requestOptions.extra[kSecureRetriedExtraKey] == true) {
      handler.next(err);
      return;
    }

    final code = _bodyCode(err.response?.data);
    registry
        .refreshAfterUnauthorized(code)
        .then((fresh) async {
          log.info(
            '安全会话 401(code=$code) 已续期，重发 ${plain.method} ${meta.path}',
            tag: 'Net',
          );
          final retry = RequestOptions(
            path: plain.url,
            method: plain.method,
            headers: Map<String, dynamic>.from(plain.headers),
            responseType: ResponseType.bytes,
            extra: <String, dynamic>{kSecureRetriedExtraKey: true},
          );
          // 走完整拦截器链：onRequest 会用 fresh token 重新封包。
          final resp = await dio.fetch<dynamic>(retry);
          handler.resolve(resp);
        })
        .catchError((Object e) {
          log.warn('安全会话 401 续期/重发失败: $e', tag: 'Net');
          handler.next(err);
        });
  }

  /// 从错误响应体里取业务码（可能是 bytes / String / Map）。
  static int? _bodyCode(dynamic data) {
    try {
      String? text;
      if (data is String) {
        text = data;
      } else if (data is List<int>) {
        text = utf8.decode(data, allowMalformed: true);
      } else if (data is Map) {
        final code = data['code'];
        return code is num ? code.toInt() : null;
      }
      if (text == null || text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final code = decoded['code'];
        return code is num ? code.toInt() : null;
      }
    } catch (_) {
      // 解析不出来就当没有业务码：refreshAfterUnauthorized 会按“未知码”处理。
    }
    return null;
  }

  static String _bodyText(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is List<int>) return base64Encode(data);
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }
}
