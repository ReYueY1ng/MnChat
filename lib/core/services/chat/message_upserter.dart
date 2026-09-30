import '../../models/messages.dart';
import 'message_store.dart';

/// 内存消息写入：把一条消息 upsert 进会话缓存（去重、未读计数、补建会话），
/// 再落盘、发事件、发快照。并**不**持有缓存本身——缓存与副作用经构造注入。
///
/// 与 [MessageStore]（纯写库）配合：本类只管内存与通知，落盘委托后者。
class MessageUpserter {
  MessageUpserter({
    required Map<String, List<ChatMessage>> messagesCache,
    required Map<int, ChatSession> friendSessions,
    required Map<int, ChatSession> groupSessions,
    required int Function() getMyUin,
    required bool Function(ChatSessionType type, int id) isViewing,
    required void Function(ChatSessionType type, int id, ChatMessage m) emitEvent,
    required MessageStore store,
    required void Function() emitSessionSnapshot,
  }) : _messagesCache = messagesCache,
       _friendSessions = friendSessions,
       _groupSessions = groupSessions,
       _getMyUin = getMyUin,
       _isViewing = isViewing,
       _emitEvent = emitEvent,
       _store = store,
       _emitSessionSnapshot = emitSessionSnapshot;

  final Map<String, List<ChatMessage>> _messagesCache;
  final Map<int, ChatSession> _friendSessions;
  final Map<int, ChatSession> _groupSessions;
  final int Function() _getMyUin;
  final bool Function(ChatSessionType type, int id) _isViewing;
  final void Function(ChatSessionType type, int id, ChatMessage m) _emitEvent;
  final MessageStore _store;
  final void Function() _emitSessionSnapshot;

  /// 内存里每个会话保留的消息条数上限（好友/群）。
  static const int friendMessageCap = 50;
  static const int groupMessageCap = 100;

  /// 同一逻辑消息判定：与 [message_adapter] 的确定性消息 id 一致，
  /// (uin, time, text) 三元组唯一决定一条消息。
  static bool sameMessage(ChatMessage a, ChatMessage b) =>
      a.uin == b.uin && a.time == b.time && a.text == b.text;

  /// 好友消息 upsert。
  void upsertFriend(int uin2, ChatMessage m) {
    final key = MessageStore.sessionKey(ChatSessionType.friend, uin2);
    final list = _messagesCache.putIfAbsent(key, () => []);
    // 去重：乐观本地回显与服务器确认推送是同一逻辑消息（共享 uin/time/text →
    // 同一 id），已存在则跳过（flutter_chat_core 控制器 debug 下断言 id 唯一）。
    if (list.any((e) => sameMessage(e, m))) return;
    list.add(m);
    if (list.length > friendMessageCap) {
      list.removeRange(0, list.length - friendMessageCap);
    }

    final existing = _friendSessions[uin2];
    // 自己发的、或正在查看该会话 → 不计未读。
    final muted = m.uin == _getMyUin() || _isViewing(ChatSessionType.friend, uin2);
    if (existing != null) {
      _friendSessions[uin2] = existing.copyWith(
        lastMessage: m,
        unreadCount: muted ? existing.unreadCount : existing.unreadCount + 1,
      );
    } else {
      // 会话不存在时补建：从好友列表直接进聊天时可能还没有会话对象，若不补建，
      // 消息虽落库却没有 chat_sessions 行 → 重启后该会话不出现（「会话丢失」）。
      // 昵称先用迷你号兜底，登录时会补成真昵称。
      _friendSessions[uin2] = ChatSession(
        id: uin2,
        type: ChatSessionType.friend,
        name: '$uin2',
        lastMessage: m,
        unreadCount: muted ? 0 : 1,
      );
    }
    _emitEvent(ChatSessionType.friend, uin2, m);
    _store.persistMessage(ChatSessionType.friend, uin2, m);
    _emitSessionSnapshot();
  }

  /// 群消息 upsert。
  void upsertGroup(int groupId, ChatMessage m) {
    final key = MessageStore.sessionKey(ChatSessionType.group, groupId);
    final list = _messagesCache.putIfAbsent(key, () => []);
    if (list.any((e) => sameMessage(e, m))) return;
    list.add(m);
    if (list.length > groupMessageCap) {
      list.removeRange(0, list.length - groupMessageCap);
    }

    final existing = _groupSessions[groupId];
    final muted = m.uin == _getMyUin() || _isViewing(ChatSessionType.group, groupId);
    if (existing != null) {
      _groupSessions[groupId] = existing.copyWith(
        lastMessage: m,
        unreadCount: muted ? existing.unreadCount : existing.unreadCount + 1,
      );
    } else if (!muted) {
      _groupSessions[groupId] = ChatSession(
        id: groupId,
        type: ChatSessionType.group,
        name: '群 $groupId',
        lastMessage: m,
        unreadCount: 1,
      );
    }
    _emitEvent(ChatSessionType.group, groupId, m);
    _store.persistMessage(ChatSessionType.group, groupId, m);
    _emitSessionSnapshot();
  }

  /// 整段替换某会话的历史（网络/离线历史拉回时）：升序归位 → 落盘 →
  /// 回填会话摘要 → 发快照 → 通知已打开的聊天窗口刷新。
  void replaceHistory(ChatSessionType type, int id, List<ChatMessage> msgs) {
    if (msgs.isEmpty) return;
    final key = MessageStore.sessionKey(type, id);
    // `buddysvr.chat_query` 只回 `[who, ts, text]` 三元组，**没有 extend_data**：
    // 直接覆盖会把已有的 interCode（动态/互动表情的真身）冲掉，表情就退化回
    // 「请升级到最新版本查看」。所以按 (uin,time,text) 回填已丢失的字段。
    final merged = preserveEmojiFields(msgs, _messagesCache[key]);
    final sorted = sortMessagesAscending(merged);
    _messagesCache[key] = sorted;
    _store.persistHistory(type, id, sorted);
    final map = type == ChatSessionType.friend
        ? _friendSessions
        : _groupSessions;
    final existing = map[id];
    if (existing != null) {
      map[id] = existing.copyWith(lastMessage: sorted.last);
      _store.persistSession(type, id);
    }
    _emitSessionSnapshot();
    // 通知已打开的聊天窗口刷新（复用 ChatEvent：provider 只按 type/id 匹配）。
    _emitEvent(type, id, sorted.last);
  }
}

/// 用旧消息里已有的表情字段，补回新拉到的历史消息上。
///
/// `buddysvr.chat_query` 只回 `[who, ts, text]` 三元组（没有 extend_data），
/// 而动态/互动表情的真身在 `extend_data.interCode` 里 —— 直接整段覆盖会让
/// 收到的表情退化回「请升级到最新版本查看」。这里按 (uin,time,text) 匹配，
/// 把新消息缺的 [ChatMessage.interCode] / [ChatMessage.extendData] 补回来。
///
/// 纯函数，便于单测。
List<ChatMessage> preserveEmojiFields(
  List<ChatMessage> incoming,
  List<ChatMessage>? existing,
) {
  if (existing == null || existing.isEmpty) return incoming;
  final prior = <String, ChatMessage>{};
  for (final m in existing) {
    final hasEmoji =
        (m.interCode ?? '').isNotEmpty || (m.extendData ?? '').isNotEmpty;
    if (hasEmoji) prior['${m.uin}:${m.time}:${m.text}'] = m;
  }
  if (prior.isEmpty) return incoming;

  final out = <ChatMessage>[];
  for (final m in incoming) {
    final prev = prior['${m.uin}:${m.time}:${m.text}'];
    // 新消息自己带了表情字段就别动它。
    if (prev == null || (m.interCode ?? '').isNotEmpty) {
      out.add(m);
      continue;
    }
    out.add(
      m.copyWith(interCode: prev.interCode, extendData: prev.extendData),
    );
  }
  return out;
}
