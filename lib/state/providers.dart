/// Riverpod 提供者 —— 把 ChatService 暴露给 UI 层。
/// 使用 riverpod 3.x 的 Notifier API（StateNotifier/StateProvider 已在 3.x 移除）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../core/services/auth.dart';
import '../core/services/chat_service.dart';
import '../core/storage/app_database.dart' show AppDatabase;

/// ChatService 单例（注入本地 SQLite 用于持久化；main() 中 override databaseProvider）。
final chatServiceProvider = Provider<ChatService>((ref) {
  final db = ref.read(databaseProvider);
  final service = ChatService(db: db);
  ref.onDispose(service.dispose);
  return service;
});

/// AppDatabase 单例（main() 中用 drift_flutter 构建后 override）。
final databaseProvider = Provider<AppDatabase>(
    (ref) => throw UnimplementedError('AppDatabase must be created in main()'));

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

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<ChatServiceState>? _sub;

  @override
  AuthState build() {
    final service = ref.watch(chatServiceProvider);
    _sub ??= service.stateStream.listen((s) {
      final loggedIn = s == ChatServiceState.connected ||
          s == ChatServiceState.connectingChatPush;
      state = AuthState(
        isLoggedIn: loggedIn,
        auth: service.auth,
        isBusy: s == ChatServiceState.authenticating,
        error: s == ChatServiceState.error ? service.lastError : null,
      );
    });
    ref.onDispose(() => _sub?.cancel());
    return const AuthState();
  }

  /// 登录；成功返回 true。
  Future<bool> login({required int uin, required String password}) async {
    final service = ref.read(chatServiceProvider);
    state = const AuthState(isBusy: true);
    try {
      final auth = await service.login(uin: uin, password: password);
      state = AuthState(isLoggedIn: true, auth: auth);
      return true;
    } catch (e) {
      state = AuthState(error: e.toString());
      return false;
    }
  }

  void logout() {
    state = const AuthState();
  }
}

// ── 当前会话 ─────────────────────────────────────────────────────────────

class ActiveSession {
  final ChatSessionType type;
  final int id;

  const ActiveSession(this.type, this.id);
}

final activeSessionProvider = NotifierProvider<ActiveSessionNotifier, ActiveSession?>(
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

/// 指定会话的消息历史。
final messageHistoryProvider =
    StreamProvider.family<List<ChatMessage>, ActiveSession>((ref, key) async* {
  final service = ref.watch(chatServiceProvider);
  yield service.historyOf(key.type, key.id);
  await for (final event in service.eventStream) {
    if (event.sessionType == key.type && event.sessionId == key.id) {
      yield service.historyOf(key.type, key.id);
    }
  }
});

/// 联系人列表。
final contactsProvider = StreamProvider<List<Contact>>((ref) {
  final service = ref.watch(chatServiceProvider);
  return service.sessionStream.map((snap) => snap.contacts);
});

/// 已登录用户 uin（供聊天页判断消息方向）。
final myUinProvider = Provider<int>((ref) {
  return ref.watch(chatServiceProvider).myUin;
});