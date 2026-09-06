/// Riverpod 提供者 —— 把 ChatService 暴露给 UI 层。
/// 使用 riverpod 3.x 的 Notifier API（StateNotifier/StateProvider 已在 3.x 移除）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_bridge.dart';
import '../core/models/messages.dart';
import '../core/services/auth.dart';
import '../core/services/chat_service.dart';
import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/settings_store.dart' show SettingsKeys, SettingsStore;

/// ChatService 单例（注入本地 SQLite 用于持久化；main() 中 override databaseProvider）。
final chatServiceProvider = Provider<ChatService>((ref) {
  final db = ref.read(databaseProvider);
  final service = ChatService(db: db);
  ref.onDispose(service.dispose);
  return service;
});

/// ChatBridge 单例（flutter_chat_ui 迁移的桥接层）。
///
/// 持有每个会话的 [ChatController]，订阅 ChatService.eventStream 单一订阅，
/// 把历史增量 reconcile 到控制器。已取代 messageHistoryProvider 的消息显示链路。
final chatBridgeProvider = Provider<ChatBridge>((ref) {
  final service = ref.watch(chatServiceProvider);
  final bridge = ChatBridge(service);
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// AppDatabase 单例（main() 中用 drift_flutter 构建后 override）。
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('AppDatabase must be created in main()'),
);

/// 应用设置存储（自动登录凭据等）单例 —— 基于 Drift 设置表（Web/原生统一）。
final settingsProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.read(databaseProvider)),
);

// ── 认证状态 ─────────────────────────────────────────────────────────────

class AuthState {
  final bool isLoggedIn;
  final MiniAuth? auth;
  final bool isBusy;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.auth,
    this.isBusy = false,
    this.error,
  });
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<ChatServiceState>? _sub;

  @override
  AuthState build() {
    final service = ref.watch(chatServiceProvider);
    _sub ??= service.stateStream.listen((s) => state = _stateFrom(service));
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    // 同步读取 service 当前状态作为初始值：service 可能已处于 connected
    // （如自动登录已发起），只等流事件会漏掉初始态导致 UI 误判未登录。
    return _stateFrom(service);
  }

  AuthState _stateFrom(ChatService service) {
    final s = service.state;
    final loggedIn =
        s == ChatServiceState.connected ||
        s == ChatServiceState.connectingChatPush;
    return AuthState(
      isLoggedIn: loggedIn,
      auth: service.auth,
      isBusy: s == ChatServiceState.authenticating,
      error: s == ChatServiceState.error ? service.lastError : null,
    );
  }

  /// 登录；成功返回 true。
  Future<bool> login({required int uin, required String password}) async {
    final service = ref.read(chatServiceProvider);
    state = const AuthState(isBusy: true);
    try {
      final auth = await service.login(uin: uin, password: password);
      state = AuthState(isLoggedIn: true, auth: auth);
      // 自动登录开启时保存凭据，下次启动免登录
      final settings = ref.read(settingsProvider);
      final autoLogin = await settings.getBool(SettingsKeys.autoLogin);
      if (autoLogin) {
        await settings.saveCredentials(uin, password);
      }
      return true;
    } catch (e) {
      state = AuthState(error: e.toString());
      return false;
    }
  }

  /// 启动自动登录：设置开启且有已存凭据 → 登录。返回是否发起了登录。
  Future<bool> autoLogin() async {
    if (state.isLoggedIn || state.isBusy) return false;
    final settings = ref.read(settingsProvider);
    final enabled = await settings.getBool(SettingsKeys.autoLogin);
    if (!enabled) return false;
    final creds = await settings.loadCredentials();
    if (creds == null) return false;
    await login(uin: creds.uin, password: creds.password);
    return true;
  }

  void logout() {
    final service = ref.read(chatServiceProvider);
    // reset() 是 async：fire-and-forget，出错也交由内部处理，不阻塞登出流程
    unawaited(service.reset());
    state = const AuthState();
  }
}

// ── 当前会话 ─────────────────────────────────────────────────────────────

class ActiveSession {
  final ChatSessionType type;
  final int id;

  const ActiveSession(this.type, this.id);

  @override
  bool operator ==(Object other) =>
      other is ActiveSession && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

final activeSessionProvider =
    NotifierProvider<ActiveSessionNotifier, ActiveSession?>(
      ActiveSessionNotifier.new,
    );

class ActiveSessionNotifier extends Notifier<ActiveSession?> {
  @override
  ActiveSession? build() => null;

  void open(ChatSessionType type, int id) => state = ActiveSession(type, id);
  void close() => state = null;
}

// ── 数据流 ───────────────────────────────────────────────────────────────

/// 会话列表（由 ChatService.sessionStream 驱动）。
final sessionListProvider = StreamProvider<SessionSnapshot>((ref) {
  final service = ref.watch(chatServiceProvider);
  return service.sessionStream;
});

/// 联系人列表。
final contactsProvider = StreamProvider<List<Contact>>((ref) {
  final service = ref.watch(chatServiceProvider);
  return service.sessionStream.map((snap) => snap.contacts);
});

/// 待处理好友申请列表（由 applyed_notify 推送驱动）。
final friendRequestStreamProvider = StreamProvider<List<FriendRequest>>((ref) {
  final service = ref.watch(chatServiceProvider);
  return service.friendRequestStream;
});

/// 待处理好友申请数（红点）。
final friendRequestCountProvider = Provider<int>((ref) {
  ref.watch(friendRequestStreamProvider);
  return ref.watch(chatServiceProvider).friendRequestCount;
});

/// 会话排序方式。
enum SessionSortMode {
  time('time', '按时间'),
  name('name', '按名称'),
  unread('unread', '按未读');

  const SessionSortMode(this.key, this.label);
  final String key;
  final String label;

  static SessionSortMode fromKey(String? k) => SessionSortMode.values
      .firstWhere((m) => m.key == k, orElse: () => SessionSortMode.time);
}

/// 会话排序方式（持久化到设置）。
final sessionSortModeProvider =
    NotifierProvider<SessionSortModeNotifier, SessionSortMode>(
      SessionSortModeNotifier.new,
    );

class SessionSortModeNotifier extends Notifier<SessionSortMode> {
  @override
  SessionSortMode build() {
    // 初始化：从设置读取（异步；provider 可能先被 dispose，用 ref.mounted 保护）
    ref
        .read(settingsProvider)
        .getString(SettingsKeys.sortMode)
        .then((k) {
          if (!ref.mounted) return;
          final m = SessionSortMode.fromKey(k);
          if (m != state) state = m;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return SessionSortMode.time;
  }

  Future<void> setMode(SessionSortMode mode) async {
    state = mode;
    await ref.read(settingsProvider).setString(SettingsKeys.sortMode, mode.key);
  }
}

/// 新消息通知开关（运行时即时生效，持久化到设置）。
final notifyEnabledProvider = NotifierProvider<NotifyEnabledNotifier, bool>(
  NotifyEnabledNotifier.new,
);

class NotifyEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref
        .read(settingsProvider)
        .getBool(SettingsKeys.notifyEnabled, fallback: true)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsProvider).setBool(SettingsKeys.notifyEnabled, value);
  }
}

/// 已登录用户 uin（供聊天页判断消息方向）。
final myUinProvider = Provider<int>((ref) {
  return ref.watch(chatServiceProvider).myUin;
});
