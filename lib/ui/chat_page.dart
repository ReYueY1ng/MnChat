import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/message_adapter.dart';
import '../core/chat_emoji.dart' show kGameEmojiCodes;
import '../core/emoticon.dart' show EmoticonImage;
import '../core/models/messages.dart';
import '../state/providers.dart';
import 'group_detail_page.dart';

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
  final TextEditingController _composerController = TextEditingController();

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
    _composerController.dispose();
    super.dispose();
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
                  if (widget.type == ChatSessionType.group)
                    IconButton(
                      tooltip: '群详情',
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GroupDetailPage(
                              groupId: widget.sessionId,
                              name: displayName,
                            ),
                          ),
                        );
                      },
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
                  _InlineEmojiBubble(message: message, isSentByMe: isSentByMe),
              customMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) =>
                  Align(
                    alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.createdAt != null)
                              Text(_fmtFullTime(message.createdAt!.toLocal()),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                            const SizedBox(height: 2),
                            Text(
                              customMessageText(message),
                              style: const TextStyle(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              composerBuilder: (context) => Composer(
                textEditingController: _composerController,
                hintText: '输入消息…',
                sendButtonVisibilityMode: SendButtonVisibilityMode.disabled,
                // 用 topWidget 承载快捷短语 + emoji/图片/礼物工具栏（不能包 Column，
                // 否则破坏 flutter_chat_ui 内部 Positioned 与 Stack 的父子关系）。
                topWidget: _ComposerBar(onInsert: _insertText),
              ),
              linkPreviewBuilder: (context, message, isSentByMe) => null,
            ),
          ),
        ),
      ],
    );
  }

  /// 在光标处插入一个表情（复用 Composer 的外部控制器，Composer 监听变化自动刷新）。
  /// 在光标处插入文本（表情码 / 快捷短语共用）。
  void _insertText(String text) {
    final controller = _composerController;
    final sel = controller.selection;
    final start = (sel.isValid ? sel.start : controller.text.length).clamp(0, controller.text.length);
    final end = (sel.isValid ? sel.end : controller.text.length).clamp(0, controller.text.length);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
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

/// 表情按钮：收起为一个按钮，点击弹出游戏表情面板（#A1xx 代码，非标准 emoji）。
class _ComposerBar extends StatelessWidget {
  final ValueChanged<String> onInsert;

  const _ComposerBar({required this.onInsert});

  static const _phrases = ['自定义', '嗨~', '一起来玩呀', '在干嘛'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 快捷短语 chips
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: _phrases.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onInsert(_phrases[i]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_phrases[i], style: const TextStyle(fontSize: 13)),
              ),
            ),
          ),
        ),
        // 工具栏：emoji / 图片 / 礼物
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _ToolBtn(
                tooltip: '表情',
                icon: Icons.emoji_emotions_outlined,
                onTap: () => _showEmojiPicker(context),
              ),
              _ToolBtn(
                tooltip: '图片',
                icon: Icons.image_outlined,
                onTap: () => _placeholder(context, '图片'),
              ),
              _ToolBtn(
                tooltip: '礼物',
                icon: Icons.card_giftcard_outlined,
                onTap: () => _placeholder(context, '礼物'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _placeholder(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name 功能暂未接入')));
  }

  void _showEmojiPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemCount: kGameEmojiCodes.length,
            itemBuilder: (context, i) {
              final code = kGameEmojiCodes[i];
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onInsert(code); // 插入 #A1xx 代码（游戏客户端渲染成它自己的图标）
                },
                child: Center(
                  child: EmoticonImage(code: code, size: 34),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _ToolBtn({required this.tooltip, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 22),
      onPressed: onTap,
    );
  }
}

/// 聊天气泡：把 `#A1xx` 表情码渲染为行内真实游戏贴图（EmoticonImage），
/// 其余为普通文本；按是否我发出对齐并应用气泡底色。
class _InlineEmojiBubble extends StatelessWidget {
  final Message message;
  final bool isSentByMe;

  const _InlineEmojiBubble({required this.message, required this.isSentByMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = (message.metadata?['raw'] as String?) ??
        switch (message) {
          TextMessage m => m.text,
          SystemMessage m => m.text,
          _ => '',
        };
    final maxWidth = MediaQuery.of(context).size.width * 0.62;
    final createdAt = message.createdAt;
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSentByMe
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (createdAt != null)
                Text(
                  _fmtFullTime(createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
              const SizedBox(height: 2),
              Text.rich(TextSpan(children: _spans(raw, theme))),
            ],
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _spans(String raw, ThemeData theme) {
    final spans = <InlineSpan>[];
    // 匹配表情码 #A1xx / #A3xx 或 @提及。
    final re = RegExp(r'#A\d{3}|@[^\s]+');
    var pos = 0;
    for (final m in re.allMatches(raw)) {
      if (m.start > pos) spans.add(TextSpan(text: raw.substring(pos, m.start)));
      final tok = m.group(0)!;
      if (kGameEmojiCodes.contains(tok)) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: EmoticonImage(code: tok, size: 20),
        ));
      } else {
        // @提及 → 主题色高亮
        spans.add(TextSpan(text: tok, style: TextStyle(color: theme.colorScheme.primary)));
      }
      pos = m.end;
    }
    if (pos < raw.length) spans.add(TextSpan(text: raw.substring(pos)));
    return spans;
  }
}

/// 完整时间戳：`yyyy-M-d HH:mm:ss`（对齐原版气泡上方时间）。
String _fmtFullTime(DateTime dt) {
  final l = dt.toLocal();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}:${p(l.second)}';
}
