/// ChatMessage/ChatSession 模型 ↔ drift 数据表记录 的映射层。
library;

import 'package:drift/drift.dart';

import '../models/messages.dart';
import '../models/session_key.dart';
import 'app_database.dart';

/// [sessionKeyOf] 的唯一定义在 `models/session_key.dart`；本文件转出它，
/// `import 'chat_mapper.dart'` 的调用方（如 chat/offline_cache.dart）无需改动。
export '../models/session_key.dart' show sessionKeyOf;

/// ChatMessage → ChatMessagesCompanion（插入用）。
/// [sessionKey] 如 `friend_123` / `group_456`。
/// [myUin] 用于判断消息方向：`out`（我发出）vs `in`（对方发出）。
ChatMessagesCompanion chatMessageToCompanion(
  ChatMessage m,
  String sessionKey, {
  required int myUin,
  int ownerUin = 0,
}) {
  return ChatMessagesCompanion(
    sessionKey: Value(sessionKey),
    uin: Value(m.uin),
    content: Value(m.text),
    time: Value(m.time),
    extendData: Value(m.extendData),
    isSuccess: Value(m.isSuccess),
    notTime: Value(m.notTime),
    srcUserVersion: Value(m.srcUserVersion),
    bubble: Value(m.bubble),
    interCode: Value(m.interCode),
    groupId: Value(m.groupId),
    isSystemMsg: Value(m.isSystemMsg),
    isTime: Value(m.isTime),
    direction: Value(m.uin == myUin ? 'out' : 'in'),
    msgType: Value(m.type.name),
    ownerUin: Value(ownerUin),
  );
}

/// ChatMessageRecord → ChatMessage。
ChatMessage chatMessageFromRecord(ChatMessageRecord r) {
  return ChatMessage(
    uin: r.uin,
    text: r.content,
    time: r.time,
    extendData: r.extendData,
    isSuccess: r.isSuccess,
    notTime: r.notTime,
    srcUserVersion: r.srcUserVersion,
    bubble: r.bubble,
    interCode: r.interCode,
    groupId: r.groupId,
    isSystemMsg: r.isSystemMsg,
    isTime: r.isTime,
    type: chatMsgTypeFrom(r.msgType),
  );
}

/// ChatSession → ChatSessionsCompanion（插入用）。
ChatSessionsCompanion chatSessionToCompanion(ChatSession s, {int ownerUin = 0}) {
  return ChatSessionsCompanion(
    sessionKey: Value(_sessionKeyOf(s)),
    typeId: Value(s.type == ChatSessionType.group ? 1 : 0),
    name: Value(s.name),
    avatar: Value(s.avatar),
    lastTime: Value(s.lastMessage?.time ?? 0),
    lastReadTime: Value(s.lastReadTime),
    unreadCount: Value(s.unreadCount),
    lastUin: Value(s.lastMessage?.uin),
    lastText: Value(s.lastMessage?.text),
    ownerUin: Value(ownerUin),
  );
}

/// ChatSessionRecord → ChatSession。
ChatSession chatSessionFromRecord(ChatSessionRecord r) {
  final type = r.typeId == 1 ? ChatSessionType.group : ChatSessionType.friend;
  final id = _idFromSessionKey(r.sessionKey);
  return ChatSession(
    id: id,
    type: type,
    // 好友会话名同样净化历史坏数据（见 [friendDisplayName]）；群名不动。
    name: type == ChatSessionType.friend ? friendDisplayName(r.name, id) : r.name,
    avatar: r.avatar,
    lastReadTime: r.lastReadTime,
    unreadCount: r.unreadCount,
    lastMessage: (r.lastUin != null && r.lastText != null)
        ? ChatMessage(uin: r.lastUin!, text: r.lastText!, time: r.lastTime)
        : null,
  );
}

String _sessionKeyOf(ChatSession s) => sessionKeyOf(s.type, s.id);

/// 从 `friend_123` / `group_456` 解析出 id。
int _idFromSessionKey(String key) {
  final idx = key.lastIndexOf('_');
  if (idx < 0) return 0;
  return int.tryParse(key.substring(idx + 1)) ?? 0;
}

/// 好友显示名净化：缓存昵称来自 SQLite（好友表 / 会话表），历史上出现过
/// 插值 bug（`'$r.uin'` 把整个 Drift 记录拼进字符串），库里已落下一部分
/// `FriendRecord(...)` 字面量。读取时统一处理：
/// - 昵称为空、或形如 `FriendRecord(` 的记录字面量 → 回退为迷你号字符串；
/// - 其余原样返回。
/// 注意：不修库、不加迁移；净化只发生在读取路径（下次 [_saveFriendCache]
/// 会用净化后的值覆盖回写，坏数据自然消失）。
String friendDisplayName(String cachedName, int uin) {
  final name = cachedName.trim();
  if (name.isEmpty || name.startsWith('FriendRecord(')) return '$uin';
  return cachedName;
}

/// Contact → FriendRecord（入库用，记录拉取时间）。
FriendRecord friendToRecord(
  Contact c, {
  required int updatedAt,
  bool isOnline = false,
  String? gameStatus,
  int ownerUin = 0,
}) {
  return FriendRecord(
    uin: c.uin,
    nickname: c.nickname,
    avatar: c.avatar,
    isOnline: isOnline,
    gameStatus: gameStatus,
    updatedAt: updatedAt,
    relation: c.relation,
    mark: c.mark,
    ownerUin: ownerUin,
  );
}

/// FriendRecord → Contact。
Contact friendFromRecord(FriendRecord r) {
  return Contact(
    uin: r.uin,
    // 净化历史坏数据（见 [friendDisplayName]）。
    nickname: friendDisplayName(r.nickname, r.uin),
    avatar: r.avatar,
    relation: r.relation,
    mark: r.mark,
  );
}