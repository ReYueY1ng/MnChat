import 'dart:async';

import '../../models/messages.dart';
import '../../storage/app_database.dart';
import '../../storage/chat_mapper.dart';
import '../../utils/log.dart';

/// 消息/会话的本地持久化（Drift）。纯写库层：不持有内存缓存，只把给定数据
/// 落盘；所有失败仅记日志，绝不阻断消息链路。
///
/// 依赖经构造注入（db、当前账号 uin、好友/群会话表）。
class MessageStore {
  MessageStore({
    required AppDatabase? Function() getDb,
    required int Function() getMyUin,
    required Map<int, ChatSession> friendSessions,
    required Map<int, ChatSession> groupSessions,
  }) : _getDb = getDb,
       _getMyUin = getMyUin,
       _friendSessions = friendSessions,
       _groupSessions = groupSessions;

  final AppDatabase? Function() _getDb;
  final int Function() _getMyUin;
  final Map<int, ChatSession> _friendSessions;
  final Map<int, ChatSession> _groupSessions;

  static const String _logTag = 'MessageStore';

  /// 会话主键：`<type>_<id>`。
  static String sessionKey(ChatSessionType type, int id) => '${type.name}_$id';

  /// 持久化一条消息 + 更新会话行。
  void persistMessage(ChatSessionType type, int id, ChatMessage m) {
    final db = _getDb();
    if (db == null || _getMyUin() == 0) return;
    final key = sessionKey(type, id);
    final owner = _getMyUin();
    unawaited(() async {
      try {
        await db.insertMessage(
          chatMessageToCompanion(m, key, myUin: owner, ownerUin: owner),
        );
      } catch (e) {
        log.error('persist message failed: $e', tag: _logTag);
      }
    }());
    persistSession(type, id);
  }

  /// 持久化会话行（未读/最后消息，按账号隔离）。
  void persistSession(ChatSessionType type, int id) {
    final db = _getDb();
    final owner = _getMyUin();
    if (db == null || owner == 0) return;
    final s = type == ChatSessionType.friend
        ? _friendSessions[id]
        : _groupSessions[id];
    if (s == null) return;
    unawaited(() async {
      try {
        await db.upsertSession(chatSessionToCompanion(s, ownerUin: owner));
      } catch (e) {
        // 写会话行失败必须留痕：schema 与 drift 生成的 ON CONFLICT 不匹配时抛的是
        // 「未捕获的异步异常」，应用侧完全无感 —— 表现就是重启后会话丢失。
        log.error('persist session failed: $e', tag: _logTag);
      }
    }());
  }

  /// 持久化整段历史（先清空该会话旧消息再批量写入，避免重复）。
  void persistHistory(ChatSessionType type, int id, List<ChatMessage> msgs) {
    final db = _getDb();
    if (db == null) return;
    final key = sessionKey(type, id);
    unawaited(replaceHistoryInDb(db, key, msgs));
  }

  /// 原子替换：清空 + 批量写入在一个事务内完成，中途失败不留半写状态。
  Future<void> replaceHistoryInDb(
    AppDatabase db,
    String key,
    List<ChatMessage> msgs,
  ) async {
    final owner = _getMyUin();
    if (owner == 0) return;
    await db.replaceMessages(
      owner,
      key,
      msgs
          .map(
            (m) =>
                chatMessageToCompanion(m, key, myUin: owner, ownerUin: owner),
          )
          .toList(),
    );
  }
}
