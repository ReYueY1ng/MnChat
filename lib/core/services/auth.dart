/// Mini World HTTP 登录客户端 —— login_v3 (口令认证) + WebSocket 心跳取 s2/s2t。
/// 移植自 MNClient `account/login.py` + `account/wsconn.py`。
library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/encoding.dart' show urlsafeB64Urlencode;
import '../crypto/md5_sign.dart' show md5Sign, loginAuthKey;
import '../crypto/xxtea.dart' show xxteaDecrypt, xxteaEncrypt, xxteaEncryptZip;
import '../net/config.dart';
import '../net/msgpack.dart' show msgpackPack, msgpackUnpack;

/// 认证结果。
class MiniAuth {
  final int uin;
  final int apiId;
  final String name;
  final String s2;
  final String s2t;
  final String jwt;

  const MiniAuth({
    required this.uin,
    required this.apiId,
    required this.name,
    required this.s2,
    required this.s2t,
    required this.jwt,
  });

  Map<String, Object?> toJson() => {
        'uin': uin,
        'api_id': apiId,
        'name': name,
        's2': s2,
        's2t': s2t,
        'jwt': jwt,
      };

  factory MiniAuth.fromJson(Map<String, Object?> json) => MiniAuth(
        uin: (json['uin'] as num).toInt(),
        apiId: (json['api_id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        s2: json['s2'] as String? ?? '',
        s2t: json['s2t'] as String? ?? '',
        jwt: json['jwt'] as String? ?? '',
      );
}

class MiniAuthError implements Exception {
  final String message;
  MiniAuthError(this.message);
  @override
  String toString() => 'MiniAuthError: $message';
}

/// 登录客户端。
class LoginClient {
  final Dio _dio;

  LoginClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              headers: {'User-Agent': kUa},
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ));

  /// login_v3：payload → msgpack → zlib → XXTEA → url-safe base64。
  String _encode(Map<String, Object?> payload) {
    final packed = msgpackPack(payload);
    final enc = xxteaEncryptZip(packed);
    return urlsafeB64Urlencode(enc);
  }

  /// 6 端口随机池，登录。
  Future<MiniAuth> login({
    required int uin,
    required String passwd,
    int apiId = 110,
    String deviceId = 'MNClientDefault',
  }) async {
    final serverTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = <String, Object?>{
      'source': 'client',
      'juhe_auth': '',
      'passwd_auth': '{"passwd":"$passwd"}',
      'DeviceID': deviceId,
      'is_url': true,
      'geetest': 'blending',
      'target': 'login',
      'apiid': apiId,
      'juhe_strong_auth': '',
      'svrTime': serverTime,
      'login_type': 'passwd',
      'version': kCltVersion,
      'time': serverTime,
      'uin': uin,
    };

    final msg = _encode(payload);
    final sign = md5Sign(['msg=', msg, '&key=', loginAuthKey]);
    // 端口是 URL 端口（login_v3 支持 14100-14150 多端口池，随机选）
    final port = kLoginPorts[Random().nextInt(kLoginPorts.length)];
    final url = Uri.https(
      kLoginHost,
      kLoginPath,
      {'msg': msg, 'sign': sign},
    ).replace(port: port);

    final resp = await _dio.getUri(url, options: Options(headers: {'User-Agent': kUa}));
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final Map<String, Object?> data;
    try {
      data = (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      throw MiniAuthError('Login failed: invalid JSON response: ${text.substring(0, text.length > 200 ? 200 : text.length)}');
    }

    final code = data['code'];
    if (code is int && code == 0) {
      final authinfo = (data['authinfo'] as Map).cast<String, Object?>();
      final baseinfo = (data['baseinfo'] as Map).cast<String, Object?>();
      final fullSign = authinfo['sign'] as String? ?? '';
      final splitIdx = fullSign.indexOf('_');
      final s2 = splitIdx <= 0 ? fullSign : fullSign.substring(0, splitIdx);
      final s2t = splitIdx <= 0 ? '' : fullSign.substring(splitIdx + 1);
      final roleInfo = ((baseinfo['RoleInfo'] as Map? ?? {}).cast<String, Object?>());
      return MiniAuth(
        uin: uin,
        apiId: apiId,
        name: roleInfo['NickName'] as String? ?? '',
        s2: s2,
        s2t: s2t,
        jwt: authinfo['token'] as String? ?? '',
      );
    }
    throw MiniAuthError('Login failed with code $code: ${data['msg']}');
  }
}

/// WebSocket 配置获取 + 心跳 s2/s2t 提取。
class WsConnection {
  /// 从 config 端点取 WS URL。
  Future<String> getWsUrl({required int uin, int apiId = 110}) async {
    final uri = Uri.parse('$kWsConfigUrl?${Uri(queryParameters: {
          'cltversion': '80384',
          'clttype': '0',
          'uin': '$uin',
          'game_env': '0',
          'ver': kClientVersionStr,
          'apiid': '$apiId',
          'lang': '0',
          'country': 'CN',
        }).query}');
    final resp = await Dio().getUri(uri, options: Options(headers: {'User-Agent': kUa}));
    // Dio 默认自动解析 JSON → resp.data 已是 Map；但保留 String 分支兼容
    final Map<String, dynamic> data;
    final raw = resp.data;
    if (raw is Map) {
      data = raw.cast<String, dynamic>();
    } else if (raw is String) {
      data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } else {
      throw MiniAuthError('Unexpected WS config response type: ${raw.runtimeType}');
    }
    return data['conn'] as String;
  }

  /// 心跳取 s2/s2t：连接 WS → 发 XXTEA(msgpack([0,seq,jwt])) → 收 [1,seq,code,result]。
  Future<(String, String)> fetchS2({
    required String jwt,
    required int uin,
    String? wsUrl,
  }) async {
    final url = wsUrl ?? await getWsUrl(uin: uin);
    final channel = WebSocketChannel.connect(Uri.parse(url));

    final seq = (DateTime.now().millisecondsSinceEpoch) % 10000000;
    // Python wsconn.py: xxtea.encrypt(ormsgpack.packb([0, seq, jwt])) — 无 zlib!
    final hb = xxteaEncrypt(List<int>.from(msgpackPack([0, seq, jwt])));
    channel.sink.add(hb);

    final raw = await channel.stream.first;
    final data = msgpackUnpack(xxteaDecrypt(raw));
    await channel.sink.close();

    if (data is! List || data.isEmpty || data[0] != 1 || data.length < 4) {
      throw MiniAuthError('Unexpected HB response: ${data.toString().substring(0, 200)}');
    }
    final code = data[2];
    if (code != 0) throw MiniAuthError('HB error code=$code');
    final result = data[3]?.toString() ?? '';
    if (!result.contains('_')) throw MiniAuthError('Invalid sign format: $result');
    final idx = result.indexOf('_');
    return (result.substring(0, idx), result.substring(idx + 1));
  }
}