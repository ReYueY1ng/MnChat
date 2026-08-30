/// ChatPush 分配 + WebSocket 长连接 + 消息推送分发。
/// 移植自 MNClient `account/chatpush.py` + `net/rpcconn.py` _chatpush_recv_loop
/// + 反编译源码 container.lua ChatPushWebSocketConn 的 msg_type==11 推送处理。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/chatpush_cipher.dart' show chatpushDecrypt, chatpushEncrypt;
import '../crypto/md5_sign.dart' show chatpushAuthKey, md5Sign, md5Token;
import '../net/config.dart';
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
      : _lbUrl = lbUrl ?? kChatpushLbUrls[env] ?? kProdLb,
        _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

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

  // ── Gate 连接 ───────────────────────────────────────────────────────────

  /// 建立 WebSocket 长连接并启动接收循环。
  /// [onPush] 收到 msg_type==11 推送时回调；[onRpc] 收到 RPC 响应时回调。
  Future<ChatPushConnection> connectGate({
    required String host,
    required String token,
    required int uin,
    int apiId = 110,
    void Function(ChatPushPush)? onPush,
    void Function(ChatPushRpcResult)? onRpc,
  }) async {
    final timeVal = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final auth = md5Sign([timeVal.toString(), chatpushAuthKey, uin.toString()]);
    final uri = Uri.parse(
        'ws://$host/minigate/gate?uid=$uin&token=$token&time=$timeVal&auth=$auth&cltversion=$kCltVersion&apiid=$apiId');
    final channel = WebSocketChannel.connect(uri);
    return ChatPushConnection(
      channel,
      onPush: onPush,
      onRpc: onRpc,
    );
  }
}

/// 管理一条 ChatPush 长连接；内部处理接收循环 + 推送 ack + RPC 匹配。
class ChatPushConnection {
  final WebSocketChannel _channel;
  final void Function(ChatPushPush)? onPush;
  final void Function(ChatPushRpcResult)? onRpc;

  final Map<int, Completer<ChatPushRpcResult>> _pending = {};
  final Set<String> _recvedOk = {};
  int _seq = 0;
  StreamSubscription? _sub;
  Timer? _heartbeat;

  ChatPushConnection(this._channel, {this.onPush, this.onRpc}) {
    _seq = DateTime.now().microsecondsSinceEpoch % 100000;
    _sub = _channel.stream.listen(_onMessage, onDone: _onDone, onError: (_) {});
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _sendHeartbeat());
  }

  int _nextSeq() {
    _seq = (_seq + 1) % 100000000;
    return _seq;
  }

  /// RPC 请求（JSON + rotate-XOR 编码），返回响应 Future。
  Future<ChatPushRpcResult> sendRpc(
      String svc, String method, List<dynamic> args,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final seq = _nextSeq();
    final msec = DateTime.now().millisecondsSinceEpoch % 100000000;
    final msg = <dynamic>[0, svc, method, seq, msec, args, <String, Object?>{}];
    final completer = Completer<ChatPushRpcResult>();
    _pending[seq] = completer;
    _channel.sink.add(chatpushEncrypt(utf8.encode(jsonEncode(msg))));
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(seq);
    }
  }

  void _sendHeartbeat() {
    final seq = _nextSeq();
    _channel.sink.add(chatpushEncrypt(utf8.encode(jsonEncode(<dynamic>[0, seq]))));
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
    final msgType = msg[0] as int;

    if (msgType == 1 && msg.length >= 4) {
      // RPC 响应: [1, seq, code, result, other]
      final seq = msg[1] as int? ?? -1;
      final code = msg[2] as int? ?? -1;
      final result = msg.length > 3 ? msg[3] : null;
      final other = msg.length > 4 ? msg[4] : null;
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
      final seq = msg[1] as int? ?? -1;
      final completer = _pending[seq];
      if (completer != null && !completer.isCompleted) {
        completer.complete(ChatPushRpcResult(seq, 0, msg[2], null));
      }
      _channel.sink.add(chatpushEncrypt(utf8.encode(jsonEncode(<dynamic>[1, seq]))));
      return;
    }

    // msg_type == 11: 服务端下行推送
    // 帧结构 (0-indexed): [0]=msg_type, [1]=servicename, [2]=methodname,
    //                     [3]=seq, [4]=ts, [5]=args_or_result
    // Lua (1-indexed): msg_type, msgseq = msg[1], msg[4] → 对应 [0] 和 [3]
    if (msgType == 11 && msg.length >= 2) {
      final msgSeq = msg.length > 3 ? '${msg[3]}' : '';
      // 回 ack {msg_type, msgseq} 告诉服务器已收到
      _channel.sink.add(chatpushEncrypt(utf8.encode(jsonEncode(<dynamic>[11, msgSeq]))));
      final baseSeq = msgSeq.split('_').isEmpty ? '' : msgSeq.split('_').first;
      if (baseSeq.isNotEmpty) {
        if (_recvedOk.contains(baseSeq)) return;
        _recvedOk.add(baseSeq);
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
    _heartbeat?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(ChatPushError('connection closed'));
    }
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    await _sub?.cancel();
    await _channel.sink.close();
  }
}