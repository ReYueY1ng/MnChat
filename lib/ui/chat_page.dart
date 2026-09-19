import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_bridge.dart' show ChatBridge;
import '../chat/message_adapter.dart';
import '../core/chat_emoji.dart' show kGameEmojiCodes;
import '../core/emoticon.dart' show EmoticonImage;
// 只取会话类型/会话模型：`messages.dart` 的 `ChatMessage` 与 flutter_chat_ui
// 导出的消息组件同名，隐藏它以保证本文件里的 `ChatMessage` 指 UI 组件。
import '../core/models/messages.dart' show ChatSession, ChatSessionType;
import '../core/services/dynamics.dart' show DynamicsClient;
import '../core/services/rich_media.dart' show RichMedia;
import '../core/storage/settings_store.dart' show SettingsKeys;
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'group_detail_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart';

/// 相邻两条消息间隔超过该值时，在两条消息之间插入居中的时间分隔条。
///
/// 5 分钟与常见聊天客户端（微信 / QQ）一致：同一段连续对话不重复标注时间，
/// 只有明显中断后才重新显示，避免每条消息都拖一条时间线。
const Duration kChatTimeDividerGap = Duration(minutes: 5);

/// 消息行内头像半径（带头像框时槽位由 [headFrameSlotSize] 自动放大）。
const double _kChatAvatarRadius = 16;

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
    // 进入会话时标记已读 + 拉取历史（仅首次，避免每次 build 重复触发）；
    // 由「进入会话自动已读」设置控制（默认开启，关闭后保留未读状态）。
    // 测试环境可能未注入 databaseProvider → 回退为直接标记已读。
    try {
      ref
          .read(settingsProvider)
          .getBool(SettingsKeys.autoMarkRead, fallback: true)
          .then((auto) {
            if (auto && mounted) {
              ref
                  .read(chatServiceProvider)
                  .markRead(widget.type, widget.sessionId);
            }
          })
          .catchError((Object _) {});
    } catch (_) {
      ref.read(chatServiceProvider).markRead(widget.type, widget.sessionId);
    }
    // 加载快捷短语（用户可增删；失败/无存储环境保持默认，如 widget 测试）
    try {
      ref
          .read(settingsProvider)
          .quickPhrases()
          .then((list) {
            if (mounted) setState(() => _phrases = list);
          })
          .catchError((Object _) {});
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
    // 聊天字号缩放与"回车发送"开关：设置页修改后此处即时重建生效。
    final chatFontScale = ref.watch(chatFontScaleProvider);
    final sendOnEnter = ref.watch(sendOnEnterProvider);
    // 会话快照：对方消息头像与 SessionListPage 共用同一份头像 / 头像框数据
    //（群成员资料拉取完成后 ChatService 也会刷新快照 → 头像自动补齐）。
    final sessions =
        ref.watch(sessionListProvider).asData?.value.sessions ??
        const <ChatSession>[];
    final scheme = Theme.of(context).colorScheme;
    final displayName = widget.name.isEmpty
        ? (widget.type == ChatSessionType.group ? '群' : '好友')
        : widget.name;
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Column(
      children: [
        // 标题栏与会话列表 AppBar 对齐：同主题底色 / 同 toolbarHeight /
        // 左对齐粗体标题；窄屏显示返回箭头回到会话列表，桌面端不再提供关闭
        // 按钮（关闭由再次点击当前会话卡片完成）。
        AppBar(
          automaticallyImplyLeading: false,
          leading: isWide
              ? null
              : IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () =>
                      ref.read(activeSessionProvider.notifier).close(),
                ),
          title: RichTextView(
            displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: widget.type == ChatSessionType.group
              ? [
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
                ]
              : null,
        ),
        const Divider(height: 1),
        // 消息列表 + 输入区（flutter_chat_ui Chat 组件）
        Expanded(
          child: Stack(
            children: [
              Chat(
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
                    // 发送按钮随输入高亮：空输入时用弱化色，有非空白文本时用
                    // 主题强调色。_SendButtonIcon 直接监听外部控制器，按键即变。
                    sendIcon: _SendButtonIcon(controller: _composerController),
                    sendIconColor: scheme.primary,
                    emptyFieldSendIconColor: scheme.onSurfaceVariant,
                    // 桌面端回车发送：true 时 Enter 发送、Shift+Enter 换行；
                    // false 时 Enter 换行（均交由 Composer 内部键盘处理，复用其
                    // 已有的 onMessageSend 回调，避免自建第二套发送逻辑）。
                    sendOnEnter: sendOnEnter,
                    sendButtonVisibilityMode: SendButtonVisibilityMode.disabled,
                    // 用 topWidget 承载快捷短语 + emoji/礼物工具栏（不能包 Column，
                    // 否则破坏 flutter_chat_ui 内部 Positioned 与 Stack 的父子关系）。
                    topWidget: _ComposerBar(
                      onInsert: _insertText,
                      phrases: _phrases,
                    ),
                  ),
                  // 消息外框统一换成 _ChatMessageRow：保留 ChatMessage 原有的
                  // 动画 / 内边距 / 对齐，另外加上对方头像、悬停时间戳与时间分隔条。
                  chatMessageBuilder:
                      (
                        context,
                        message,
                        index,
                        animation,
                        child, {
                        isRemoved,
                        required isSentByMe,
                        groupStatus,
                      }) => _ChatMessageRow(
                        message: message,
                        index: index,
                        animation: animation,
                        isRemoved: isRemoved,
                        groupStatus: groupStatus,
                        // 对方消息带头像；自己的消息右对齐、不带头像。
                        avatar: isSentByMe
                            ? null
                            : _avatarFor(message, sessions),
                        // 与前一条间隔超过 [kChatTimeDividerGap] 时插入时间条。
                        showTimeDivider: _showTimeDivider(index, message),
                        child: child,
                      ),
                  // 空会话时用中文空态**替换消息列表区**（而不是覆盖整个 Chat）。
                  // 旧实现用 `Positioned.fill` 遮罩，会把输入框/工具栏一起盖住：
                  // 新会话既看不到输入框，空态里的按钮也「点了没反应」（它只是往被
                  // 遮住的输入框塞字），导致新会话完全无法开始。
                  chatAnimatedListBuilder: (context, itemBuilder) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(chatFontScale),
                    ),
                    child: StreamBuilder<void>(
                      stream: _controller.operationsStream,
                      builder: (context, _) => _controller.messages.isEmpty
                          // 「打个招呼」直接发送，而不是往输入框塞字。
                          ? _EmptyChatState(onSayHi: () => _send('嗨~'))
                          : ChatAnimatedList(itemBuilder: itemBuilder),
                    ),
                  ),
                  linkPreviewBuilder: (context, message, isSentByMe) => null,
                ),
              ),
              // 空状态中文化：flutter_chat_ui 内置文案为英文 "No messages yet"
              // 且未暴露覆写参数。空态改由 `chatAnimatedListBuilder` 在
              // 消息列表区渲染（见上），这里不再用遮罩覆盖整个 Chat。
            ],
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

  /// 构造对方消息行左侧的头像（自己的消息与系统消息返回 null，不显示）。
  ///
  /// 展示数据来源：
  /// - 好友会话：会话快照（与 SessionListPage / FriendsPage 同一组字段）；
  /// - 群会话：ChatService 缓存的群成员资料，未缓存时退化为首字占位。
  /// 消息发送者一律按「个人」样式渲染（群成员同样使用头像框）。
  Widget? _avatarFor(Message message, List<ChatSession> sessions) {
    if (message is SystemMessage) return null;
    final uin = int.tryParse(message.authorId) ?? 0;
    var name = message.authorId;
    String? avatarUrl;
    int? headType;
    int? headId;
    int? frameId;

    if (widget.type == ChatSessionType.friend) {
      for (final s in sessions) {
        if (s.type == ChatSessionType.friend && s.id == widget.sessionId) {
          name = s.name.isNotEmpty ? s.name : widget.name;
          avatarUrl = s.avatar;
          headType = s.headType;
          headId = s.headId;
          frameId = s.headFrameId;
          break;
        }
      }
    } else {
      final member = ref
          .read(chatServiceProvider)
          .groupMemberProfile(widget.sessionId, uin);
      if (member != null) {
        name = member.nickname.isNotEmpty ? member.nickname : name;
        avatarUrl = member.avatarUrl;
        headType = member.headType;
        headId = member.headId;
        frameId = member.headFrameId;
      }
    }
    if (name.isEmpty) {
      name = widget.name.isNotEmpty ? widget.name : message.authorId;
    }
    return AvatarView(
      name: name,
      avatarUrl: avatarUrl,
      type: ChatSessionType.friend,
      radius: _kChatAvatarRadius,
      headType: headType,
      headId: headId,
      frameId: frameId,
    );
  }

  /// 当前消息与前一条消息的间隔是否超过 [kChatTimeDividerGap]。
  ///
  /// 通过 [ChatController.messages] 定位前一条消息；列表 item 动画期间可能出现
  /// 索引与控制器不一致，id 不匹配时直接返回 false，避免插入错误的时间条。
  bool _showTimeDivider(int index, Message message) {
    final messages = _controller.messages;
    if (index <= 0 || index >= messages.length) return false;
    if (messages[index].id != message.id) return false;
    final previous = messages[index - 1].resolvedTime;
    final current = message.resolvedTime;
    if (previous == null || current == null) return false;
    return current.difference(previous) > kChatTimeDividerGap;
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
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '发送失败: $e',
              style: TextStyle(color: scheme.onError),
            ),
            backgroundColor: scheme.error,
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
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DynamicsDetailPage(post: post)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('动态加载失败: $e')));
      }
    }
  }
}

/// 中文空状态：覆盖 flutter_chat_ui 内置的英文 "No messages yet"。
class _EmptyChatState extends StatelessWidget {
  final VoidCallback onSayHi;

  const _EmptyChatState({required this.onSayHi});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '暂无消息，打个招呼吧 👋',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '发送第一条消息，开启你们的冒险',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onSayHi,
              icon: const Icon(Icons.waving_hand_outlined, size: 16),
              label: const Text('打个招呼'),
            ),
          ],
        ),
      ),
    );
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
        // 工具栏：emoji / 礼物（图片入口已移除）
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
      visualDensity: adaptiveDensity(context),
      icon: Icon(icon, size: 22),
      onPressed: onTap,
    );
  }
}

/// 发送按钮图标：输入为空时用弱化色（onSurfaceVariant），有非空白文本时
/// 切换为主题强调色（primary）。
///
/// Composer 的 M3 发送按钮在 `onPressed == null` 时统一走禁用色
///（`disabledColor`），传空的 `emptyFieldSendIconColor` 不生效；这里直接监听
/// 外部输入控制器自行着色，保证每次按键都即时更新（触屏/桌面一致）。
class _SendButtonIcon extends StatelessWidget {
  final TextEditingController controller;

  const _SendButtonIcon({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => Icon(
        Icons.send,
        color: value.text.trim().isEmpty
            ? scheme.onSurfaceVariant
            : scheme.primary,
      ),
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
              // 时间戳默认隐藏，仅指针悬停本条消息时淡入（触屏无 hover 不显示）。
              if (createdAt != null) _MessageTimeText(createdAt),
              const SizedBox(height: 2),
              // 复用共享富文本解析：支持 [color=] / #cRRGGBB / #n / #A1xx 表情 /
              // @提及 等（见 rich_text_view.dart）。
              Text.rich(
                TextSpan(
                  children: buildRichSpans(
                    raw,
                    context: context,
                    emojiSize: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 完整时间戳：`yyyy-M-d HH:mm:ss`（对齐原版气泡上方时间）。
String _fmtFullTime(DateTime dt) {
  final l = dt.toLocal();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}:${p(l.second)}';
}

/// 时间分隔条文案：同一天 → `HH:mm`，跨天 → `MM-DD HH:mm`。
///
/// 与 `session_list_page.dart` / `friend_request_page.dart` 的 `_fmtTime`
/// 同源（同天只显示时分），跨天追加月日以免丢失日期信息。
String _fmtDividerTime(DateTime dt) {
  final l = dt.toLocal();
  final now = DateTime.now();
  final sameDay =
      l.year == now.year && l.month == now.month && l.day == now.day;
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  final mo = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '$mo-$dd $hh:$mm';
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
          child: media == null
              ? _plainText()
              : (media.isMap || media.isRoomInvite)
              ? _mapCard(context, media, theme)
              : _card(context, media, theme),
        ),
      ),
    );
  }

  /// 无法解码 → 回退纯文本卡。
  Widget _plainText() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.createdAt != null)
            _MessageTimeText(message.createdAt!),
          const SizedBox(height: 2),
          Text(
            customMessageText(message),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  /// 地图 / 房间分享：两列卡（缩略图 + 标题 + 说明 + 标签），对齐游戏样式。
  Widget _mapCard(BuildContext context, RichMedia media, ThemeData theme) {
    final isRoom = media.isRoomInvite;
    final title = isRoom
        ? (media.roomName.isNotEmpty ? media.roomName : '房间邀请')
        : (media.name.isNotEmpty ? media.name : '地图分享');
    final desc = isRoom ? '邀请你一起玩 · 需在游戏内加入房间' : '邀请你一起玩 · 发现一个好玩的地图，快来一起吧';
    return InkWell(
      borderRadius: AppRadius.inputR,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isRoom ? '房间需在游戏内加入' : '地图需在游戏内打开')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.createdAt != null)
              _MessageTimeText(message.createdAt!),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 76,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.inputR,
                    color: theme.colorScheme.primaryContainer,
                  ),
                  child: Icon(
                    isRoom ? Icons.meeting_room_outlined : Icons.map_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRoom ? '房间' : '地图',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
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
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('红包需在游戏内领取')));
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
          crossAxisAlignment: isSentByMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.createdAt != null)
              _MessageTimeText(message.createdAt!),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconFor(media),
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (media.author.isNotEmpty)
              Text(
                '作者: ${media.author}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
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

/// 单条消息外框：沿用 flutter_chat_ui 的 [ChatMessage]（动画 / 内边距 /
/// 分组 / 点击手势全部保留），另外附加：
/// - 气泡内时间戳的显隐：桌面端鼠标悬停显示；**触屏没有 hover，改为点按气泡
///   切换**（外层 `GestureDetector`，`translucent` 不抢子级手势；公开的
///   `ChatMessage` 在本版本未暴露 `onMessageTap`，故不走它）；
/// - `leadingWidget` 展示对方头像（自己的消息不传，保持右对齐）；
/// - `headerWidget` 在消息间隔超过 [kChatTimeDividerGap] 时插入居中时间条。
class _ChatMessageRow extends StatefulWidget {
  final Message message;
  final int index;
  final Animation<double> animation;
  final bool? isRemoved;
  final MessageGroupStatus? groupStatus;

  /// 对方消息的头像；自己的消息为 null（不显示）。
  final Widget? avatar;

  /// 是否在消息上方插入时间分隔条（见 [_ChatPageState._showTimeDivider]）。
  final bool showTimeDivider;

  final Widget child;

  const _ChatMessageRow({
    required this.message,
    required this.index,
    required this.animation,
    this.isRemoved,
    this.groupStatus,
    this.avatar,
    this.showTimeDivider = false,
    required this.child,
  });

  @override
  State<_ChatMessageRow> createState() => _ChatMessageRowState();
}

class _ChatMessageRowState extends State<_ChatMessageRow> {
  /// 指针是否悬停在当前消息上（桌面端用；触屏不产生 hover 事件）。
  bool _hovering = false;

  /// 是否已点按钉住时间戳（触屏端用；再点一次取消）。
  bool _pinnedByTap = false;

  @override
  Widget build(BuildContext context) {
    final time = widget.message.resolvedTime;
    return MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      // 触屏没有 hover：点按气泡切换时间戳显隐。`translucent` 只参与命中、
      // 不拦截子级——气泡内部若自带手势识别器，仍由子级优先。
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _togglePinnedByTap,
        child: _ChatTimeScope(
          showTime: _hovering || _pinnedByTap,
          child: ChatMessage(
            message: widget.message,
            index: widget.index,
            animation: widget.animation,
            isRemoved: widget.isRemoved,
            groupStatus: widget.groupStatus,
            leadingWidget: widget.avatar,
            headerWidget: widget.showTimeDivider && time != null
                ? _TimeDivider(time: time)
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  void _setHovering(bool value) {
    if (_hovering == value) return;
    setState(() => _hovering = value);
  }

  /// 点按气泡：钉住 / 取消钉住时间戳。
  void _togglePinnedByTap() => setState(() => _pinnedByTap = !_pinnedByTap);
}

/// 消息时间戳显隐作用域：把 [_ChatMessageRow] 的显隐状态传给子级气泡，
/// 让气泡内部的时间戳无需各自维护状态。
///
/// 显隐条件 = 桌面端鼠标悬停 **或** 触屏端点按气泡钉住。
class _ChatTimeScope extends InheritedWidget {
  final bool showTime;

  const _ChatTimeScope({required this.showTime, required super.child});

  /// 读取当前消息的时间戳是否应显示；不在消息内（无作用域）时视为不显示。
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChatTimeScope>()?.showTime ??
      false;

  @override
  bool updateShouldNotify(_ChatTimeScope oldWidget) =>
      showTime != oldWidget.showTime;
}

/// 消息时间戳：默认完全透明（**占位不变，不引起布局跳动**），需要时淡入。
///
/// 显示条件见 [_ChatTimeScope]：桌面端悬停，或触屏端点按气泡钉住。
class _MessageTimeText extends StatelessWidget {
  final DateTime time;

  const _MessageTimeText(this.time);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      opacity: _ChatTimeScope.of(context) ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: Text(
        _fmtFullTime(time),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// 消息列表中的居中时间分隔条（相邻消息间隔超过 [kChatTimeDividerGap] 时）。
class _TimeDivider extends StatelessWidget {
  final DateTime time;

  const _TimeDivider({required this.time});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _fmtDividerTime(time),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
