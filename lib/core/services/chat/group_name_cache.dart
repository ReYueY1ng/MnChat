import 'dart:async';
import 'dart:convert';

import '../../storage/app_database.dart';
import '../../utils/log.dart';
import '../../models/messages.dart';

/// 群名缓存：把已知群名落到 settings 表一行 JSON，重启后**立刻**显示真实群名，
/// 不必等 `query_user_groups`。
///
/// 结构刻意保持简单：一张 settings 行足够，零建表 / 零迁移 / 零代码生成。
/// 数据来源与写入目标由构造注入（[groupSessions] 为 ChatService 的群会话表）。
class GroupNameCache {
  GroupNameCache({
    required this._getDb,
    required this._getMyUin,
    required this._groupSessions,
  });

  final AppDatabase? Function() _getDb;
  final int Function() _getMyUin;
  final Map<int, ChatSession> _groupSessions;

  /// 缓存键。带 `.v1` 后缀：格式若有变不会误解析。
  static const String key = 'cache.groupNames.v1';

  /// 最多保留多少条（防无界增长；正常账号远小于此）。
  static const int maxEntries = 1000;

  static const String _logTag = 'GroupNameCache';

  /// 落盘群名。写库失败只记日志，不阻断群列表加载。
  void persist() {
    final db = _getDb();
    if (db == null || _getMyUin() == 0) return;
    final map = <String, String>{};
    for (final s in _groupSessions.values) {
      final name = s.name.trim();
      if (s.type != ChatSessionType.group || name.isEmpty) continue;
      map['${s.id}'] = name;
      if (map.length >= maxEntries) break;
    }
    if (map.isEmpty) return;
    final text = jsonEncode(map);
    unawaited(() async {
      try {
        await db.setSetting(key, text);
      } catch (e) {
        log.error('persist group names failed: $e', tag: _logTag);
      }
    }());
  }

  /// 恢复群名缓存：只为「本地还没有的群」补建会话；随后 `loadSessions` 会用网络
  /// 结果覆盖/合并，不在群列表里且无聊天记录的会被既有逻辑清掉，不留幽灵群。
  Future<void> load() async {
    final db = _getDb();
    if (db == null) return;
    try {
      final raw = await db.getSetting(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final e in decoded.entries) {
        final gid = int.tryParse('${e.key}');
        final name = '${e.value}'.trim();
        if (gid == null || gid == 0 || name.isEmpty) continue;
        if (_groupSessions.containsKey(gid)) continue;
        _groupSessions[gid] = ChatSession(
          id: gid,
          type: ChatSessionType.group,
          name: name,
        );
      }
    } catch (e) {
      log.warn('恢复群名缓存失败: $e', tag: _logTag);
    }
  }
}
