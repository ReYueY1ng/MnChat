/// ChatBridge —— ChatService ↔ flutter_chat_core [ChatController] 桥接层。
///
/// 职责：为每个会话惰性创建并持有 [ChatController]，订阅 [ChatService.eventStream]
/// 单一订阅，把 service 的历史增量 reconcile 到控制器。
///
/// 设计要点：
/// - **reconcile 决策是纯函数** [computeChatOps]，只按消息 id 计算，便于单测；
/// - **只使用 insertAllMessages / setMessages**（Oracle 裁决）：绝不用
///   updateMessage/removeMessage 逐条修补；
/// - **确定性 id 去重**：adapter 的 id 由 (sessionKey, uin, time, text) 决定，
///   乐观本地回显与服务器确认推送映射到同一 id，据此去重。
library;

import 'dart:async';

import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../core/models/messages.dart';
import '../core/services/chat_service.dart';
import 'message_adapter.dart';

// ── reconcile 决策模型 ────────────────────────────────────────────────────

/// 一次 reconcile 的决策结果（纯数据，无副作用）。
sealed class ChatOps {
  const ChatOps();
}

/// Path A：在 [index] 处批量插入 [messages]（纯前缀追加）。
final class InsertAll extends ChatOps {
  final List<Message> messages;
  final int index;

  const InsertAll(this.messages, this.index);
}

/// Path B：全量替换为 [messages]（任何 stale / update / 交错缺失）。
final class SetAll extends ChatOps {
  final List<Message> messages;

  const SetAll(this.messages);
}

/// Path C：无差异，跳过。
final class NoOp extends ChatOps {
  const NoOp();
}

/// 计算把 [current] 对齐到 [target] 所需的操作（纯函数，不调用任何控制器方法）。
///
/// 按消息 **id**（String）而非对象相等计算：
/// - `missing` = target 中 id 不在 current 的消息；
/// - `stale`   = current 中 id 不在 target 的消息；
/// - `updated` = id 相同但内容不同的消息。
///
/// 决策（Oracle 裁决）：
/// - Path C：无 missing、无 stale、无 update → [NoOp]；
/// - Path A：无 stale、无 update，且每条 missing 都**严格早于** `current.first`
///   （current 为空时平凡成立）→ [InsertAll]（missing 升序，index 0）；
/// - Path B：其余一切（任何 stale / update / 交错缺失 / 尾部追加）→ [SetAll]。
///
/// 前提：[current] 与 [target] 均为时间升序（historyOf 已保证升序）。
ChatOps computeChatOps(List<Message> current, List<Message> target) {
  final currentById = {for (final m in current) m.id: m};
  final targetIds = target.map((m) => m.id).toSet();

  final missing = target.where((m) => !currentById.containsKey(m.id)).toList();
  final stale = current.where((m) => !targetIds.contains(m.id)).toList();
  final hasUpdate = target.any((m) => currentById[m.id] != null && currentById[m.id] != m);

  if (missing.isEmpty && stale.isEmpty && !hasUpdate) return const NoOp();

  if (stale.isEmpty && !hasUpdate) {
    final oldest = current.isEmpty ? null : current.first;
    final allOlder = oldest == null ||
        missing.every((m) => _createdAt(m).isBefore(_createdAt(oldest)));
    if (allOlder) {
      final sorted = [...missing]..sort((a, b) => _createdAt(a).compareTo(_createdAt(b)));
      return InsertAll(sorted, 0);
    }
  }

  return SetAll(target);
}

/// createdAt 缺失时的兜底时间（epoch 0），保证排序/比较不抛异常。
final DateTime _epochZero = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime _createdAt(Message m) => m.createdAt ?? _epochZero;

// ── 历史映射 ──────────────────────────────────────────────────────────────

/// 把 service 的 [ChatMessage] 历史映射为 flutter_chat_core 的 [Message] 列表。
///
/// 按 id **去重**（保留首次出现），保持升序稳定。去重是必须的：
/// [InMemoryChatController] 在 debug 下断言 id 唯一，而 service 的内存缓存
/// 可能因乐观回显 + 服务器确认推送而含同 id 记录。
List<Message> chatHistoryToMessages(
  List<ChatMessage> history,
  ChatSessionType type,
  int sessionId,
) {
  final seen = <String>{};
  final out = <Message>[];
  for (final m in history) {
    final msg = chatMessageToMessage(m, type: type, sessionId: sessionId);
    if (seen.add(msg.id)) out.add(msg);
  }
  return out;
}

// ── 桥接器 ────────────────────────────────────────────────────────────────

/// 会话控制器桥接器。
///
/// - 按 [sessionKey]（`'${type.name}_$id'`）持有 `Map<String, ChatController>`；
/// - 对 [ChatService.eventStream] 只建**一个**订阅；
/// - [controllerFor] 幂等：首次调用用当前历史初始化控制器并注册。
class ChatBridge {
  ChatBridge(this._service) {
    _sub = _service.eventStream.listen(handleEvent);
  }

  final ChatService _service;
  final Map<String, ChatController> _controllers = {};
  StreamSubscription<ChatEvent>? _sub;

  /// 取（或惰性创建）指定会话的控制器。幂等：同一会话始终返回同一实例。
  ///
  /// 首次创建时以 `service.historyOf` 映射并**按 id 去重**后的列表初始化
  /// [InMemoryChatController]（其构造器在 debug 下断言 id 唯一）。
  ChatController controllerFor(ChatSessionType type, int sessionId) {
    final key = sessionKey(type, sessionId);
    final existing = _controllers[key];
    if (existing != null) return existing;

    final controller = InMemoryChatController(
      messages: chatHistoryToMessages(_service.historyOf(type, sessionId), type, sessionId),
    );
    _controllers[key] = controller;
    return controller;
  }

  /// 处理一条事件：该会话已有控制器则 reconcile，否则忽略（不抛异常）。
  ///
  /// 公开以便测试直接驱动重复投递场景；生产路径由 eventStream 订阅调用。
  void handleEvent(ChatEvent event) {
    final controller = _controllers[sessionKey(event.sessionType, event.sessionId)];
    if (controller == null) return;
    reconcile(controller, event.sessionType, event.sessionId);
  }

  /// 把 [controller] 的内容对齐到 service 当前历史。
  void reconcile(ChatController controller, ChatSessionType type, int sessionId) {
    final current = List.of(controller.messages);
    final target = chatHistoryToMessages(_service.historyOf(type, sessionId), type, sessionId);

    switch (computeChatOps(current, target)) {
      case InsertAll(:final messages, :final index):
        unawaited(controller.insertAllMessages(messages, index: index));
      case SetAll(:final messages):
        unawaited(controller.setMessages(messages));
      case NoOp():
        break;
    }
  }

  /// 取消事件订阅、释放全部控制器并清空映射。
  void dispose() {
    _sub?.cancel();
    _sub = null;
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }
}
