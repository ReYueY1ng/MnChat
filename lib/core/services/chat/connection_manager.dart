/// ChatConnectionManager —— ChatPush WebSocket 长连接生命周期管理。
///
/// 职责：alloc → connect_gate → 心跳保活 → 断线重连（指数退避）。
/// **不触碰**会话/消息/推送分发逻辑——通过回调通知 [ChatService]。
///
/// 对齐原版 container.lua ChatPushWebSocketConn 的连接管理。
library;

import 'dart:async';

import '../auth.dart';
import '../chatpush.dart';
import '../chat_service.dart' show ChatServiceState;
import 'reconnect_policy.dart';

/// ChatPush 长连接生命周期管理器。
///
/// 通过回调与 [ChatService] 解耦：
/// - [onStateChange]：连接状态变化（connectingChatPush / connected）。
/// - [onPush]：收到推送帧。
/// - [onReconnected]：重连成功后刷新数据（掉线期间的会话/好友/未读）。
/// - [onError]：连接失败时设置 lastError。
/// - [onConnectionChanged]：连接对象变化（供命令客户端同步）。
class ChatConnectionManager {
  ChatConnectionManager({
    required this._chatpush,
    required this._onStateChange,
    required this._onPush,
    required this._onReconnected,
    required this._onError,
    required this._onConnectionChanged,
  });

  final ChatPushClient _chatpush;
  final void Function(ChatServiceState) _onStateChange;
  final void Function(ChatPushPush) _onPush;
  final Future<void> Function(DateTime? droppedAt) _onReconnected;
  final void Function(String) _onError;
  final void Function(ChatPushConnection?) _onConnectionChanged;

  /// 当前 ChatPush 连接（null = 未连接）。
  ChatPushConnection? conn;

  Timer? _reconnectTimer;

  /// 正在进行的建连。并发调用共享它，见 [connect]。
  Future<void>? _connecting;

  /// 上次断开长连接的时刻（[_onClosed] 记录）。重连成功后据此只补拉
  /// 「掉线窗口内有动静」的会话历史（见 `ChatService._refreshAfterReconnect`）。
  DateTime? lastDroppedAt;

  /// 是否应自动重连（登录成功后 true，登出/清理后 false）。
  bool shouldReconnect = false;

  /// 首次连过之后置 true；重连时用于拼 URL 的 &reconnect=1（对齐原版）。
  bool hasConnectedOnce = false;

  /// 重连退避策略：指数增长 + 全抖动（1s base / ×2 / 30s cap）。
  final ReconnectPolicy reconnectPolicy = ReconnectPolicy();

  /// 当前认证状态（login 后设置，reset 后清空）。
  MiniAuth? auth;

  // ── 连接 ────────────────────────────────────────────────────────────────

  /// 建立 ChatPush 长连接（登录 / 重连 / 回前台保活都走它）。
  ///
  /// 已有建连在途时**复用同一个 Future**：回前台的 [ensureConnection] 与重连
  /// 定时器很容易同时想建连，以前会各发一次 `alloc` + `connect_gate` —— 两次重复
  /// 请求，还会多出一条刚建好就被关掉的连接。
  Future<void> connect() {
    final inFlight = _connecting;
    if (inFlight != null) return inFlight;
    final future = _connect().whenComplete(() {
      _connecting = null;
    });
    _connecting = future;
    return future;
  }

  Future<void> _connect() async {
    final a = auth;
    if (a == null) return;
    // 是否为"重连"（此前已连接成功过）：用于重连成功后刷新数据。
    final isReconnect = hasConnectedOnce;
    _onStateChange(ChatServiceState.connectingChatPush);
    try {
      final (host, token) = await _chatpush.alloc(
        uin: a.uin,
        s2: a.s2,
        s2t: a.s2t,
        jwt: a.jwt,
      );
      final connection = await _chatpush.connectGate(
        host: host,
        token: token,
        uin: a.uin,
        authToken: a.jwt, // 握手用（Lua container.conn.token = 登录 jwt）
        reconnect: isReconnect, // 重连时 true → URL &reconnect=1（对齐原版，保留在线态）
        onPush: _onPush,
        onClosed: _onClosed,
      );
      // 保留旧连接并关闭
      final old = conn;
      conn = connection;
      _onConnectionChanged(connection);
      await old?.close();
      hasConnectedOnce = true;
      shouldReconnect = true;
      reconnectPolicy.reset(); // 连接成功 → 退避回到 attempt 0
      _onStateChange(ChatServiceState.connected);
      // 重连成功 → 刷新本地数据：掉线期间的会话/好友/未读离线了，
      // 主动重新拉取一遍，避免"断线重连后收不到之前消息"。
      if (isReconnect) {
        unawaited(_onReconnected(lastDroppedAt));
      }
    } catch (e) {
      _onError('ChatPush connect failed: $e');
      // 登录本身已成功（auth 已获取）：不把状态置为 error，保持 connected，
      // 由后台重连恢复聊天推送——否则 login() 返回成功而 UI 显示失败，
      // 出现状态不一致。
      _onStateChange(ChatServiceState.connected);
      scheduleReconnect();
    }
  }

  /// WS 连接断开：置为需要重连并调度（关键：不重连则账号在游戏端显示离线）。
  void _onClosed() {
    conn = null;
    _onConnectionChanged(null);
    // 记下掉线时刻：重连后只补拉这段时间内有动静的会话历史。
    lastDroppedAt = DateTime.now();
    if (!shouldReconnect) return; // 已在登出/清理中
    scheduleReconnect();
  }

  /// 调度重连（指数退避 + 全抖动）。已有建连在途 / 已排了定时器则不重复排。
  void scheduleReconnect() {
    if (!shouldReconnect ||
        _reconnectTimer?.isActive == true ||
        _connecting != null) {
      return;
    }
    _reconnectTimer = Timer(reconnectPolicy.next(), () {
      if (shouldReconnect) unawaited(connect());
    });
  }

  /// 确保长连接存活：若已断开/无连接则立即重连；连接活跃则强制发一次心跳。
  /// 供生命周期（回前台）与手动保活调用。
  Future<void> ensureConnection() async {
    if (auth == null || !shouldReconnect) return;
    final c = conn;
    if (c == null || c.isClosed) {
      await connect();
    } else {
      c.ping();
    }
  }

  // ── 清理 ────────────────────────────────────────────────────────────────

  /// 关闭连接 + 取消重连定时器（登出 / dispose 时调用）。
  Future<void> close() async {
    shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connecting = null;
    await conn?.close();
    conn = null;
    _onConnectionChanged(null);
  }

  /// 重置全部状态（切换账号时调用）。
  void reset() {
    shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connecting = null;
    lastDroppedAt = null;
    conn = null;
    auth = null;
    hasConnectedOnce = false;
    _onConnectionChanged(null);
  }
}
