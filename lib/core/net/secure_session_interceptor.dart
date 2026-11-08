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
/// 响应侧：`X-Protocol-Encrypted: 1` 时用 rx 密钥解密，必要时 gunzip，
/// 再把明文塞回 `response.data`，让既有 `decodeGatewayResponse` 继续工作。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/log.dart' show log;
import 'secure_session.dart';

/// 拦截器写进 `RequestOptions.extra` 的键。
const String kSecureRequestExtraKey = 'mnchat.secureSession';

class _SecureRequestMeta {
  final String path;
  final String apiName;
  final String apiValue;
  const _SecureRequestMeta(this.path, this.apiName, this.apiValue);
}

class SecureSessionInterceptor extends Interceptor {
  final SecureSessionRegistry registry;

  SecureSessionInterceptor({SecureSessionRegistry? registry})
      : registry = registry ?? SecureSessionRegistry.instance;

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

    // 已经改写过（重试 / 递归）就跳过。
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
    final body = _bodyText(options.data);

    session
        .seal(
          path: uri.path,
          apiName: apiName,
          apiValue: apiValue,
          method: method.toLowerCase(),
          query: query,
          body: body,
        )
        .then((sealed) {
          final (cipher, nonce) = sealed;
          options.extra[kSecureRequestExtraKey] =
              _SecureRequestMeta(uri.path, apiName, apiValue);
          options.method = 'POST';
          // 清掉查询串：参数已经在密文里。用完整 URL（含 scheme/host），
          // 因为调用方常用绝对 URL 字符串发请求，baseUrl 可能是空的。
          options.path = uri.replace(query: '').toString();
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
          options.headers['X-Protocol-Api-Name'] = apiName;
          options.headers['X-Protocol-Api-Value'] = apiValue;
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
