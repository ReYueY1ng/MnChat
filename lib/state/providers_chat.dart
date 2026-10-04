part of 'providers.dart';

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
