/// 聊天记录检索/收藏的结果行（纯数据，无 drift 依赖）。
///
/// 由 `storage/app_database.dart` 的检索接口返回、由 UI 渲染；放在 models/ 是
/// 为了让"跨会话搜索页"与"收藏夹页"不必 import drift。
library;

/// 一条命中记录。
class ChatSearchHit {
  /// 会话 key（`friend_123` / `group_456`）。
  final String sessionKey;

  /// 发送者 uin。
  final int uin;

  /// 消息时间（epoch 秒）。
  final int time;

  /// 消息正文。
  final String text;

  /// 标记/命中发生时间（epoch 秒）：收藏夹按它倒序，搜索结果不用。
  final int markedAt;

  const ChatSearchHit({
    required this.sessionKey,
    required this.uin,
    required this.time,
    required this.text,
    this.markedAt = 0,
  });

  @override
  String toString() =>
      'ChatSearchHit($sessionKey, uin=$uin, time=$time, "$text")';
}

/// 会话 key → (类型名, id)。解析失败返回 null（脏数据只跳过，不抛）。
///
/// 格式唯一定义在 `models/session_key.dart`（`<type>_<id>`，type 即
/// [ChatSessionType] 的 name），这里只做反向解析，供 UI 从命中行跳回会话。
({String typeName, int id})? parseSessionKey(String key) {
  final sep = key.lastIndexOf('_');
  if (sep <= 0) return null;
  final id = int.tryParse(key.substring(sep + 1));
  if (id == null) return null;
  return (typeName: key.substring(0, sep), id: id);
}
