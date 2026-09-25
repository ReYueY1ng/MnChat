import '../../models/messages.dart';
import '../../storage/app_database.dart';
import '../../storage/chat_mapper.dart';
import '../../utils/log.dart';

/// 离线缓存加载：启动时从 SQLite 恢复上次的会话、消息与好友信息（按账号隔离），
/// 让 UI 立即有内容。
///
/// 含两处历史兜底（见行内注释）：库里有消息却无会话行、会话行缺 last_message。
/// 缓存与副作用经构造注入；`loadGroupNames` 用于顺带恢复群名。
class OfflineCache {
  OfflineCache({
    required AppDatabase? Function() getDb,
    required int Function() getMyUin,
    required Map<int, ChatSession> friendSessions,
    required Map<int, ChatSession> groupSessions,
    required List<Contact> contacts,
    required Map<String, List<ChatMessage>> messagesCache,
    required Future<void> Function() loadGroupNames,
    required void Function() emitSessionSnapshot,
  }) : _getDb = getDb,
       _getMyUin = getMyUin,
       _friendSessions = friendSessions,
       _groupSessions = groupSessions,
       _contacts = contacts,
       _messagesCache = messagesCache,
       _loadGroupNames = loadGroupNames,
       _emitSessionSnapshot = emitSessionSnapshot;

  final AppDatabase? Function() _getDb;
  final int Function() _getMyUin;
  final Map<int, ChatSession> _friendSessions;
  final Map<int, ChatSession> _groupSessions;
  final List<Contact> _contacts;
  final Map<String, List<ChatMessage>> _messagesCache;
  final Future<void> Function() _loadGroupNames;
  final void Function() _emitSessionSnapshot;

  static const String _logTag = 'OfflineCache';

  Future<void> load() async {
    final db = _getDb();
    if (db == null) return;
    try {
      final owner = _getMyUin();
      if (owner == 0) return;
      // v6→v7 迁移：把旧数据（ownerUin=0）收养到当前账号，避免升级丢历史
      await db.adoptOrphanData(owner);
      final sessionRows = await db.allSessions(owner);
      // 一次查询全部消息再内存分组，消除逐会话查询的 N+1
      final allMsgs = await db.allMessages(owner);
      final msgsByKey = <String, List<ChatMessageRecord>>{};
      for (final r in allMsgs) {
        msgsByKey.putIfAbsent(r.sessionKey, () => []).add(r);
      }
      for (final r in sessionRows) {
        final s = chatSessionFromRecord(r);
        if (s.type == ChatSessionType.friend) {
          _friendSessions[s.id] = s;
        } else {
          _groupSessions[s.id] = s;
        }
        final key = sessionKeyOf(s.type, s.id);
        final msgRows = msgsByKey[key];
        if (msgRows != null && msgRows.isNotEmpty) {
          // 与 messagesOf 语义一致：升序取最早 200 条
          _messagesCache[key] = msgRows
              .take(200)
              .map(chatMessageFromRecord)
              .toList();
        }
      }
      // 恢复好友信息缓存（昵称/头像/在线/游玩状态）
      final friendRows = await db.allFriends(owner);
      if (friendRows.isNotEmpty) {
        _contacts.clear();
        for (final r in friendRows) {
          _contacts.add(friendFromRecord(r));
          // 若会话尚未恢复（无历史），用好友缓存补建会话，保证列表完整
          final existing = _friendSessions[r.uin];
          if (existing == null) {
            _friendSessions[r.uin] = ChatSession(
              id: r.uin,
              type: ChatSessionType.friend,
              // 缓存昵称可能为空、或被历史插值 bug 写坏成 FriendRecord(...)，
              // 统一净化（见 friendDisplayName），否则坏名字会直接显示出来。
              name: friendDisplayName(r.nickname, r.uin),
              avatar: r.avatar,
              isOnline: r.isOnline,
              gameStatus: r.gameStatus,
              relation: r.relation,
            );
          } else {
            // 净化缓存昵称与已有会话名：空值 / 被写坏的 FriendRecord(...) 都
            // 视为无名字，优先沿用已有会话名，最后回退迷你号。
            final uinText = '${r.uin}';
            final cachedName = friendDisplayName(r.nickname, r.uin);
            final prevName = friendDisplayName(existing.name, r.uin);
            _friendSessions[r.uin] = ChatSession(
              id: existing.id,
              type: existing.type,
              name: cachedName != uinText
                  ? cachedName
                  : (prevName != uinText ? prevName : uinText),
              avatar: r.avatar ?? existing.avatar,
              isOnline: r.isOnline,
              gameStatus: r.gameStatus,
              lastMessage: existing.lastMessage,
              unreadCount: existing.unreadCount,
              lastReadTime: existing.lastReadTime,
              relation: r.relation,
              // 离线缓存里没有 head 字段（表未存），但内存中的旧值要保留。
              headType: existing.headType,
              headId: existing.headId,
              headFrameId: existing.headFrameId,
            );
          }
        }
      }
      // 群名缓存恢复：重启后群聊立刻用真实群名（否则会先闪「群 123456」）
      await _loadGroupNames();
      // 兜底一：库里有消息、却没有对应会话行时，用消息把会话补出来。
      // messages 才是真正的事实来源 —— 历史上出现过「消息写得进、会话行写不进」
      // 的 bug（见 app_database 的迁移说明），这类会话原先在列表里完全看不到。
      for (final entry in msgsByKey.entries) {
        final key = entry.key;
        final rows = entry.value;
        if (rows.isEmpty || _messagesCache.containsKey(key)) continue;
        final sep = key.lastIndexOf('_');
        if (sep <= 0) continue;
        final id = int.tryParse(key.substring(sep + 1));
        if (id == null || id == 0) continue;
        final isGroup = key.substring(0, sep) == ChatSessionType.group.name;
        final msgs = rows.take(200).map(chatMessageFromRecord).toList();
        _messagesCache[key] = msgs;
        final target = isGroup ? _groupSessions : _friendSessions;
        if (target.containsKey(id)) continue;
        // 名字先用迷你号 / 「群 N」兜底，登录后由好友列表、群列表刷新成真名。
        target[id] = ChatSession(
          id: id,
          type: isGroup ? ChatSessionType.group : ChatSessionType.friend,
          name: isGroup ? '群 $id' : '$id',
          lastMessage: msgs.last,
        );
      }
      // 兜底二：会话有本地消息、但会话行的 last_time/last_text 缺失（或会话是刚由
      // 好友缓存补建的）时，用本地最后一条消息补上 —— 否则列表按 lastMessage 排序
      // 会把它排到最后、也不显示消息预览。
      _messagesCache.forEach((key, msgs) {
        if (msgs.isEmpty) return;
        final sep = key.lastIndexOf('_');
        if (sep <= 0) return;
        final id = int.tryParse(key.substring(sep + 1));
        if (id == null || id == 0) return;
        final isGroup = key.substring(0, sep) == ChatSessionType.group.name;
        final target = isGroup ? _groupSessions : _friendSessions;
        final s = target[id];
        if (s == null || s.lastMessage != null) return;
        target[id] = s.copyWith(lastMessage: msgs.last);
      });
      _emitSessionSnapshot();
    } catch (e) {
      log.warn('load offline cache failed: $e', tag: _logTag);
    }
  }
}
