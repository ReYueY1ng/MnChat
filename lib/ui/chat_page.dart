import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_bridge.dart' show ChatBridge;
import '../chat/message_adapter.dart';
import '../core/chat_emoji.dart' show kGameEmojiCodes;
import '../core/emoticon.dart' show EmoticonImage;
import '../core/models/messages.dart';
import '../core/services/dynamics.dart' show DynamicsClient;
import '../core/services/rich_media.dart' show RichMedia;
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
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

  /// 快捷短语（来自设置，可管理）。initState 异步加载。
  List<String> _phrases = const ['嗨~', '一起来玩呀', '在干嘛'];

  /// 桥接层引用：在 [initState] 中保存，供 [dispose] 释放控制器使用——
  /// Riverpod 3.x 禁止在 State.dispose 中再访问 ref，必须提前持有。
  late final ChatBridge _bridge;

  /// 本会话的聊天控制器。在 [initState] 中一次性取得（[ChatBridge.controllerFor]
  /// 有创建/缓存副作用，不能在 build 中调用），build 直接复用。
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(chatBridgeProvider);
    _controller = _bridge.controllerFor(widget.type, widget.sessionId);
    // 进入会话时标记已读 + 拉取历史（仅首次，避免每次 build 重复触发）
    ref.read(chatServiceProvider).markRead(widget.type, widget.sessionId);
    // 加载快捷短语（用户可增删；失败/无存储环境保持默认，如 widget 测试）
    try {
      ref.read(settingsProvider).quickPhrases().then((list) {
        if (mounted) setState(() => _phrases = list);
      }).catchError((Object _) {});
    } catch (_) {
      // ProviderContainer 未注入 databaseProvider（如单元测试）→ 用默认短语
    }
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
    // 释放本会话控制器，避免 ChatBridge 的控制器映射随会话开关累积泄漏。
    _bridge.release(widget.type, widget.sessionId);
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
                    onPressed: () =>
                        ref.read(activeSessionProvider.notifier).close(),
                  ),
                  Icon(
                    widget.type == ChatSessionType.group
                        ? Icons.group
                        : Icons.person,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
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
            chatController: _controller,
            currentUserId: myUin.toString(),
            resolveUser: _resolveUser,
            onMessageSend: _send,
            theme: ChatTheme.fromThemeData(Theme.of(context)),
            builders: Builders(
              textMessageBuilder:
                  (
                    context,
                    message,
                    index, {
                    required isSentByMe,
                    groupStatus,
                  }) => _InlineEmojiBubble(
                    message: message,
                    isSentByMe: isSentByMe,
                  ),
              customMessageBuilder:
                  (
                    context,
                    message,
                    index, {
                    required isSentByMe,
                    groupStatus,
                  }) => _RichMediaBubble(
                    message: message,
                    isSentByMe: isSentByMe,
                    onOpenDynamics: widget.type == ChatSessionType.friend
                        ? _openSharedDynamics
                        : null,
                  ),
              composerBuilder: (context) => Composer(
                textEditingController: _composerController,
                hintText: '输入消息…',
                sendButtonVisibilityMode: SendButtonVisibilityMode.disabled,
                // 用 topWidget 承载快捷短语 + emoji/图片/礼物工具栏（不能包 Column，
                // 否则破坏 flutter_chat_ui 内部 Positioned 与 Stack 的父子关系）。
                topWidget: _ComposerBar(
                  onInsert: _insertText,
                  phrases: _phrases,
                ),
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
    final start = (sel.isValid ? sel.start : controller.text.length).clamp(
      0,
      controller.text.length,
    );
    final end = (sel.isValid ? sel.end : controller.text.length).clamp(
      0,
      controller.text.length,
    );
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
    if (widget.type == ChatSessionType.friend &&
        id == widget.sessionId.toString()) {
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
          SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  /// 点击分享的动态卡片 → 拉取动态后打开详情页。
  Future<void> _openSharedDynamics(String pid) async {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) return;
    final client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    try {
      final post = await client.fetchPost(pid);
      if (!mounted || post == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DynamicsDetailPage(post: post),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('动态加载失败: $e')),
        );
      }
    }
  }
}

/// 表情按钮：收起为一个按钮，点击弹出游戏表情面板（#A1xx 代码，非标准 emoji）。
class _ComposerBar extends StatelessWidget {
  final ValueChanged<String> onInsert;
  final List<String> phrases;

  const _ComposerBar({required this.onInsert, required this.phrases});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 快捷短语 chips
        if (phrases.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: phrases.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onInsert(phrases[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(phrases[i], style: const TextStyle(fontSize: 13)),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$name 功能暂未接入')));
  }

  void _showEmojiPicker(BuildContext context) {
    // kGameEmojiCodes 是 Set（O(1) contains）；选择器需按下标遍历，取一次有序快照。
    final codes = kGameEmojiCodes.toList();
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
            itemCount: codes.length,
            itemBuilder: (context, i) {
              final code = codes[i];
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onInsert(code); // 插入 #A1xx 代码（游戏客户端渲染成它自己的图标）
                },
                child: Center(child: EmoticonImage(code: code, size: 34)),
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

  const _ToolBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

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
    final raw =
        (message.metadata?['raw'] as String?) ??
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
            crossAxisAlignment: isSentByMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (createdAt != null)
                Text(
                  _fmtFullTime(createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
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
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: EmoticonImage(code: tok, size: 20),
          ),
        );
      } else {
        // @提及 → 主题色高亮
        spans.add(
          TextSpan(
            text: tok,
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        );
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

/// 富媒体气泡（share / custom 消息卡片）。
///
/// 从 [CustomMessage.metadata] 的 `extend`（url→base64→JSON）解码 [RichMedia]：
/// - 红包（Type=SendFriendRedPocket）→ 红包卡（点击占位提示，无法在外部客户端领取）
/// - 动态通知/动态分享（shareType 19/18）→ 动态卡（点击打开详情）
/// - 地图分享（shareType 1）→ 地图卡
/// - 链接（shareType 9）→ 链接卡
/// - 其余 → 回退为纯文本卡片。
class _RichMediaBubble extends StatelessWidget {
  final CustomMessage message;
  final bool isSentByMe;

  /// 点击动态卡片回调（仅好友会话有效；群会话不跳动态详情）。
  final ValueChanged<String>? onOpenDynamics;

  const _RichMediaBubble({
    required this.message,
    required this.isSentByMe,
    this.onOpenDynamics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawExt = message.metadata?['extend']?.toString();
    final media = RichMedia.decode(rawExt);

    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.62,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          decoration: BoxDecoration(
            color: isSentByMe
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: media == null ? _plainText(theme) : _card(context, media, theme),
        ),
      ),
    );
  }

  /// 无法解码 → 回退纯文本卡。
  Widget _plainText(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment:
            isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.createdAt != null)
            Text(
              _fmtFullTime(message.createdAt!.toLocal()),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          const SizedBox(height: 2),
          Text(
            customMessageText(message),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, RichMedia media, ThemeData theme) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: media.isDynamicNotice || media.isDynamics
          ? (media.pid.isNotEmpty && onOpenDynamics != null
              ? () => onOpenDynamics!(media.pid)
              : null)
          : media.isRedPacket
              ? () {
                  // 外部客户端无支付流，无法领取红包；仅提示。
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('红包需在游戏内领取')),
                  );
                }
              : media.isRoomInvite
                  ? () {
                      // 外部客户端无法进入游戏房间；展示房间信息。
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '房间: ${media.roomName.isNotEmpty ? media.roomName : media.roomUin}'
                            '（需在游戏内加入）',
                          ),
                        ),
                      );
                    }
                  : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment:
              isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.createdAt != null)
              Text(
                _fmtFullTime(message.createdAt!.toLocal()),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(media), size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  media.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 图片预览（动态/红包图）
            if (media.picList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    media.picList.first,
                    width: 120,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 120,
                      height: 90,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_outlined),
                    ),
                  ),
                ),
              ),
            // 名称 / 内容摘要
            if (media.name.isNotEmpty)
              Text(
                media.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            if (media.author.isNotEmpty)
              Text(
                '作者: ${media.author}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            if (media.content.isNotEmpty)
              Text(
                media.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            if (media.isUrl && media.url.isNotEmpty)
              Text(
                media.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            if (media.isRedPacket)
              Text(
                '金额 ¥${media.amount > 0 ? media.amount / 10 : '?'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(RichMedia media) {
    if (media.isRedPacket) return Icons.redeem;
    if (media.isRoomInvite) return Icons.videogame_asset_outlined;
    if (media.isDynamicNotice || media.isDynamics) return Icons.public;
    if (media.isMap) return Icons.map_outlined;
    if (media.isUrl) return Icons.link;
    return Icons.article_outlined;
  }
}
