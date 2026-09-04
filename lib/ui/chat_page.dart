import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../state/providers.dart';
import 'widgets/avatar_view.dart';

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
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
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
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ActiveSession(widget.type, widget.sessionId);
    final history = ref.watch(messageHistoryProvider(active));
    final myUin = ref.watch(myUinProvider);
    final displayName = widget.name.isEmpty
        ? (widget.type == ChatSessionType.group ? '群' : '好友')
        : widget.name;
    final isWide = MediaQuery.of(context).size.width >= 700;

    final msgs = history.when(data: (m) => m, loading: () => [], error: (_, _) => []);

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
        // 消息列表
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Text(
                    '暂无消息',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) => _MessageBubble(
                    msg: msgs[i],
                    isMine: msgs[i].uin == myUin,
                    sessionName: displayName,
                  ),
                ),
        ),
        // 输入区
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '输入消息…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final service = ref.read(chatServiceProvider);
      if (widget.type == ChatSessionType.friend) {
        await service.sendFriendMessage(widget.sessionId, text);
      } else {
        await service.sendGroupMessage(widget.sessionId, text);
      }
      _inputCtrl.clear();
      // 本地乐观消息：立即回显（不等服务端推送）
      service.addLocalMessage(widget.type, widget.sessionId, text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e'), backgroundColor: Colors.red.shade400),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

/// 单条消息气泡。
class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMine;
  final String sessionName;

  const _MessageBubble({
    required this.msg,
    required this.isMine,
    this.sessionName = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (msg.isSystemMsg) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              msg.text,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ),
      );
    }

    // 对方消息带头像，自己消息不带
    final leading = isMine
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AvatarView(
              avatarUrl: null,
              name: sessionName,
              radius: 18,
            ),
          );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ?leading,
          Flexible(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.62,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMine ? 12 : 2),
                  bottomRight: Radius.circular(isMine ? 2 : 12),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isMine
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtClock(msg.time),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtClock(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}