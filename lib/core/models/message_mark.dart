/// 本机消息标记（收藏 / 本地删除）的纯模型常量与键格式。
///
/// 标记是"本机视角"的附加信息：它不改动消息本身，也不影响服务端与其他设备。
/// 与 drift 表 `message_marks.kind` 的取值一一对应，但本文件不依赖 drift。
library;

/// 消息标记类型。
abstract final class MessageMarkKind {
  /// 收藏（星标消息）。
  static const String favorite = 'favorite';

  /// 本机删除（仅本机隐藏，对方与其他设备仍可见）。
  static const String hidden = 'hidden';
}

/// 消息标记键：`<uin>_<time>`。
///
/// 同一会话内 (发送者 uin, epoch 秒) 唯一决定一条服务端消息，而会话由
/// `sessionKey` 承载，因此标记表只用这两个字段定位消息 —— 不依赖本地自增
/// `id`（历史替换 `replaceMessages` 会重建行、自增 id 会变）。
///
/// 与 `chat/message_adapter.dart` 的 [chatMessageId] 不是同一个字符串（那个还
/// 带正文与会话），但两者都能由 (uin, time) 还原，UI 侧据此把标记套回消息。
String messageMarkKey(int uin, int time) => '${uin}_$time';
