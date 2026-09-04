import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/message_adapter.dart';
import '../core/models/messages.dart';
import '../state/providers.dart';

/// 聊天窗口（右侧）。
class ChatPage extends ConsumerStatefulWidget {
  final ChatSessionType type;
  final int sessionId;
  final String name;

  const ChatPage({
    super.key,
    required this.type,
    required this.sessionId,
    required this.name,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    // 进入会话时标记已读 + 拉取历史（仅首次，避免每次 build 重复触发）
    ref.read(chatServiceProvider).markRead(widget.type, widget.sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_historyLoaded) return;
      _historyLoaded = true;
      final service = ref.read(chatServiceProvider);
      if (widget.type == ChatSessionType.friend) {
        service.requestFriendHistory(widget.sessionId);
      } else {
        service.requestGroupHistory(widget.sessionId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUin = ref.watch(myUinProvider);
    final displayName = widget.name.isEmpty
        ? (widget.type == ChatSessionType.group ? '群' : '好友')
        : widget.name;
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Column(
      children: [
        // 标题栏（SafeArea 防止被系统状态栏遮挡）
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  // 窄屏显示返回按钮，宽屏用关闭
                  IconButton(
                    tooltip: isWide ? '关闭' : '返回',
                    icon: Icon(isWide ? Icons.close : Icons.arrow_back),
                    onPressed: () => ref.read(activeSessionProvider.notifier).close(),
                  ),
                  Icon(widget.type == ChatSessionType.group ? Icons.group : Icons.person,
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        // 消息列表 + 输入区（flutter_chat_ui Chat 组件）
        Expanded(
          child: Chat(
            chatController: ref.watch(chatBridgeProvider).controllerFor(widget.type, widget.sessionId),
            currentUserId: myUin.toString(),
            resolveUser: _resolveUser,
            onMessageSend: _send,
            theme: ChatTheme.fromThemeData(Theme.of(context)),
            builders: Builders(
              textMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) =>
                  SimpleTextMessage(
                    message: message,
                    index: index,
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.62,
                    ),
                  ),
              composerBuilder: (context) => Composer(
                hintText: '输入消息…',
                sendButtonVisibilityMode: SendButtonVisibilityMode.disabled,
              ),
              linkPreviewBuilder: (context, message, isSentByMe) => null,
            ),
          ),
        ),
      ],
    );
  }

  /// 解析用户信息：自己 → 昵称；好友会话对方 → 会话名；其余 → uin 字符串。
  Future<User?> _resolveUser(UserID id) async {
    final service = ref.read(chatServiceProvider);
    final myUin = ref.read(myUinProvider);
    if (id == myUin.toString()) {
      return chatUserFor(myUin, nickname: service.myNickname);
    }
    if (widget.type == ChatSessionType.friend && id == widget.sessionId.toString()) {
      return chatUserFor(widget.sessionId, nickname: widget.name);
    }
    return chatUserFor(int.tryParse(id) ?? 0);
  }

  /// 发送消息：trim/空值守卫 → 发送 → 本地乐观回显 → 失败弹 SnackBar。
  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      final service = ref.read(chatServiceProvider);
      if (widget.type == ChatSessionType.friend) {
        await service.sendFriendMessage(widget.sessionId, trimmed);
      } else {
        await service.sendGroupMessage(widget.sessionId, trimmed);
      }
      // 本地乐观消息：立即回显（ChatBridge 经 eventStream 增量 reconcile 上屏，
      // 无需在此处手动操作 controller）
      service.addLocalMessage(widget.type, widget.sessionId, trimmed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e'), backgroundColor: Colors.red.shade400),
        );
      }
    }
  }
}
