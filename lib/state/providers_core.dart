part of 'providers.dart';

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

/// 应用设置存储（自动登录凭据等）单例 —— 基于 Drift 设置表。
final settingsProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.read(databaseProvider)),
);

