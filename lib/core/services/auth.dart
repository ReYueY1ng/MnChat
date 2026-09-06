/// Mini World HTTP 登录客户端 —— login_v3 (口令认证) + WebSocket 心跳取 s2/s2t。
/// 移植自 MNClient `account/login.py` + `account/wsconn.py`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/encoding.dart' show urlsafeB64Urlencode;
import '../crypto/md5_sign.dart' show chatpushAuthKey, md5Sign, loginAuthKey;
import '../crypto/xxtea.dart' show xxteaDecrypt, xxteaEncrypt, xxteaEncryptZip;
import '../net/config.dart';
import '../net/http_factory.dart';
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

  LoginClient({Dio? dio}) : _dio = dio ?? createDio();

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
    // Web：走同源代理（tool/web_proxy.dart），跳过端口随机池（代理固定 14100）；
    // 原生：保留端口池随机负载均衡。
    final Uri url;
    if (kIsWeb) {
      url = Uri.parse('${backendLogin()}$kLoginPath')
          .replace(queryParameters: {'msg': msg, 'sign': sign});
    } else {
      final port = kLoginPorts[Random().nextInt(kLoginPorts.length)];
      url = Uri.https(
        kLoginHost,
        kLoginPath,
        {'msg': msg, 'sign': sign},
      ).replace(port: port);
    }

    final resp = await _dio.getUri(url);
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
    final uri = Uri.parse('${backendWsConfig()}/update/?${Uri(queryParameters: {
          'cltversion': '80384',
          'clttype': '0',
          'uin': '$uin',
          'game_env': '0',
          'ver': kClientVersionStr,
          'apiid': '$apiId',
          'lang': '0',
          'country': 'CN',
        }).query}');
    final resp = await createDio().getUri(uri);
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

/// 主账号长连接（对应游戏 container.lua 的 WebSocketConnection / self.conn）。
/// 帧协议为 **XXTEA + msgpack**（非 chatpush 的 rotate-XOR+JSON），承载 buddy 好友服务 RPC
/// （friend_info / batch_friend_info → 在线状态）。URL 取自 `/update/` config 的 conn 字段。
class MainAccountConnection {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final Map<int, Completer<List<dynamic>>> _pending = {};
  int _seq = 0;

  /// RPC comm_param 字段（对齐游戏 remote_call）。
  final String _sceneId;
  final String _gameSessionId;

  MainAccountConnection({this._sceneId = '0', this._gameSessionId = ''});

  /// 主账号 alloc：请求体用 **XXTEA+msgpack** 编码（与 chatpush 的 rotate-XOR 区分），
  /// 服务器据此返回**主 gate** 的 host/token。
  static Future<(String, String)> alloc({
    required int uin,
    required String s2,
    required String s2t,
    String? lbUrl,
  }) async {
    final lb = lbUrl ?? kChatpushLbUrls[0]!;
    final timeVal = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final auth = md5Sign([timeVal.toString(), chatpushAuthKey, uin.toString()]);
    final loginauth = md5Sign(['$timeVal$s2$uin']);
    final params = <String, Object?>{
      'flag': 1,
      'uid': uin,
      'time': timeVal,
      'auth': auth,
      'loginauth': loginauth,
      's2t': s2t,
    };
    final enc = xxteaEncrypt(List<int>.from(msgpackPack(params)));
    final body = Uri.encodeComponent(base64Encode(enc));
    final resp = await createDio().post('$lb/minilb/alloc', data: body);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final Map<String, Object?> data;
    try {
      data = (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      throw MiniAuthError('main alloc: invalid JSON: $text');
    }
    if (data['code'] != 0) {
      throw MiniAuthError('main alloc failed: code=${data['code']}');
    }
    final d = (data['data'] as Map).cast<String, Object?>();
    return (d['host'] as String, d['token'] as String);
  }

  /// 连接主账号长连接（wsurl，/update/ config 的 conn 字段）。
  /// 认证：发 `[0,seq,jwt]` 并**等 ack**（fetchS2 同款），认证完成才可发 RPC。
  Future<void> connect({required String jwt, required int uin, String? wsUrl}) async {
    final url = wsUrl ?? await WsConnection().getWsUrl(uin: uin);
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    _seq = DateTime.now().microsecondsSinceEpoch % 100000;
    _sub = channel.stream.listen(_onMessage, onDone: _onDone);
    // 认证心跳 [0,seq,jwt]，等 [1,seq,code,result] ack 后才返回（连接已就绪）
    final authSeq = _seq;
    final authCompleter = Completer<List<dynamic>>();
    _pending[authSeq] = authCompleter;
    sendRaw([0, authSeq, jwt]);
    await authCompleter.future.timeout(const Duration(seconds: 5));
  }

  void sendRaw(List<dynamic> data) {
    _channel?.sink.add(xxteaEncrypt(List<int>.from(msgpackPack(data))));
  }

  /// 随机 32 位 hex（对齐游戏 log_id/session_id 等）。
  static String _randId() {
    final rnd = Random();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  /// 发一条 RPC 并等响应（`[1,seq,code,result,other]`）。comm_param 对齐游戏
  /// remote_call：session_id/log_id/scene_id/game_session_id。
  Future<List<dynamic>> sendRpc(String svc, String method, List<dynamic> args,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final seq = _seq = (_seq + 1) % 100000000;
    final msec = DateTime.now().millisecondsSinceEpoch % 100000000;
    final completer = Completer<List<dynamic>>();
    _pending[seq] = completer;
    final comm = <String, Object?>{
      'session_id': _randId(),
      'log_id': _randId(),
      'scene_id': _sceneId,
      'game_session_id': _gameSessionId.isEmpty ? _randId() : _gameSessionId,
    };
    sendRaw([0, svc, method, seq, msec, args, comm]);
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(seq);
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! List<int>) return;
    final dynamic decoded;
    try {
      decoded = msgpackUnpack(xxteaDecrypt(raw));
    } catch (_) {
      return;
    }
    if (decoded is! List || decoded.isEmpty) return;
    final msg = decoded.cast<dynamic>();
    final type = msg[0];
    if (type == 1 && msg.length >= 2) {
      // 两种形态：
      //  a) 心跳/ack: [1, seq, ...]（seq 在 index 1）
      //  b) RPC 响应: [1, 服务名, 方法名, seq, ts, 结果]（seq 在 index 3）
      int? seq;
      if (msg[1] is num) {
        seq = (msg[1] as num).toInt();
      } else if (msg.length >= 4 && msg[3] is num) {
        seq = (msg[3] as num).toInt();
      }
      if (seq != null) {
        final c = _pending[seq];
        if (c != null && !c.isCompleted) c.complete(msg);
      }
    } else if (type == 11) {
      // 推送（此处暂不处理）
    }
  }

  void _onDone() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('main connection closed'));
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _channel?.sink.close();
  }
}