/// ChatPush 分配 + WebSocket 长连接 + 消息推送分发。
/// 移植自 MNClient `account/chatpush.py` + `net/rpcconn.py` _chatpush_recv_loop
/// + 反编译源码 container.lua ChatPushWebSocketConn 的 msg_type==11 推送处理。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/chatpush_cipher.dart' show chatpushDecrypt, chatpushEncrypt;
import '../crypto/md5_sign.dart' show chatpushAuthKey, md5Sign, md5Token;
import '../net/config.dart';
import '../net/http_factory.dart';
import '../net/msgpack.dart' show chatpushJsonDecode;

/// ChatPush 下行推送事件。
class ChatPushPush {
  /// 服务名，如 `friend` / `buddysvr`。
  final String service;

  /// 方法名，如 `msg` / `speek`。
  final String method;

  /// 推送参数（列表，展开为参数）。
  final List<dynamic> args;

  const ChatPushPush(this.service, this.method, this.args);

  String get eventName => '$service.$method';
}

/// ChatPush RPC 响应（由 seq 匹配）。
class ChatPushRpcResult {
  final int seq;
  final int code;
  final dynamic result;
  final dynamic other;

  const ChatPushRpcResult(this.seq, this.code, this.result, this.other);
}

class ChatPushError implements Exception {
  final String message;
  ChatPushError(this.message);
  @override
  String toString() => 'ChatPushError: $message';
}

/// ChatPush 客户端：alloc → connect_gate → RPC + 推送接收。
class ChatPushClient {
  final String _lbUrl;
  final Dio _dio;

  static const String kProdLb = 'https://chatpush.mini1.cn:19602';

  ChatPushClient({int env = 0, String? lbUrl, Dio? dio})
    : _lbUrl =
          lbUrl ??
          (kIsWeb ? backendChatpush(env) : (kChatpushLbUrls[env] ?? kProdLb)),
      _dio = dio ?? createDio();

  // ── alloc ─────────────────────────────────────────────────────────────

  /// POST `{lb}/minilb/alloc` 用 rotate-XOR 加密参数，返回 (host, token)。
  Future<(String, String)> alloc({
    required int uin,
    required String s2,
    required String s2t,
    required String jwt,
  }) async {
    final timeVal = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final auth = md5Sign([timeVal.toString(), chatpushAuthKey, uin.toString()]);
    final loginauth = md5Token(timeVal, s2, uin);

    final params = <String, Object?>{
      'flag': 1,
      'uid': uin,
      'time': timeVal,
      'auth': auth,
      'loginauth': loginauth,
      's2t': s2t,
    };
    final body = _encode(params);
    final url = '$_lbUrl/minilb/alloc';

    final resp = await _dio.post(url, data: body);
    final Map<String, Object?> data;
    try {
      data = ((jsonDecode(resp.data as String) as Map).cast<String, Object?>());
    } on FormatException {
      throw ChatPushError('alloc: invalid JSON: ${resp.data}');
    }
    if (data['code'] != 0) {
      throw ChatPushError('alloc failed: code=${data['code']}');
    }
    final d = (data['data'] as Map).cast<String, Object?>();
    return (d['host'] as String, d['token'] as String);
  }

  /// 编码：params → JSON → chatpush_encrypt → **标准 base64** → url-encode。
  /// Python chatpush.py:_encode: json.dumps(separators=(",",":")) → chatpush_encrypt
  /// → base64.b64encode → urllib.parse.quote(safe="")。
  static String _encode(Map<String, Object?> params) {
    final jsonBytes = utf8.encode(jsonEncode(params));
    final encrypted = chatpushEncrypt(jsonBytes);
    final b64 = base64Encode(encrypted);
    return Uri.encodeComponent(b64);
  }

  /// HTTP 后备 RPC（对齐反编译源码 managerbase.lua `chatpush_rpc`）。
  ///
  /// WS 长连接不可用时使用：POST `{lb}/minilb/rpc?uid&time&auth&loginauth&s2t`。
  /// 关键差异（vs WS）：auth = md5(time + key + uin + extdata) **包含 extdata**。
  ///
  /// [args] 与 WS 通道一致，如 `['svc','method',seq,msec,args,{}]`。
  /// 返回解码后的数组（chatpush_decrypt(JSON)）。
  Future<List<dynamic>> rpcHttp({
    required int uin,
    required String s2,
    required String s2t,
    required List<dynamic> message,
  }) async {
    final timeVal = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final jsonBytes = utf8.encode(jsonEncode(message));
    final enc = chatpushEncrypt(jsonBytes);
    final b64 = base64Encode(enc);
    final extdata = Uri.encodeComponent(b64);

    final loginauth = md5Token(timeVal, s2, uin);
    final auth = md5Sign([
      timeVal.toString(),
      chatpushAuthKey,
      uin.toString(),
      extdata,
    ]);

    final url =
        '$_lbUrl/minilb/rpc'
        '?uid=$uin&time=$timeVal&auth=$auth&loginauth=$loginauth&s2t=$s2t';
    final resp = await _dio.post(url, data: extdata);
    final text = resp.data.toString();
    try {
      final decrypted = chatpushDecrypt(base64Decode(text));
      final decoded = jsonDecode(utf8.decode(decrypted));
      if (decoded is List) return decoded;
      return [decoded];
    } catch (e) {
      throw ChatPushError(
        'rpcHttp decode failed: $e (raw=${text.substring(0, text.length > 60 ? 60 : text.length)})',
      );
    }
  }

  // ── Gate 连接 ───────────────────────────────────────────────────────────

  /// 建立 WebSocket 长连接并启动接收循环。
  /// [onPush] 收到 msg_type==11 推送时回调；[onRpc] 收到 RPC 响应时回调。
  /// 对齐 container.lua `onStateChange READYSTATE_OPEN`：连接打开后必须立即
  /// 发送 `{21, conn.token}`（rotate-XOR 加密）作为握手认证，否则服务器秒断。
  Future<ChatPushConnection> connectGate({
    required String host,
    required String token,
    required int uin,
    int apiId = 110,
    String? authToken, // 握手用（登录返回的 jwt；Lua = container.conn.token）
    bool reconnect = false, // 重连时 true → URL 追加 &reconnect=1（对齐原版，保留在线态）
    void Function(ChatPushPush)? onPush,
    void Function(ChatPushRpcResult)? onRpc,
    VoidCallback? onClosed,
  }) async {
    final timeVal = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final auth = md5Sign([timeVal.toString(), chatpushAuthKey, uin.toString()]);
    final reconnectParam = reconnect ? '&reconnect=1' : '';
    final uri = Uri.parse(
      'ws://$host/minigate/gate?uid=$uin&token=$token&time=$timeVal&auth=$auth&cltversion=$kCltVersion&apiid=$apiId$reconnectParam',
    );
    final channel = WebSocketChannel.connect(uri);
    return ChatPushConnection(
      channel,
      authToken: authToken,
      onPush: onPush,
      onRpc: onRpc,
      onClosed: onClosed,
    );
  }
}

/// 管理一条 ChatPush 长连接；内部处理接收循环 + 推送 ack + RPC 匹配。
class ChatPushConnection {
  final WebSocketChannel _channel;
  final void Function(ChatPushPush)? onPush;
  final void Function(ChatPushRpcResult)? onRpc;

  /// 连接关闭/断开时回调（供上层触发自动重连）。
  final VoidCallback? onClosed;

  bool _closed = false;

  final Map<int, Completer<ChatPushRpcResult>> _pending = {};
  final Set<String> _recvedOk = <String>{};
  static const int _kMaxRecvedOk = 1000;
  int _seq = 0;
  StreamSubscription? _sub;
  Timer? _heartbeat;

  ChatPushConnection(
    this._channel, {
    this.authToken,
    this.onPush,
    this.onRpc,
    this.onClosed,
  }) {
    _seq = DateTime.now().microsecondsSinceEpoch % 100000;
    _sub = _channel.stream.listen(_onMessage, onDone: _onDone, onError: (_) {});
    _heartbeat = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _sendHeartbeat(),
    );
    // 连接打开 → 立即发 {21, authToken} 握手（container.lua:1290-1297）
    _sendHandshake();
  }

  /// 是否已断开。
  bool get isClosed => _closed;

  /// 强制发一次心跳（保活/重置服务器侧活跃状态）。
  void ping() => _sendHeartbeat();

  /// 登录返回的 jwt（Lua container.conn.token）。null 时跳过握手。
  final String? authToken;

  void _sendHandshake() {
    final t = authToken;
    if (t == null) return;
    try {
      _channel.sink.add(
        chatpushEncrypt(utf8.encode(jsonEncode(<dynamic>[21, t]))),
      );
    } catch (_) {
      // 连接未就绪时忽略（后续心跳/RPC 会重试建立）
    }
  }

  int _nextSeq() {
    _seq = (_seq + 1) % 100000000;
    return _seq;
  }

  /// 服务器将 seq 序列化为 String，统一转 int（失败返回 -1）。
  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? -1;
  }

  /// RPC 请求（JSON + rotate-XOR 编码），返回响应 Future。
  Future<ChatPushRpcResult> sendRpc(
    String svc,
    String method,
    List<dynamic> args, {
    Duration timeout = const Duration(seconds: 15),
    Map<String, Object?>? commParam,
  }) async {
    final seq = _nextSeq();
    final msec = DateTime.now().millisecondsSinceEpoch % 100000000;
    final comm =
        commParam ??
        <String, Object?>{
          'session_id': _randId(),
          'log_id': _randId(),
          'scene_id': '0',
          'game_session_id': '',
        };
    final msg = <dynamic>[0, svc, method, seq, msec, args, comm];
    final completer = Completer<ChatPushRpcResult>();
    _pending[seq] = completer;
    _channel.sink.add(chatpushEncrypt(utf8.encode(jsonEncode(msg))));
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(seq);
    }
  }

  /// 随机 32 位 hex（对齐游戏 log_id/session_id 等）。
  String _randId() {
    final rnd = Random();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  void _sendHeartbeat() {
    final seq = _nextSeq();
    _channel.sink.add(
      chatpushEncrypt(utf8.encode(jsonEncode(<dynamic>[0, seq]))),
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! List<int>) return;
    final List<dynamic> msg;
    try {
      msg = chatpushJsonDecode(utf8.decode(chatpushDecrypt(raw)));
    } catch (_) {
      return;
    }
    if (msg.isEmpty) return;
    final msgType = msg[0] is int
        ? msg[0] as int
        : int.tryParse('${msg[0]}') ?? -1;

    if (msgType == 1 && msg.length >= 4) {
      // 两种 RPC 响应形态：
      //  a) [1, seq, code, result, other]（seq 在 index 1）
      //  b) [1, service, method, seq, ts, result]（buddy 等 usechatpush 方法，seq 在 index 3）
      int seq;
      int code;
      dynamic result;
      dynamic other;
      if (msg[1] is num) {
        seq = _toInt(msg[1]);
        code = _toInt(msg[2]);
        result = msg.length > 3 ? msg[3] : null;
        other = msg.length > 4 ? msg[4] : null;
      } else {
        seq = _toInt(msg[3]);
        code = 0;
        result = msg.length > 5 ? msg[5] : (msg.length > 4 ? msg[4] : null);
        other = null;
      }
      final completer = _pending[seq];
      if (completer != null && !completer.isCompleted) {
        completer.complete(ChatPushRpcResult(seq, code, result, other));
      } else {
        onRpc?.call(ChatPushRpcResult(seq, code, result, other));
      }
      return;
    }

    if (msgType == 0 && msg.length >= 3) {
      // 心跳 ack: [0, seq, svrtime_delta] → 回 [1, seq]
      final seq = _toInt(msg[1]);
      final completer = _pending[seq];
      if (completer != null && !completer.isCompleted) {
        completer.complete(ChatPushRpcResult(seq, 0, msg[2], null));
      }
      _channel.sink.add(
        chatpushEncrypt(utf8.encode(jsonEncode(<dynamic>[1, seq]))),
      );
      return;
    }

    // msg_type == 11: 服务端下行推送
    // 帧结构 (0-indexed): [0]=msg_type, [1]=servicename, [2]=methodname,
    //                     [3]=seq, [4]=ts, [5]=args_or_result
    // Lua (1-indexed): msg_type, msgseq = msg[1], msg[4] → 对应 [0] 和 [3]
    if (msgType == 11 && msg.length >= 2) {
      final msgSeq = msg.length > 3 ? '${msg[3]}' : '';
      _channel.sink.add(
        chatpushEncrypt(utf8.encode(jsonEncode(<dynamic>[11, msgSeq]))),
      );
      final baseSeq = msgSeq.split('_').isEmpty ? '' : msgSeq.split('_').first;
      if (baseSeq.isNotEmpty) {
        if (_recvedOk.contains(baseSeq)) return;
        _recvedOk.add(baseSeq);
        if (_recvedOk.length > _kMaxRecvedOk) {
          _truncateRecvedOk();
        }
      }
      if (msg.length >= 6) {
        final service = msg[1]?.toString() ?? '';
        final methodName = msg[2]?.toString() ?? '';
        final args = (msg[5] is List) ? msg[5] as List<dynamic> : [msg[5]];
        onPush?.call(ChatPushPush(service, methodName, args));
      }
      return;
    }
  }

  void _onDone() {
    _closed = true;
    _heartbeat?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(ChatPushError('connection closed'));
    }
    onClosed?.call();
  }

  void _truncateRecvedOk() {
    if (_recvedOk.length <= _kMaxRecvedOk) return;
    final all = _recvedOk.toList();
    // Keep only the newest _kMaxRecvedOk entries (LinkedHashSet preserves insertion order).
    _recvedOk.clear();
    _recvedOk.addAll(all.sublist(all.length - _kMaxRecvedOk));
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    await _sub?.cancel();
    await _channel.sink.close();
  }
}
