/// 1.60 安全会话（SecureSession）请求封装。
///
/// 游戏 1.60.1 起，网关对 `/miniw/*`、`/server/friend/*`、`/center/*` 不再接受明文
/// 查询串：请求必须走 `POST` + ChaCha20-Poly1305 信封，并带一组 `X-Protocol-*` 头。
/// 协议逆向见 MNReverse `docs/RE/1.60_secure_session_http.md`。
///
/// 关键结论（全部有二进制/抓包证据）：
/// - 密钥：libsodium `crypto_kx_client_session_keys` 等价推导 ——
///   `q = X25519(c_sk, s_pk)`，`k = BLAKE2b-512(q ‖ c_pk ‖ s_pk)`，
///   `rx = k[0..32]`（解密响应）、`tx = k[32..64]`（加密请求）。
/// - AAD（`|` 分隔、无尾分隔符）：
///   请求 `v4|request|<path>|miniworld|<uin>|<api_value>`，
///   响应 `v4|response|<path>|miniworld|<uin>|<api_value>`。
/// - 明文 JSON：`{"method":"get"|"post","query":"<urlencode 查询串>","body":"<原 body>"}`。
/// - 密文 = `ciphertext ‖ 16B tag`，nonce（12B）走 `X-Protocol-Nonce`。
/// - 响应头 `X-Protocol-Content-Encoding: gzip` 时，解密后还要 gunzip。
///
/// 服务端随时可能回退这套协议，所以会话缺失时调用方一律回退明文（见
/// [SecureSessionRegistry.session] 与 `SecureSessionInterceptor`）。
library;

import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 网关安全协议的版本常量（`X-Protocol-Version` / AAD 前缀）。
const String kSecureProtocolVersion = 'v4';

/// `X-Protocol-App-ID`，同时参与 AAD。
const String kSecureProtocolAppId = 'miniworld';

/// 白名单前缀（命中即必须走安全会话）。
const List<String> kSecureWhitelistPrefixes = [
  '/miniw/',
  '/server/friend',
  '/center/',
];

/// 黑名单前缀（命中即保持明文，优先级高于白名单）。
///
/// 取自 login `session.gateway_rules.blacklist`。
const List<String> kSecureBlacklistPrefixes = [
  '/miniw/crypto/',
  '/miniw/cm/',
  '/miniw/map',
  '/miniw/php_cmd',
  '/miniw/cdn/',
  '/miniw/ma/',
  '/miniw/taobao_shop/',
  '/miniw/report/',
  '/miniw/kuaishou_shop/',
  '/miniw/douyin_shop/',
  '/miniw/patch/',
  '/miniw/rocketmq/',
  '/miniw/platform_metaapp/',
  '/miniw/bilibili_shop/',
  '/miniw/pdd_shop/',
];

/// 路径是否需要安全会话。
///
/// 黑名单优先：`/miniw/map` 会覆盖 `/miniw/` 白名单；黑名单条目按「路径段」
/// 匹配（`/miniw/map` 命中 `/miniw/map`、`/miniw/map/...`，但不命中 `/miniw/mapbag`）。
bool shouldSecurePath(String path) {
  for (final entry in kSecureBlacklistPrefixes) {
    if (entry.endsWith('/')) {
      if (path.startsWith(entry)) return false;
      continue;
    }
    if (path == entry || path.startsWith('$entry/')) return false;
  }
  for (final prefix in kSecureWhitelistPrefixes) {
    if (path.startsWith(prefix)) return true;
  }
  return false;
}

/// 从旧查询串里取 `X-Protocol-Api-Name` / `Api-Value`。
///
/// 游戏按 `act` / `cmd` 二选一（`sub_180326150` 只写这两个键）；都没有时
/// 返回空串（服务端按空值参与 AAD）。
(String name, String value) apiNameValueFromQuery(String query) {
  for (final name in const ['act', 'cmd']) {
    for (final part in query.split('&')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      if (part.substring(0, eq) != name) continue;
      final raw = part.substring(eq + 1);
      // 查询串是 urlencode 后的；AAD 用解码后的值（游戏里 Api-Value 就是明文）。
      return (name, Uri.decodeQueryComponent(raw));
    }
  }
  return ('', '');
}

/// 组装请求 AAD。
String buildRequestAad({
  required String path,
  required int uin,
  required String apiValue,
}) =>
    '$kSecureProtocolVersion|request|$path|$kSecureProtocolAppId|$uin|$apiValue';

/// 组装响应 AAD。
String buildResponseAad({
  required String path,
  required int uin,
  required String apiValue,
}) =>
    '$kSecureProtocolVersion|response|$path|$kSecureProtocolAppId|$uin|$apiValue';

/// 登录下发的安全会话（`session` 字段）+ 本地密钥对。
class SecureSession {
  final String sessionId;
  final String accessToken;
  final int uin;

  /// 客户端 X25519 私钥（32B），仅内存持有。
  final Uint8List clientSecretKey;

  /// 客户端 X25519 公钥（32B，登录时上报过）。
  final Uint8List clientPublicKey;

  /// 解密响应用的密钥。
  final Uint8List rxKey;

  /// 加密请求用的密钥。
  final Uint8List txKey;

  /// access_token 过期时间（unix 秒），0 表示未知。
  final int accessExpiresAt;

  SecureSession({
    required this.sessionId,
    required this.accessToken,
    required this.uin,
    required this.clientSecretKey,
    required this.clientPublicKey,
    required this.rxKey,
    required this.txKey,
    this.accessExpiresAt = 0,
  });

  bool get isExpired {
    if (accessExpiresAt <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 提前 60s 视为过期，给 refresh 留窗口。
    return now >= accessExpiresAt - 60;
  }

  /// 用会话密钥加密一条网关请求。
  ///
  /// 返回 `(ciphertext ‖ tag, nonceBase64Url)`。
  Future<(Uint8List, String)> seal({
    required String path,
    required String apiName,
    required String apiValue,
    required String method,
    required String query,
    required String body,
  }) async {
    final plain = jsonEncode(<String, Object?>{
      'method': method,
      'query': query,
      'body': body,
    });
    final aad = utf8.encode(
      buildRequestAad(path: path, uin: uin, apiValue: apiValue),
    );
    final nonce = _randomBytes(12);
    final box = await Chacha20.poly1305Aead().encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(txKey),
      nonce: nonce,
      aad: aad,
    );
    final out = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return (out, base64UrlEncode(nonce));
  }

  /// 解密网关响应；`contentEncoding` 为 gzip 时自动解压。
  Future<Uint8List> open({
    required String path,
    required String apiValue,
    required List<int> cipherText,
    required String nonceBase64Url,
    String? contentEncoding,
  }) async {
    if (cipherText.length < 16) {
      throw const SecureSessionError('响应密文短于 16 字节 tag');
    }
    final nonce = _decodeBase64Url(nonceBase64Url);
    if (nonce.length != 12) {
      throw SecureSessionError('响应 nonce 长度异常: ${nonce.length}');
    }
    final tagStart = cipherText.length - 16;
    final box = SecretBox(
      cipherText.sublist(0, tagStart),
      nonce: nonce,
      mac: Mac(cipherText.sublist(tagStart)),
    );
    final aad = utf8.encode(
      buildResponseAad(path: path, uin: uin, apiValue: apiValue),
    );
    final clear = await Chacha20.poly1305Aead().decrypt(
      box,
      secretKey: SecretKey(rxKey),
      aad: aad,
    );
    if (contentEncoding == 'gzip') {
      return Uint8List.fromList(GZipCodec().decode(clear));
    }
    return Uint8List.fromList(clear);
  }

  /// 从 login_v3 响应的 `session` 字段构建会话。
  ///
  /// `session` 缺失或字段不全时返回 `null`（服务端未启用 → 调用方回退明文）。
  static Future<SecureSession?> fromLoginSession({
    required int uin,
    required Map<String, Object?>? session,
    required Uint8List clientSecretKey,
    required Uint8List clientPublicKey,
  }) async {
    if (session == null || session.isEmpty) return null;
    final sessionId = session['session_id'] as String? ?? '';
    final accessToken = session['access_token'] as String? ?? '';
    final serverPublicKey = session['s_pk'] as String? ?? '';
    if (sessionId.isEmpty || accessToken.isEmpty || serverPublicKey.isEmpty) {
      return null;
    }
    final sPk = _decodeBase64Url(serverPublicKey);
    if (sPk.length != 32) return null;

    // q = X25519(c_sk, s_pk)
    final keyPair = await X25519().newKeyPairFromSeed(clientSecretKey);
    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(sPk, type: KeyPairType.x25519),
    );
    final q = Uint8List.fromList(await sharedSecret.extractBytes());

    // k = BLAKE2b-512(q ‖ c_pk ‖ s_pk)
    final material = Uint8List.fromList([
      ...q,
      ...clientPublicKey,
      ...sPk,
    ]);
    final digest = await Blake2b(hashLengthInBytes: 64).hash(material);
    final k = digest.bytes;
    if (k.length != 64) {
      throw const SecureSessionError('BLAKE2b 输出长度异常');
    }

    final expires = session['access_expires_at'];
    return SecureSession(
      sessionId: sessionId,
      accessToken: accessToken,
      uin: uin,
      clientSecretKey: clientSecretKey,
      clientPublicKey: clientPublicKey,
      rxKey: Uint8List.fromList(k.sublist(0, 32)),
      txKey: Uint8List.fromList(k.sublist(32, 64)),
      accessExpiresAt: expires is num ? expires.toInt() : 0,
    );
  }

  /// 生成一对 X25519 密钥，供 login_v3 上报公钥。
  static Future<(Uint8List, Uint8List)> generateKeyPair() async {
    final keyPair = await X25519().newKeyPair();
    final secret = await keyPair.extractPrivateKeyBytes();
    final pub = await keyPair.extractPublicKey();
    return (Uint8List.fromList(secret), Uint8List.fromList(pub.bytes));
  }
}

/// 安全会话相关错误。
class SecureSessionError implements Exception {
  final String message;
  const SecureSessionError(this.message);
  @override
  String toString() => 'SecureSessionError: $message';
}

/// 当前进程的安全会话槽位。
///
/// [SecureSessionInterceptor] 在 `createDio()` 里创建，拿不到 Riverpod 容器，
/// 所以沿用 `DuplicateRequestMonitor.instance` 的做法用单例传递。
/// 登录成功后由 `LoginClient` 写入；登出或登录失败时清空。
class SecureSessionRegistry {
  SecureSessionRegistry._();
  static final SecureSessionRegistry instance = SecureSessionRegistry._();

  SecureSession? _session;

  /// 运行期总开关：服务端回退时置 false 即可整体退回明文（默认开）。
  bool enabled = true;

  SecureSession? get session => _session;

  bool get active => enabled && _session != null;

  void install(SecureSession? session) => _session = session;

  void clear() => _session = null;
}

Uint8List _randomBytes(int n) {
  final rnd = Random.secure();
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rnd.nextInt(256);
  }
  return out;
}

Uint8List _decodeBase64Url(String s) {
  final normalized = base64Url.normalize(s);
  return Uint8List.fromList(base64Url.decode(normalized));
}

/// base64url 编码（去 padding），用于 `X-Protocol-Nonce`。
String base64UrlEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
