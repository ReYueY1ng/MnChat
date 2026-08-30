import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../state/providers.dart';

/// 聊天窗口（右侧）。
class ChatPage extends ConsumerStatefulWidget {
  final ChatSessionType type;
  final int sessionId;

  const ChatPage({super.key, required this.type, required this.sessionId});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _sessionName {
    final sessions = ref.read(sessionListProvider).value;
    if (sessions == null) return widget.type == ChatSessionType.group ? '群' : '好友';
    for (final s in sessions.sessions) {
      if (s.type == widget.type && s.id == widget.sessionId) return s.name;
    }
    return widget.type == ChatSessionType.group ? '群' : '好友';
  }

  @override
  Widget build(BuildContext context) {
    final active = ActiveSession(widget.type, widget.sessionId);
    final history = ref.watch(messageHistoryProvider(active));
    final myUin = ref.watch(myUinProvider);

    // 进入时标记已读 + 拉取历史
    ref.read(chatServiceProvider).markRead(widget.type, widget.sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.type == ChatSessionType.friend) {
        ref.read(chatServiceProvider).requestFriendHistory(widget.sessionId);
      } else {
        ref.read(chatServiceProvider).requestGroupHistory(widget.sessionId);
      }
    });

    final msgs = history.when(data: (m) => m, loading: () => [], error: (_, _) => []);

    return Column(
      children: [
        // 标题栏
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(widget.type == ChatSessionType.group ? Icons.group : Icons.person,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sessionName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(activeSessionProvider.notifier).close(),
                ),
              ],
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

  const _MessageBubble({required this.msg, required this.isMine});

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

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
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
    );
  }

  static String _fmtClock(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}