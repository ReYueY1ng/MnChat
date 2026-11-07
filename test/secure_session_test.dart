/// 1.60 安全会话（SecureSession）单元测试。
///
/// 覆盖协议里最容易写错、又无法靠“跑一次”发现的部分：
/// - AAD 精确格式（服务端逐字节比对，错一个字符就是 40007）；
/// - `X-Protocol-Api-Name/Value` 的提取规则；
/// - 白名单/黑名单边界（黑名单优先）；
/// - `crypto_kx` 等价推导的已知答案（KAT，与 Python 参考实现逐字节一致）；
/// - 拦截器回退：没有会话时请求必须原样发出（服务端回退协议时不至于全挂）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/net/secure_session.dart';
import 'package:mnchat/core/net/secure_session_interceptor.dart';

Uint8List _hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

SecureSession _session({
  Uint8List? rx,
  Uint8List? tx,
  int uin = 2089540493,
}) {
  return SecureSession(
    sessionId: 'test-session',
    accessToken: 'test-token',
    uin: uin,
    clientSecretKey: Uint8List(32),
    clientPublicKey: Uint8List(32),
    rxKey: rx ?? Uint8List.fromList(List<int>.generate(32, (i) => i)),
    txKey: tx ?? Uint8List.fromList(List<int>.generate(32, (i) => 255 - i)),
  );
}

/// 捕获实际发出去的请求，并可返回预设响应。
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? captured;
  Uint8List? capturedBody;
  ResponseBody Function(RequestOptions options)? respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      capturedBody = Uint8List.fromList(chunks);
    }
    final body = respond?.call(options);
    return body ?? ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  tearDown(() => SecureSessionRegistry.instance.clear());

  group('AAD', () {
    test('request AAD 与抓包逐字节一致', () {
      expect(
        buildRequestAad(
          path: '/server/friend',
          uin: 2089540493,
          apiValue: 'list_appointments',
        ),
        'v4|request|/server/friend|miniworld|2089540493|list_appointments',
      );
    });

    test('response AAD 用 response 段', () {
      expect(
        buildResponseAad(
          path: '/miniw/business',
          uin: 1,
          apiValue: 'get_business_advert',
        ),
        'v4|response|/miniw/business|miniworld|1|get_business_advert',
      );
    });
  });

  group('apiNameValueFromQuery', () {
    test('优先 act', () {
      expect(
        apiNameValueFromQuery('uin=1&act=bubble_get_data&cmd=x'),
        ('act', 'bubble_get_data'),
      );
    });

    test('其次 cmd', () {
      expect(
        apiNameValueFromQuery('page=1&cmd=query_friend_list&uin=1'),
        ('cmd', 'query_friend_list'),
      );
    });

    test('都没有时返回空', () {
      expect(apiNameValueFromQuery('uin=1&page=2'), ('', ''));
    });

    test('值按 urlencode 解码', () {
      expect(
        apiNameValueFromQuery('act=hello%20world'),
        ('act', 'hello world'),
      );
    });
  });

  group('shouldSecurePath', () {
    test('白名单', () {
      expect(shouldSecurePath('/miniw/business'), isTrue);
      expect(shouldSecurePath('/server/friend'), isTrue);
      expect(shouldSecurePath('/center/iap/'), isTrue);
    });

    test('黑名单优先', () {
      expect(shouldSecurePath('/miniw/map'), isFalse);
      expect(shouldSecurePath('/miniw/map/'), isFalse);
      expect(shouldSecurePath('/miniw/php_cmd'), isFalse);
      expect(shouldSecurePath('/miniw/crypto/refresh-access'), isFalse);
      expect(shouldSecurePath('/miniw/report/x'), isFalse);
    });

    test('黑名单按路径段匹配，不误伤同前缀资源', () {
      expect(shouldSecurePath('/miniw/mapbag'), isTrue);
    });
  });

  group('crypto_kx 推导', () {
    test('KAT 与 Python 参考实现一致', () async {
      final cSk = _hex('0000000000000000000000000000000000000000000000000000000000000007');
      final sPk = _hex('7b4e909bbe7ffe44c465a220037d608ee35897d31ef972f07f74892cb0f73f13');
      final session = await SecureSession.fromLoginSession(
        uin: 2089540493,
        session: <String, Object?>{
          'session_id': 'sid',
          'access_token': 'token',
          's_pk': base64UrlEncode(sPk),
        },
        clientSecretKey: cSk,
        clientPublicKey: _hex(
          'f6031bd7596323fa540041bd3a635133e72878493e7620048875887bdc8b9907',
        ),
      );
      expect(session, isNotNull);
      expect(
        session!.rxKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'df1be1145403a7d02933e8c39a452a980b0f52f3ffe068c8239d023fd64eec4c',
      );
      expect(
        session.txKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '093c3b3b2c3772ec8997d016c7dc6aa05b899fd0f183122fdab7a77efdf3ba3b',
      );
    });

    test('session 缺失时返回 null（服务端未启用 → 回退明文）', () async {
      final s = await SecureSession.fromLoginSession(
        uin: 1,
        session: const <String, Object?>{},
        clientSecretKey: Uint8List(32),
        clientPublicKey: Uint8List(32),
      );
      expect(s, isNull);
    });
  });

  group('SecureSessionInterceptor', () {
    test('无会话时请求原样发出（回退路径）', () async {
      final adapter = _CapturingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://shequ.mini1.cn:8081'))
        ..httpClientAdapter = adapter
        ..interceptors.add(SecureSessionInterceptor());

      await dio.get('/server/friend?cmd=query_friend_list&uin=1');

      expect(adapter.captured, isNotNull);
      expect(adapter.captured!.method, 'GET');
      expect(
        adapter.captured!.headers.keys
            .map((k) => k.toLowerCase())
            .where((k) => k.startsWith('x-protocol')),
        isEmpty,
      );
    });

    test('有会话时改写为 POST + 加密信封，AAD/明文可复原', () async {
      final rx = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final tx = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
      SecureSessionRegistry.instance.install(_session(rx: rx, tx: tx));

      final adapter = _CapturingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://shequ.mini1.cn:8081'))
        ..httpClientAdapter = adapter
        ..interceptors.add(SecureSessionInterceptor());

      await dio.get('/server/friend?cmd=query_friend_list&uin=2089540493');

      final req = adapter.captured!;
      expect(req.method, 'POST');
      expect(req.uri.query, isEmpty);
      expect(req.headers['X-Protocol-Version'], 'v4');
      expect(req.headers['X-Protocol-App-ID'], 'miniworld');
      expect(req.headers['X-Protocol-Encrypted'], '1');
      expect(req.headers['X-Protocol-Api-Name'], 'cmd');
      expect(req.headers['X-Protocol-Api-Value'], 'query_friend_list');
      expect(req.headers['X-Protocol-UIN'], '2089540493');

      final nonce = base64Url.decode(
        base64Url.normalize(req.headers['X-Protocol-Nonce'] as String),
      );
      final cipher = adapter.capturedBody!;
      final aad = utf8.encode(
        'v4|request|/server/friend|miniworld|2089540493|query_friend_list',
      );
      final clear = await _decrypt(tx, nonce, cipher, aad);
      final body = jsonDecode(clear) as Map<String, Object?>;
      expect(body['method'], 'get');
      expect(body['query'], 'cmd=query_friend_list&uin=2089540493');
      expect(body['body'], '');
    });
  });
}

Future<String> _decrypt(
  Uint8List key,
  List<int> nonce,
  Uint8List cipher,
  List<int> aad,
) async {
  final tagStart = cipher.length - 16;
  final box = SecretBox(
    cipher.sublist(0, tagStart),
    nonce: nonce,
    mac: Mac(cipher.sublist(tagStart)),
  );
  final clear = await Chacha20.poly1305Aead().decrypt(
    box,
    secretKey: SecretKey(key),
    aad: aad,
  );
  return utf8.decode(clear);
}
