/// 本机消息标记（收藏 / 本机删除）的内存镜像 + 读写入口。
///
/// 为什么要有内存镜像：消息列表每次 reconcile 都要按 `<uin>_<time>` 判断
/// "这条是不是被我本机删掉了"，逐条查库是 O(消息数) 次 SQL；而标记量级很小
/// （几十条），整会话载入一次即可。写操作先更新镜像再落库，UI 不必等 IO。
///
/// 依赖经构造注入（数据库、当前账号 uin），与 `chat/` 目录下其它模块一致；
/// 测试环境未注入 `databaseProvider` 时两个 getter 都返回空值，全部逻辑静默跳过。
library;

import '../../models/message_mark.dart';
import '../../storage/app_database.dart';
import '../../utils/log.dart';

/// 会话内消息标记的内存镜像。
class MessageMarksStore {
  MessageMarksStore({required this._getDb, required this._getMyUin});

  final AppDatabase? Function() _getDb;
  final int Function() _getMyUin;

  static const String _logTag = 'MessageMarks';

  /// `sessionKey → {<uin>_<time>}`。
  final Map<String, Set<String>> _hidden = <String, Set<String>>{};
  final Map<String, Set<String>> _favorite = <String, Set<String>>{};

  /// 载入某会话的标记（幂等：已载入过直接返回）。
  ///
  /// 失败只记日志并保持未载入状态（下次进会话再试）—— 标记是辅助功能，
  /// 不该阻断聊天。
  Future<void> ensureLoaded(String sessionKey) async {
    if (_hidden.containsKey(sessionKey) &&
        _favorite.containsKey(sessionKey)) {
      return;
    }
    final db = _getDb();
    final owner = _getMyUin();
    if (db == null || owner == 0) return;
    try {
      final hidden = await db.messageMarkKeys(
        owner,
        MessageMarkKind.hidden,
        sessionKey: sessionKey,
      );
      final favorite = await db.messageMarkKeys(
        owner,
        MessageMarkKind.favorite,
        sessionKey: sessionKey,
      );
      _hidden[sessionKey] = hidden;
      _favorite[sessionKey] = favorite;
    } catch (e) {
      log.error('load marks failed: $e', tag: _logTag);
    }
  }

  /// 该消息是否已被本机删除（仅本机隐藏）。
  bool isHidden(String sessionKey, int uin, int time) =>
      _hidden[sessionKey]?.contains(messageMarkKey(uin, time)) ?? false;

  /// 该消息是否已收藏。
  bool isFavorite(String sessionKey, int uin, int time) =>
      _favorite[sessionKey]?.contains(messageMarkKey(uin, time)) ?? false;

  /// 本机删除的键集合（供 [ChatBridge] 过滤历史；未载入时为空集）。
  Set<String> hiddenKeysOf(String sessionKey) =>
      _hidden[sessionKey] ?? const <String>{};

  /// 收藏的键集合（供消息行画星标；未载入时为空集）。
  Set<String> favoriteKeysOf(String sessionKey) =>
      _favorite[sessionKey] ?? const <String>{};

  /// 设置/取消本机删除。
  Future<void> setHidden(
    String sessionKey,
    int uin,
    int time,
    bool on,
  ) => _write(_hidden, MessageMarkKind.hidden, sessionKey, uin, time, on);

  /// 设置/取消收藏。
  Future<void> setFavorite(
    String sessionKey,
    int uin,
    int time,
    bool on,
  ) => _write(_favorite, MessageMarkKind.favorite, sessionKey, uin, time, on);

  /// 先改镜像再落库（顺序固定：UI 立即生效，落库失败只记日志）。
  Future<void> _write(
    Map<String, Set<String>> mirror,
    String kind,
    String sessionKey,
    int uin,
    int time,
    bool on,
  ) async {
    final key = messageMarkKey(uin, time);
    final set = mirror.putIfAbsent(sessionKey, () => <String>{});
    if (on) {
      set.add(key);
    } else {
      set.remove(key);
    }
    final db = _getDb();
    final owner = _getMyUin();
    if (db == null || owner == 0) return;
    try {
      await db.setMessageMark(
        ownerUin: owner,
        sessionKey: sessionKey,
        msgUin: uin,
        msgTime: time,
        kind: kind,
        on: on,
      );
    } catch (e) {
      log.error('write mark failed: $e', tag: _logTag);
    }
  }

  /// 清空镜像（切换账号时调用，避免旧账号标记套到新账号消息上）。
  void clear() {
    _hidden.clear();
    _favorite.clear();
  }
}
