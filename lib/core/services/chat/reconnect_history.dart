/// 重连后「哪些会话值得补拉一次离线历史」的纯函数与常量。
///
/// 放在 chat/ 而不是 chat_service.dart：和 reconnect_policy.dart / online_notify.dart
/// 一样，纯逻辑便于单测（不需要 socket、不需要登录）。
///
/// 背景：原先重连成功后会**无条件**串行拉最近 20 个会话的 `buddysvr.chat_query`，
/// 而它是消费式读取 —— 一次重连就是 20 次请求，且撞上网关的账号排队。
library;

import '../../models/messages.dart' show ChatSession;

/// 掉线窗口的宽限：推送到达时间可能略晚于本地记录的 lastMessage 时间。
const Duration kReconnectHistoryGrace = Duration(seconds: 60);

/// 重连补拉的会话数上限。
const int kReconnectHistoryMax = 20;

/// 兜底补拉的最近会话数：服务端没把未读带回来时，至少覆盖最可能漏消息的几个。
const int kReconnectHistoryFallback = 3;

/// 重连补拉的并发批大小（与 session_loader 首屏分批一致）。
const int kReconnectHistoryBatch = 5;

/// 需要补拉历史的会话 id（按最后一条消息时间倒序）。
///
/// 只挑三类：
/// - `unreadCount > 0`：服务端（query_friend_list）已告诉我们有离线消息；
/// - 最后一条消息落在掉线窗口内（[droppedAt] 往前 [kReconnectHistoryGrace]）；
/// - 最近 [kReconnectHistoryFallback] 个会话兜底。
///
/// 没有任何消息的会话不参与（没有历史可补）。最多返回 [kReconnectHistoryMax] 个。
List<int> reconnectHistoryTargets(
  Iterable<ChatSession> sessions,
  DateTime? droppedAt,
) {
  final withMessage = sessions.where((s) => s.lastMessage != null).toList()
    ..sort(
      (a, b) => (b.lastMessage?.time ?? 0).compareTo(a.lastMessage?.time ?? 0),
    );
  if (withMessage.isEmpty) return const <int>[];
  final since = droppedAt == null
      ? null
      : droppedAt.millisecondsSinceEpoch ~/ 1000 -
            kReconnectHistoryGrace.inSeconds;
  final picked = <int>[];
  for (final s in withMessage) {
    final t = s.lastMessage?.time ?? 0;
    if (s.unreadCount > 0 || (since != null && t >= since)) picked.add(s.id);
  }
  for (final s in withMessage.take(kReconnectHistoryFallback)) {
    if (!picked.contains(s.id)) picked.add(s.id);
  }
  return picked.take(kReconnectHistoryMax).toList();
}
