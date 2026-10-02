/// 会话 key —— 全仓唯一定义。
///
/// 格式 `'${type.name}_$id'`：`friend_123` / `group_456` / `system_1`。
///
/// 这个字符串同时是 drift `ChatSessions.sessionKey` 的主键、内存
/// `Map<sessionKey, List<ChatMessage>>` 的键、设置表里免打扰 / 置顶的键，
/// 以及 `MainShell` 聊天实例的 `ValueKey`。
///
/// 以前它在 5 个地方各写了一份（`storage/chat_mapper.dart`、
/// `chat/message_adapter.dart`、`chat/message_store.dart`、`chat_service.dart`
/// `_sessionKey`、`storage/settings_store.dart` `SettingsKeys.sessionKey`），
/// 改一处必须手动同步其余四处，而且没有任何编译期联系 —— 拆 ChatService
/// 时就从 2 份涨到了 5 份。现在只在这里定义，其余位置一律转调。
///
/// 本文件只依赖 `models/messages.dart`（[ChatSessionType]），
/// 不碰 drift / Flutter，因此纯映射模块也能安全复用。
library;

import 'messages.dart' show ChatSessionType;

/// 会话 key：`'${type.name}_$id'`。
String sessionKeyOf(ChatSessionType type, int id) => sessionKeyFor(type.name, id);

/// 会话 key（类型以字符串给出）。
///
/// 供只存类型名的场景使用：设置表（`SettingsKeys.sessionKey`）与通知
/// （`native_bridge` 的 `sessionKey` 字符串）。
String sessionKeyFor(String typeName, int id) => '${typeName}_$id';
