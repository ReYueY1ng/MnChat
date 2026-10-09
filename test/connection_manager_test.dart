// ChatConnectionManager 的建连并发门闩测试。
//
// 回前台的 ensureConnection 与已在排队/在途的重连很容易同时想建连：以前会各发
// 一次 alloc + connect_gate（重复请求 + 多出一条刚建好就被关掉的连接）。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/auth.dart' show MiniAuth;
import 'package:mnchat/core/services/chat/connection_manager.dart';
import 'package:mnchat/core/services/chat_service.dart' show ChatServiceState;
import 'package:mnchat/core/services/chatpush.dart';

/// 假 chatpush：alloc 可被卡住（用来把两次 connect 压在同一个在途窗口里），
/// connect_gate 必然失败（不需要真的 WebSocket）。
class _FakeChatPush extends ChatPushClient {
  _FakeChatPush() : super(dio: Dio());

  final Completer<void> _holdAlloc = Completer<void>();
  bool holdAlloc = false;
  int allocCalls = 0;
  int gateCalls = 0;

  void releaseAlloc() {
    if (!_holdAlloc.isCompleted) _holdAlloc.complete();
  }

  @override
  Future<(String, String)> alloc({
    required int uin,
    required String s2,
    required String s2t,
    required String jwt,
  }) async {
    allocCalls++;
    if (holdAlloc) await _holdAlloc.future;
    return ('host', 'token');
  }

  @override
  Future<ChatPushConnection> connectGate({
    required String host,
    required String token,
    required int uin,
    int apiId = 110,
    String? authToken,
    bool reconnect = false,
    void Function(ChatPushPush)? onPush,
    void Function(ChatPushRpcResult)? onRpc,
    void Function()? onClosed,
  }) async {
    gateCalls++;
    throw ChatPushError('gate down');
  }
}

ChatConnectionManager _manager(_FakeChatPush chatpush) => ChatConnectionManager(
  chatpush: chatpush,
  onStateChange: (_) {},
  onPush: (_) {},
  onReconnected: (_) async {},
  onError: (_) {},
  onConnectionChanged: (_) {},
);

const MiniAuth _auth = MiniAuth(
  uin: 1,
  apiId: 110,
  name: 'Tester',
  s2: 's2',
  s2t: 's2t',
  jwt: 'jwt',
);

void main() {
  group('ChatConnectionManager.connect 并发门闩', () {
    test('并发两次 connect 只发一次 alloc / connect_gate', () async {
      final chatpush = _FakeChatPush()..holdAlloc = true;
      final manager = _manager(chatpush)..auth = _auth;
      addTearDown(manager.close);

      final first = manager.connect();
      final second = manager.connect();
      expect(chatpush.allocCalls, 1, reason: '第二次必须复用第一次在途的建连');

      chatpush.releaseAlloc();
      await Future.wait(<Future<void>>[first, second]);

      expect(chatpush.allocCalls, 1);
      expect(chatpush.gateCalls, 1);
    });

    test('建连结束后门闩释放 → 再次 connect 会重新建连', () async {
      final chatpush = _FakeChatPush();
      final manager = _manager(chatpush)..auth = _auth;
      addTearDown(manager.close);

      await manager.connect();
      expect(chatpush.allocCalls, 1);
      await manager.connect();
      expect(chatpush.allocCalls, 2);
    });

    test('未登录（auth 为 null）不建连', () async {
      final chatpush = _FakeChatPush();
      final manager = _manager(chatpush);
      addTearDown(manager.close);
      await manager.connect();
      expect(chatpush.allocCalls, 0);
    });

    test('连接失败 → 状态仍为 connected（登录已成功）且不进入重连风暴', () async {
      final chatpush = _FakeChatPush();
      final states = <ChatServiceState>[];
      final errors = <String>[];
      final manager = ChatConnectionManager(
        chatpush: chatpush,
        onStateChange: states.add,
        onPush: (_) {},
        onReconnected: (_) async {},
        onError: errors.add,
        onConnectionChanged: (_) {},
      )..auth = _auth;
      addTearDown(manager.close);

      await manager.connect();
      expect(states.last, ChatServiceState.connected);
      expect(errors, hasLength(1));
      expect(chatpush.gateCalls, 1);
      // 从未连上过（hasConnectedOnce = false）→ 不排重连定时器，也不残留掉线时刻。
      expect(manager.shouldReconnect, isFalse);
      expect(manager.lastDroppedAt, isNull);
    });
  });
}
