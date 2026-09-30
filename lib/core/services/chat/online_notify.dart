/// 好友上线通知的判定（纯函数，便于单测）。
///
/// 对齐反编译 `friendservice.lua:7618-7624` 的 `DoFriendOnlineNotify`：
/// 只有**离线 → 在线**的跳变、且该好友开了「上线通知」才提醒一次。
library;

import '../../models/messages.dart' show ChatSession, ChatSessionType;

/// 当前在线的好友 uin（群聊不算）。
Set<int> onlineFriendUins(Iterable<ChatSession> sessions) => {
  for (final s in sessions)
    if (s.type == ChatSessionType.friend && s.isOnline) s.id,
};

/// [prev] → [now] 之间**新上线**的好友（离线→在线才有；一直在线不算）。
Set<int> newlyOnlineFriends(Set<int> prev, Set<int> now) =>
    now.difference(prev);
