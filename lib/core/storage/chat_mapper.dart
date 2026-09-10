/// ChatMessage/ChatSession 模型 ↔ drift 数据表记录 的映射层。
library;

import 'package:drift/drift.dart';

import '../models/messages.dart';
import 'app_database.dart';

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
    name: r.name,
    avatar: r.avatar,
    lastReadTime: r.lastReadTime,
    unreadCount: r.unreadCount,
    lastMessage: (r.lastUin != null && r.lastText != null)
        ? ChatMessage(uin: r.lastUin!, text: r.lastText!, time: r.lastTime)
        : null,
  );
}

/// 会话的存储 key。
String sessionKeyOf(ChatSessionType type, int id) => '${type.name}_$id';

String _sessionKeyOf(ChatSession s) => sessionKeyOf(s.type, s.id);

/// 从 `friend_123` / `group_456` 解析出 id。
int _idFromSessionKey(String key) {
  final idx = key.lastIndexOf('_');
  if (idx < 0) return 0;
  return int.tryParse(key.substring(idx + 1)) ?? 0;
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
    nickname: r.nickname,
    avatar: r.avatar,
    relation: r.relation,
    mark: r.mark,
  );
}