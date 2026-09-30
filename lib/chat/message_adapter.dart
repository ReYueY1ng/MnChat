/// ChatMessage/ChatSession 模型 ↔ flutter_chat_core 模型的纯映射层。
///
/// 全部为纯 Dart 函数：无网络、无单例、无状态。唯一的第三方依赖是
/// `flutter_chat_core`（其自身依赖 Flutter，无法避免）。
library;

import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../core/chat_emoji.dart' show decodeEmojiCodes;
import '../core/models/messages.dart';
import '../core/services/rich_media.dart' show RichMedia;

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
/// - 系统消息（[ChatMessage.isSystemMsg] / [ChatMsgType.system]）→ [Message.system]，
///   authorId 固定为 `'system'`；
/// - share / custom 类型 → [Message.custom]，用 `metadata` 承载应用数据
///   （`text` + `extend`），UI 侧用 [Message.custom] 的 builder 渲染；
/// - 其余 → [Message.text]，authorId 为发送者 uin 的字符串。
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
  // 显示文本：把表情码 #A1xx 解码为 Unicode 表情（id 仍用原始 text 保证稳定）。
  final text = decodeEmojiCodes(m.text);
  // 动态/互动表情的真身在 extend_data.interCode。**老数据行**（当时还没解析
  // interCode）只存了 extend_data，所以这里统一兜底再解一次 —— 否则那些消息会
  // 一直显示「请升级到最新版本查看」。
  final interCode = (m.interCode ?? '').isNotEmpty
      ? m.interCode
      : decodeChatExtendData(m.extendData)?['interCode']?.toString();
  final hasInterCode = (interCode ?? '').isNotEmpty;

  if (m.isSystemMsg || m.type == ChatMsgType.system) {
    return Message.system(id: id, authorId: 'system', createdAt: createdAt, text: text);
  }
  switch (m.type) {
    case ChatMsgType.share:
      return Message.custom(
        id: id,
        authorId: m.uin.toString(),
        createdAt: createdAt,
        metadata: {
          'type': 'share',
          'text': text,
          'extend': m.extendData,
          if (hasInterCode) 'interCode': interCode,
          if (m.isLive) 'live': true,
        },
      );
    case ChatMsgType.custom:
      return Message.custom(
        id: id,
        authorId: m.uin.toString(),
        createdAt: createdAt,
        metadata: {
          'type': 'custom',
          'text': text,
          'extend': m.extendData,
          if (hasInterCode) 'interCode': interCode,
          if (m.isLive) 'live': true,
        },
      );
    case ChatMsgType.text:
    case ChatMsgType.system:
      // 收到的卡片类消息（礼物 / 红包 / 房间邀请 / 拍一拍 …）在推送侧没有
      // msg_type（默认 text），但 extend_data 里写着 Type/shareType。游戏客户端
      // 也只认 extend_data（`mainchatview.lua:412-450`）—— 这里同样按它分流，
      // 否则礼物只会显示那句「收到来自「X」的默契礼物」兜底文案。
      final media = RichMedia.decode(m.extendData);
      if (media != null && media.isCard) {
        return Message.custom(
          id: id,
          authorId: m.uin.toString(),
          createdAt: createdAt,
          metadata: {
            'type': 'custom',
            'text': text,
            'extend': m.extendData,
            if (hasInterCode) 'interCode': interCode,
            if (m.isLive) 'live': true,
          },
        );
      }
      return Message.text(
        id: id,
        authorId: m.uin.toString(),
        createdAt: createdAt,
        text: text,
        // 保留原始文本（含 #A1xx 表情码），供气泡行内渲染真实游戏贴图；
        // text 字段则用解码后的 Unicode（会话/通知预览友好）。
        // interCode：动态表情/互动表情的真身（此时 m.text 只是低版本提示文案）。
        metadata: {
          'raw': m.text,
          if (hasInterCode) 'interCode': interCode,
          if (m.isLive) 'live': true,
        },
      );
  }
}

/// 从 [CustomMessage.metadata] 提取原始文本（share/custom 消息的正文）。
String customMessageText(CustomMessage message) =>
    message.metadata?['text']?.toString() ?? '';

/// uin → flutter_chat_core 的 [User]。
///
/// [nickname] 为空时回退为 uin 字符串；[avatarUrl] 为空时 [User.imageSource]
/// 透传 null（UI 可用首字占位渲染）。
User chatUserFor(int uin, {String? nickname, String? avatarUrl}) {
  return User(id: uin.toString(), name: nickname ?? uin.toString(), imageSource: avatarUrl);
}
