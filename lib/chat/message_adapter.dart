/// ChatMessage/ChatSession 模型 ↔ flutter_chat_core 模型的纯映射层。
///
/// 全部为纯 Dart 函数：无网络、无单例、无状态。唯一的第三方依赖是
/// `flutter_chat_core`（其自身依赖 Flutter，无法避免）。
library;

import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../core/models/messages.dart';

/// 会话存储 key，格式 `'${type.name}_$id'`（`friend_123` / `group_456`）。
///
/// 与 `lib/core/storage/chat_mapper.dart` 的 [sessionKeyOf] 格式完全一致
/// （不复用它是为了避免把 drift 拖进这个纯映射模块）。
String sessionKey(ChatSessionType type, int id) => '${type.name}_$id';

/// 生成确定性的、无冲突的消息 id。
///
/// 编码为 `'m:<sessionKey>:<uin>:<timeSeconds>:<text>'`：
/// 前置字段（sessionKey/uin/timeSeconds）均为不含 `:` 的固定形态，
/// text 是最后一个字段，因此同一会话内三元组 (uin, time, text) 唯一
/// 决定一个 id —— **乐观本地回显与服务器确认推送的同一逻辑消息共享
/// uin/time/text，因而映射到同一个 id，桥接层据此去重**。跨重启稳定。
String chatMessageId({
  required ChatSessionType type,
  required int sessionId,
  required int uin,
  required int timeSeconds,
  required String text,
}) {
  return 'm:${sessionKey(type, sessionId)}:$uin:$timeSeconds:$text';
}

/// ChatMessage → flutter_chat_core 的 [Message]。
///
/// - 系统消息（`who == 1000` → [ChatMessage.isSystemMsg]）映射为
///   [Message.system]，authorId 固定为 `'system'`；
/// - 其余映射为 [Message.text]，authorId 为发送者 uin 的字符串。
///
/// `m.time` 为 epoch **秒**，flutter_chat_core 的 [EpochDateTimeConverter]
/// 以**毫秒**为准，故 ×1000 并构造 UTC DateTime。不设置
/// sentAt/deliveredAt/seenAt/reactions 等状态字段。
Message chatMessageToMessage(
  ChatMessage m, {
  required ChatSessionType type,
  required int sessionId,
}) {
  final id = chatMessageId(
    type: type,
    sessionId: sessionId,
    uin: m.uin,
    timeSeconds: m.time,
    text: m.text,
  );
  final createdAt = DateTime.fromMillisecondsSinceEpoch(m.time * 1000, isUtc: true);

  if (m.isSystemMsg) {
    return Message.system(id: id, authorId: 'system', createdAt: createdAt, text: m.text);
  }
  return Message.text(id: id, authorId: m.uin.toString(), createdAt: createdAt, text: m.text);
}

/// uin → flutter_chat_core 的 [User]。
///
/// [nickname] 为空时回退为 uin 字符串；[avatarUrl] 为空时 [User.imageSource]
/// 透传 null（UI 可用首字占位渲染）。
User chatUserFor(int uin, {String? nickname, String? avatarUrl}) {
  return User(id: uin.toString(), name: nickname ?? uin.toString(), imageSource: avatarUrl);
}
