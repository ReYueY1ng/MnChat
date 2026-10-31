/// 会话历史分页器：游标、内存页、按天窗口与收起策略。
///
/// 从 ChatService 拆出的独立单元：只依赖数据库、消息缓存与一个「已加载」回调，
/// 因此可以直接对分页边界做单测，不再需要一个已登录的 ChatService。
library;

import '../../models/messages.dart'
    show ChatMessage, ChatSessionType, sortMessagesAscending;
import '../../storage/app_database.dart';
import '../../storage/chat_mapper.dart' show chatMessageFromRecord;
import '../../utils/log.dart';
import 'message_store.dart' show HistoryCursor;
import 'message_upserter.dart' show mergeHistory;

/// 历史分页器。
class HistoryPager {
  HistoryPager({
    required this.getDb,
    required this.getMyUin,
    required this.messagesCache,
    required this.onHistoryLoaded,
  });

  final AppDatabase? Function() getDb;
  final int Function() getMyUin;

  /// 每会话消息列表（与 ChatService 共享同一份内存镜像）。
  final Map<String, List<ChatMessage>> messagesCache;

  /// 加载更早页成功后通知外部（聊天页据此把前缀上屏）。
  final void Function(ChatSessionType type, int id) onHistoryLoaded;

  /// 每会话「已加载到哪」的游标（最老一条的 time/id）。
  final Map<String, HistoryCursor> cursors = {};

  /// 已经主动展开过历史的会话：展开后不再按 50/100 裁剪。
  final Set<String> expanded = {};

  static const int pageSize = 50;
  static const int restorePageSize = 200;

  static const String _logTag = 'HistoryPager';

  int _sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  /// 是否还能向更早翻页。
  bool hasOlder(String key) => cursors.containsKey(key);

  /// 进会话时准备分页状态：内存为空 → 取最新一页；否则补建游标。
  Future<void> prepare(
    ChatSessionType type,
    int id, {
    int limit = restorePageSize,
  }) async {
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0) return;
    final key = _key(type, id);
    final cache = messagesCache[key];
    if (cache == null || cache.isEmpty) {
      try {
        final rows = await db.latestMessages(owner, key, limit: limit);
        if (rows.isEmpty) return;
        messagesCache[key] = rows
            .map(chatMessageFromRecord)
            .toList(growable: false);
        final oldest = rows.first;
        cursors[key] = (time: oldest.time, id: oldest.id);
        expanded.add(key);
      } catch (e) {
        log.warn('prepare history failed: $e', tag: _logTag);
      }
      return;
    }
    if (cursors.containsKey(key)) return;
    final oldest = cache.first;
    try {
      final rowId = await db.messageRowId(
        owner,
        key,
        uin: oldest.uin,
        time: oldest.time,
        content: oldest.text,
      );
      if (rowId != null) {
        cursors[key] = (time: oldest.time, id: rowId);
      }
    } catch (e) {
      log.warn('history cursor failed: $e', tag: _logTag);
    }
  }

  /// 加载更早一页（keyset 分页），返回新增条数；0 表示没有更多了。
  Future<int> loadOlder(
    ChatSessionType type,
    int id, {
    int limit = pageSize,
  }) async {
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0) return 0;
    final key = _key(type, id);
    final cursor = cursors[key];
    if (cursor == null) return 0;
    final List<ChatMessageRecord> rows;
    try {
      rows = await db.messagesBefore(
        owner,
        key,
        beforeTime: cursor.time,
        beforeId: cursor.id,
        limit: limit,
      );
    } catch (e) {
      log.warn('load older history failed: $e', tag: _logTag);
      return 0;
    }
    if (rows.isEmpty) {
      cursors.remove(key);
      return 0;
    }
    final older = rows.map(chatMessageFromRecord).toList(growable: false);
    messagesCache[key] = sortMessagesAscending(
      mergeHistory(older, messagesCache[key]),
    );
    expanded.add(key);
    final oldest = rows.first;
    if (rows.length < limit) {
      cursors.remove(key);
    } else {
      cursors[key] = (time: oldest.time, id: oldest.id);
    }
    onHistoryLoaded(type, id);
    return rows.length;
  }

  /// 会话关闭时收拢历史：只保留最近 [cap] 条，并丢掉游标。
  void collapse(ChatSessionType type, int id, {required int cap}) {
    final key = _key(type, id);
    if (!expanded.remove(key)) return;
    cursors.remove(key);
    final list = messagesCache[key];
    if (list == null) return;
    if (list.length > cap) {
      messagesCache[key] = list.sublist(list.length - cap);
    }
  }

  /// 本机删除了某会话的全部聊天记录：清掉内存镜像与游标。
  void forget(ChatSessionType type, int id) {
    final key = _key(type, id);
    messagesCache.remove(key);
    cursors.remove(key);
    expanded.remove(key);
  }

  /// 某一天的历史（含端点）；当天无消息时退化为该日结束前最近 [limit] 条。
  Future<List<ChatMessage>> forDay(
    ChatSessionType type,
    int id,
    DateTime day, {
    int limit = 300,
    int fallbackLimit = 50,
  }) async {
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0) return const <ChatMessage>[];
    final key = _key(type, id);
    final start = _sec(DateTime(day.year, day.month, day.day));
    final end =
        _sec(
          DateTime(
            day.year,
            day.month,
            day.day,
          ).add(const Duration(days: 1)),
        ) -
        1;
    try {
      var rows = await db.messagesInRange(
        owner,
        key,
        from: start,
        to: end,
        limit: limit,
      );
      if (rows.isEmpty) {
        rows = await db.messagesBefore(
          owner,
          key,
          beforeTime: end + 1,
          beforeId: 1 << 62,
          limit: fallbackLimit,
        );
      }
      return rows.map(chatMessageFromRecord).toList(growable: false);
    } catch (e) {
      log.warn('history for day failed: $e', tag: _logTag);
      return const <ChatMessage>[];
    }
  }

  static String _key(ChatSessionType type, int id) =>
      '${type.name}_$id';
}
