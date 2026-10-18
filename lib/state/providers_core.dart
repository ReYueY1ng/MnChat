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
///
/// 同时挂上「本机删除」过滤：标记里属于 hidden 的消息不进控制器（服务端仍有
/// 这条消息，只是本机不显示）。
final chatBridgeProvider = Provider<ChatBridge>((ref) {
  final service = ref.watch(chatServiceProvider);
  final marks = ref.watch(messageMarksStoreProvider);
  final bridge = ChatBridge(service, hiddenKeys: marks.hiddenKeysOf);
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// 本机消息标记（收藏 / 本机删除）的内存镜像。
///
/// 数据库经闭包惰性读取：测试环境未 override databaseProvider 时它是一个
/// 会抛的 provider，这里吞掉并返回 null —— 标记功能整体静默降级，不影响
/// 其它测试。
final messageMarksStoreProvider = Provider<MessageMarksStore>((ref) {
  return MessageMarksStore(
    getDb: () {
      try {
        return ref.read(databaseProvider);
      } catch (_) {
        return null;
      }
    },
    getMyUin: () => ref.read(myUinProvider),
  );
});

/// AppDatabase 单例（main() 中用 drift_flutter 构建后 override）。
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('AppDatabase must be created in main()'),
);

/// 应用设置存储（自动登录凭据等）单例 —— 基于 Drift 设置表。
final settingsProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.read(databaseProvider)),
);

