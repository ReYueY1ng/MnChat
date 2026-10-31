import 'dart:async';

import '../../models/messages.dart';
import '../../storage/app_database.dart';
import '../../storage/chat_mapper.dart';
import '../../utils/log.dart';

/// 历史分页游标：内存里最老一条消息的 `(时间, 数据库行 id)`。
///
/// 只用 time 作游标会在同一秒内的多条消息上跳/重，必须带上自增 id。
typedef HistoryCursor = ({int time, int id});

/// 消息/会话的本地持久化（Drift）。纯写库层：不持有内存缓存，只把给定数据
/// 落盘；所有失败仅记日志，绝不阻断消息链路。
///
/// 依赖经构造注入（db、当前账号 uin、好友/群会话表）。
class MessageStore {
  MessageStore({
    required this._getDb,
    required this._getMyUin,
    required this._friendSessions,
    required this._groupSessions,
  });

  final AppDatabase? Function() _getDb;
  final int Function() _getMyUin;
  final Map<int, ChatSession> _friendSessions;
  final Map<int, ChatSession> _groupSessions;

  static const String _logTag = 'MessageStore';

  /// 串行写队列：所有落库操作排在同一条 Future 链上。
  ///
  /// 旧实现是每条消息一个 `unawaited(async {...})`，多条消息并发时 SQLite 的
  /// 执行顺序不保证，后入队的旧会话快照可能覆盖新快照（未读数/最后一条回退）。
  /// 串行化后写入顺序 = 调用顺序。
  Future<void> _chain = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _chain.then((_) => op());
    // 队列本身不能因为某次写入失败而断掉；错误由各 op 自己记日志。
    _chain = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  /// 等待当前队列写完（测试 / 登出前使用）。
  Future<void> flush() => _chain;

  /// 会话主键：`<type>_<id>`。格式定义见 [sessionKeyOf]（models/session_key.dart）。
  static String sessionKey(ChatSessionType type, int id) => sessionKeyOf(type, id);

  /// 持久化一条消息 + 更新会话行。
  void persistMessage(ChatSessionType type, int id, ChatMessage m) {
    final db = _getDb();
    final owner = _getMyUin();
    if (db == null || owner == 0) return;
    final key = sessionKey(type, id);
    final row = chatMessageToCompanion(m, key, myUin: owner, ownerUin: owner);
    unawaited(_serial(() async {
      try {
        // 幂等：同一逻辑消息（推送重放/重启恢复）只落一行。
        await db.insertMessageIdempotent(row);
      } catch (e) {
        log.error('persist message failed: $e', tag: _logTag);
      }
    }));
    persistSession(type, id);
  }

  /// 持久化会话行（未读/最后消息，按账号隔离）。
  void persistSession(ChatSessionType type, int id) {
    final db = _getDb();
    final owner = _getMyUin();
    if (db == null || owner == 0) return;
    unawaited(_serial(() async {
      try {
        // 在队列里再取快照：入队后到达的新消息会体现在这次写入里，
        // 而不是让先前的旧快照后落盘。
        final s = type == ChatSessionType.friend
            ? _friendSessions[id]
            : _groupSessions[id];
        if (s == null) return;
        await db.upsertSession(chatSessionToCompanion(s, ownerUin: owner));
      } catch (e) {
        // 写会话行失败必须留痕：schema 与 drift 生成的 ON CONFLICT 不匹配时抛的是
        // 「未捕获的异步异常」，应用侧完全无感 —— 表现就是重启后会话丢失。
        log.error('persist session failed: $e', tag: _logTag);
      }
    }));
  }

  /// 把失败回显标回成功（发件箱重试成功后）。
  void markSent(
    ChatSessionType type,
    int id, {
    required int time,
    required String text,
  }) {
    final db = _getDb();
    final owner = _getMyUin();
    if (db == null || owner == 0) return;
    final key = sessionKey(type, id);
    unawaited(_serial(() async {
      try {
        await db.markMessageSuccess(
          owner,
          key,
          uin: owner,
          time: time,
          content: text,
        );
      } catch (e) {
        log.error('mark message success failed: $e', tag: _logTag);
      }
    }));
  }

  /// 持久化整段历史：增量合并（插缺行、删多余行），不再整段重写。
  void persistHistory(ChatSessionType type, int id, List<ChatMessage> msgs) {
    final db = _getDb();
    if (db == null) return;
    final key = sessionKey(type, id);
    final owner = _getMyUin();
    if (owner == 0) return;
    final rows = msgs
        .map((m) => chatMessageToCompanion(m, key, myUin: owner, ownerUin: owner))
        .toList();
    unawaited(_serial(() async {
      try {
        await db.mergeMessages(owner, key, rows);
      } catch (e) {
        log.error('persist history failed: $e', tag: _logTag);
      }
    }));
  }
}
