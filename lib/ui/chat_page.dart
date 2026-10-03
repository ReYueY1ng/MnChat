import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_bridge.dart' show ChatBridge;
import '../chat/message_adapter.dart';
import '../core/emoticon.dart' show ImfcEmojiImage;
// 只取会话类型/会话模型：`messages.dart` 的 `ChatMessage` 与 flutter_chat_ui
// 导出的消息组件同名，隐藏它以保证本文件里的 `ChatMessage` 指 UI 组件。
import '../core/models/emoji_catalog.dart'
    show ImfcEmoji, isDynamicEmojiHint, parseImfc;
import '../core/models/messages.dart'
    show
        ChatSession,
        ChatSessionType,
        decodeChatExtendData,
        emojiCodeForMessage;
import '../core/services/chat_service.dart';
import '../core/services/dynamics.dart' show DynamicsClient;
import '../core/services/rich_media.dart' show RichMedia, ShareType;
import '../core/storage/settings_store.dart' show SettingsKeys;
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'group_detail_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/emoji_code_image.dart' show EmojiCodeImage;
import 'widgets/emoji_picker.dart' show showEmojiPicker;
import 'widgets/gift_picker.dart' show showGiftPicker;
import 'widgets/rich_text_view.dart';
import '../core/services/image_disk_cache.dart';

/// 相邻两条消息间隔超过该值时，在两条消息之间插入居中的时间分隔条。
///
/// 5 分钟与常见聊天客户端（微信 / QQ）一致：同一段连续对话不重复标注时间，
/// 只有明显中断后才重新显示，避免每条消息都拖一条时间线。
const Duration kChatTimeDividerGap = Duration(minutes: 5);

/// 消息行内头像半径（带头像框时槽位由 [headFrameSlotSize] 自动放大）。
const double _kChatAvatarRadius = 22;

/// 气泡最大宽度占屏宽比例（原来 0.62 偏窄，手机上长句子折行过多）。
const double _kBubbleMaxWidthFactor = 0.75;

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

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  bool _historyLoaded = false;
  final TextEditingController _composerController = TextEditingController();

  /// 快捷短语（来自设置，可管理）。initState 异步加载。
  List<String> _phrases = const ['嗨~', '一起来玩呀', '在干嘛'];

  /// 桥接层引用：在 [initState] 中保存，供 [dispose] 释放控制器使用——
  /// Riverpod 3.x 禁止在 State.dispose 中再访问 ref，必须提前持有。
  late final ChatBridge _bridge;

  /// 同上：dispose 中要用它清空「正在查看的会话」并补标已读。
  late final ChatService _service;

  /// 「进入会话自动已读」设置解析结果；dispose 时据此决定是否补标已读。
  bool _autoRead = true;

  /// 是否**真的**进过后台（paused / hidden）。
  ///
  /// 桌面端窗口失焦只会上报 `inactive`，不算后台；用它区分「真后台回来」
  /// 与「窗口重新聚焦」。
  bool _wasBackground = false;

  /// 本会话的聊天控制器。在 [initState] 中一次性取得（[ChatBridge.controllerFor]
  /// 有创建/缓存副作用，不能在 build 中调用），build 直接复用。
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(chatBridgeProvider);
    _controller = _bridge.controllerFor(widget.type, widget.sessionId);
    // 提前持有：Riverpod 3.x 禁止在 dispose 中再访问 ref。
    _service = ref.read(chatServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    // 进入会话：登记为「正在查看」并（默认）标记已读。
    // 登记后，停留期间到达的消息不再累加未读；离开时 [dispose] 再补一次已读，
    // 保证返回列表后红点一定消掉。由「进入会话自动已读」设置控制（默认开启）。
    // 测试环境可能未注入 databaseProvider → 回退为直接登记。
    try {
      ref
          .read(settingsProvider)
          .getBool(SettingsKeys.autoMarkRead, fallback: true)
          .then((auto) {
            if (mounted) {
              _autoRead = auto;
              _service.setViewing(
                widget.type,
                widget.sessionId,
                autoRead: auto,
              );
            }
          })
          .catchError((Object _) {});
    } catch (_) {
      _service.setViewing(widget.type, widget.sessionId);
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

  /// 前后台切换：退到后台就不再算「正在查看」，否则后台期间到达的消息不会
  /// 计入未读、回前台也不会亮红点（用户可能真漏消息）。**真正**回到前台才重新登记
  /// —— 桌面端窗口聚焦也会上报 resumed，若不区分，每次点回窗口都会重标已读并
  /// 重新发一次会话快照（表现为列表无谓刷新）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _wasBackground = true;
        _service.setViewing(null, null, autoRead: false);
      case AppLifecycleState.resumed:
        if (_wasBackground) {
          _wasBackground = false;
          _service.setViewing(
            widget.type,
            widget.sessionId,
            autoRead: _autoRead,
          );
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 离开会话：清空「正在查看」并把刚在看的会话补标已读 —— 否则停留期间到达的
    // 消息会一直留在未读数里，返回列表后红点消不掉（见 [ChatService.setViewing]）。
    _service.setViewing(null, null, autoRead: _autoRead);
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
                      onImfc: _sendImfc,
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
                        isSentByMe: isSentByMe,
                        isRemoved: isRemoved,
                        groupStatus: groupStatus,
                        // 双方都带头像：对方在气泡左侧，自己在右侧。
                        avatar: _avatarFor(
                          message,
                          sessions,
                          isSentByMe: isSentByMe,
                        ),
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
                    child: ChatAnimatedList(itemBuilder: itemBuilder),
                  ),
                  // 空会话的中文空态走官方 `emptyChatListBuilder`：由
                  // ChatAnimatedList 自己在列表为空时叠一层（`Positioned.fill`，
                  // 输入框是它的兄弟节点、不会被盖住）。
                  // **不要**再用 StreamBuilder 把 ChatAnimatedList 整体换成空态控件 ——
                  // 空↔非空切换时它会反复卸载/重挂，GlobalKey 重复出现在树上、
                  // SliverAnimatedList 索引错乱，整段消息列表随即渲染失败。
                  // 「打个招呼」只往输入框塞字，不直接发出去（误点代价太大）。
                  emptyChatListBuilder: (context) =>
                      _EmptyChatState(onInsert: () => _insertText('嗨~')),
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
  Widget? _avatarFor(
    Message message,
    List<ChatSession> sessions, {
    required bool isSentByMe,
  }) {
    if (message is SystemMessage) return null;
    // 自己的消息：用本人资料（与资料页同源 —— DIY 头像 / 头像框 / 头像本体）。
    // 尚未拉到或未登录时回退昵称首字占位，不阻塞气泡渲染。
    if (isSentByMe) {
      final info = ref.watch(myAvatarInfoProvider).asData?.value;
      final ownName = info?.name ?? '';
      final auth = ref.watch(authProvider).auth;
      return AvatarView(
        name: ownName.isNotEmpty ? ownName : (auth?.name ?? ''),
        avatarUrl: info?.avatarUrl,
        type: ChatSessionType.friend,
        radius: _kChatAvatarRadius,
        headType: info?.headType,
        headId: info?.headId,
        frameId: info?.frameId,
      );
    }
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

  /// 发送互动表情（骰子 / 猜拳）：结果由服务端消息携带、点按即发（不经过输入框）。
  Future<void> _sendImfc(ImfcEmoji emoji) async {
    if (widget.type != ChatSessionType.friend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('互动表情暂仅支持好友会话')),
      );
      return;
    }
    try {
      await ref
          .read(chatServiceProvider)
          .sendImfcEmoji(widget.sessionId, emoji);
      // 成功后由本地乐观回显的聊天气泡展示结果图，无需额外提示。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
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
///
/// 「打个招呼」按钮只把招呼语填进输入框（同快捷短语），发送由用户自己按发送键 ——
/// 空态里任何一键直发都会在误触时真的给对方发消息。
class _EmptyChatState extends StatelessWidget {
  final VoidCallback onInsert;

  const _EmptyChatState({required this.onInsert});

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
              onPressed: onInsert,
              icon: const Icon(Icons.waving_hand_outlined, size: 16),
              label: const Text('打个招呼'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表情按钮：弹出游戏表情面板（「基础」内置表情 + 「我的」服务端表情包）。
class _ComposerBar extends ConsumerWidget {
  final ValueChanged<String> onInsert;
  final List<String> phrases;

  /// 互动表情（骰子/猜拳）：点按即发送，不走输入框。
  final ValueChanged<ImfcEmoji>? onImfc;

  const _ComposerBar({
    required this.onInsert,
    required this.phrases,
    this.onImfc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                anchorKey: _emojiKey,
                onTap: () => _showEmojiPicker(context, ref),
              ),
              _ToolBtn(
                tooltip: '礼物',
                icon: Icons.card_giftcard_outlined,
                anchorKey: _giftKey,
                onTap: () => _showGiftPicker(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 表情 / 礼物按钮的锚点：浮动面板要贴在按钮上方。
  static final GlobalKey _emojiKey = GlobalKey();
  static final GlobalKey _giftKey = GlobalKey();

  Rect? _anchorOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _showEmojiPicker(BuildContext context, WidgetRef ref) {
    showEmojiPicker(
      context,
      ref,
      onPick: onInsert,
      onImfc: onImfc,
      anchor: _anchorOf(_emojiKey),
    );
  }

  /// 当前会话的对方 uin（礼物只能送给好友）。群聊 / 未选中时不弹面板。
  void _showGiftPicker(BuildContext context, WidgetRef ref) {
    final active = ref.read(activeSessionProvider);
    if (active == null || active.type != ChatSessionType.friend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('礼物只能送给好友会话')),
      );
      return;
    }
    showGiftPicker(
      context,
      ref,
      uin: active.id,
      name: ref.read(sessionListProvider).asData?.value.sessions
              .where((s) => s.type == active.type && s.id == active.id)
              .firstOrNull
              ?.name ??
          '${active.id}',
      anchor: _anchorOf(_giftKey),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  /// 浮动面板的锚点（面板贴这个按钮弹出）。
  final Key? anchorKey;

  const _ToolBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.anchorKey,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: anchorKey,
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

  /// 只有「本进程运行期间到的」（新收到 / 自己刚发）才播动画；
  /// 历史消息直接显示结果帧 —— 骰子/猜拳是即时反馈，翻旧记录不该重播。
  bool get _animateEmoji => message.metadata?['live'] == true;

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
    // 动态/互动表情的真身在 extend_data.interCode 里（文本只是低版本提示文案）。
    final emojiCode = emojiCodeForMessage(
      text: raw,
      interCode: message.metadata?['interCode']?.toString(),
    );
    final maxWidth =
        MediaQuery.of(context).size.width * _kBubbleMaxWidthFactor;
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              // 动态/互动表情：渲染成图，不显示低版本提示文案或 JSON 原文。
              if (emojiCode != null)
                _EmojiMessageBody(code: emojiCode, animate: _animateEmoji)
              else if (isDynamicEmojiHint(raw))
                // 解不出表情代码（老数据 / 离线历史 / 素材缺失）时，也别把
                // 那句「请升级到最新版本查看」当正文显示 —— 给个中性提示。
                const _DynamicEmojiHintChip()
              else
                // 复用共享富文本解析：支持 [color=] / #cRRGGBB / #n / #A1xx 表情 /
                // @提及 等（见 rich_text_view.dart）。
                Text.rich(
                  TextSpan(
                    children: buildRichSpans(
                      raw,
                      context: context,
                      emojiSize: 24,
                      emojiAnimate: _animateEmoji,
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
class _RichMediaBubble extends ConsumerWidget {
  final CustomMessage message;
  final bool isSentByMe;

  /// 点击动态卡片回调（仅好友会话有效；群会话不跳动态详情）。
  final ValueChanged<String>? onOpenDynamics;

  /// 同上：只有运行期间新到的才播动画。
  bool get _isLive => message.metadata?['live'] == true;

  const _RichMediaBubble({
    required this.message,
    required this.isSentByMe,
    this.onOpenDynamics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rawExt = message.metadata?['extend']?.toString();
    final media = RichMedia.decode(rawExt);

    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width * _kBubbleMaxWidthFactor,
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
              : media.isFriendGift
              ? _giftCard(context, ref, media, theme)
              : (media.isMap || media.isRoomInvite)
              ? _mapCard(context, media, theme)
              : _card(context, media, theme),
        ),
      ),
    );
  }

  /// 礼物卡：礼物图（目录里的道具图标）+ 名称 + 数量 + 默契度。
  ///
  /// 名称/图标来自服务端 visual-cfg（`new_give_gift_config` + `items`），
  /// 还没加载出来时退回「礼物 #id」+ 通用礼物图标。
  Widget _giftCard(
    BuildContext context,
    WidgetRef ref,
    RichMedia media,
    ThemeData theme,
  ) {
    final gift = ref
        .watch(giftCatalogProvider)
        .asData
        ?.value
        .byId(media.giftItemId);
    final name = gift?.displayName ?? '礼物 ${media.giftItemId}';
    final icon = gift?.icon;
    final num = media.giftNum > 0 ? media.giftNum : 1;
    final who = media.giftSrcName.isNotEmpty
        ? media.giftSrcName
        : media.nickname;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, size: 18),
              const SizedBox(width: 6),
              Text(
                '默契礼物',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: icon != null && icon.startsWith('http')
                      ? Image.network(
                          icon,
                          width: 44,
                          height: 44,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.card_giftcard, size: 28),
                        )
                      : const Icon(Icons.card_giftcard, size: 28),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name ×$num',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (who.isNotEmpty)
                      Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (media.giftAddValue > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.hexagon,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '默契度 +${media.giftAddValue}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 无法解码 → 回退纯文本卡。
  ///
  /// 但动态表情要先看一眼 `extend_data.interCode`：它可能被归成 share/custom
  /// 类型走到这里，此时正文只是「请升级到最新版本查看」，必须改成渲染表情。
  Widget _plainText() {
    final code = _emojiCodeOrNull;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (code != null)
            _EmojiMessageBody(code: code, animate: _isLive)
          else if (isDynamicEmojiHint(customMessageText(message)))
            const _DynamicEmojiHintChip()
          else
            Text(
              customMessageText(message),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  /// 本条消息应渲染的表情代码（interCode 优先，其次动态表情的 JSON 信封）。
  String? get _emojiCodeOrNull {
    final ext = message.metadata?['extend']?.toString();
    final interCode =
        message.metadata?['interCode']?.toString() ??
        decodeChatExtendData(ext)?['interCode']?.toString();
    return emojiCodeForMessage(
      text: message.metadata?['text']?.toString() ?? ext,
      interCode: interCode,
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
    // 除图标+标题外是否有可展示的细节；没有则给一句兜底说明，避免空卡片。
    final hasDetail =
        media.name.isNotEmpty ||
        media.author.isNotEmpty ||
        media.content.isNotEmpty ||
        media.picList.isNotEmpty ||
        (media.isUrl && media.url.isNotEmpty) ||
        media.isRedPacket ||
        ((media.isPat || media.isCustomPanel) && media.subtitle.isNotEmpty);
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: isSentByMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  child: Image(image: CachedNetworkImageProvider(media.picList.first),
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
            // 拍一拍 / 自定义面板：正文取 tapText / customData.strContent。
            if ((media.isPat || media.isCustomPanel) &&
                media.content.isEmpty &&
                media.subtitle.isNotEmpty)
              Text(
                media.subtitle,
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
            if (!hasDetail)
              Text(
                media.hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(RichMedia media) {
    if (media.isFriendGift) return Icons.card_giftcard;
    if (media.isRedPacket || media.shareType == ShareType.familyRedPacket) {
      return Icons.redeem;
    }
    if (media.isRoomInvite) return Icons.videogame_asset_outlined;
    if (media.isPat) return Icons.touch_app_outlined;
    if (media.isAchieve) return Icons.emoji_events_outlined;
    if (media.isCustomPanel) return Icons.style_outlined;
    if (media.isDynamicNotice || media.isDynamics) return Icons.public;
    if (media.isMap) return Icons.map_outlined;
    if (media.isUrl) return Icons.link;
    switch (media.shareType) {
      case ShareType.role:
        return Icons.person_outline;
      case ShareType.skin:
      case ShareType.chameleon:
        return Icons.checkroom_outlined;
      case ShareType.ride:
        return Icons.directions_car_outlined;
      case ShareType.weapon:
        return Icons.hardware_outlined;
      case ShareType.avatar:
      case ShareType.avatarMatch:
        return Icons.account_circle_outlined;
      case ShareType.familyRecruit:
      case ShareType.familyInvite:
      case ShareType.familyServer:
      case ShareType.familyDynamics:
        return Icons.family_restroom_outlined;
      case ShareType.rankSystem:
        return Icons.leaderboard_outlined;
      case ShareType.contentFavsShare:
        return Icons.bookmark_outline;
      case ShareType.qixiPartnerInvite:
      case ShareType.customPeerShare:
        return Icons.favorite_outline;
      case ShareType.resourceGoodShare:
      case ShareType.versionResCrShare:
        return Icons.inventory_2_outlined;
      case ShareType.action:
        return Icons.sports_martial_arts_outlined;
      case ShareType.customPic:
        return Icons.image_outlined;
      default:
        return Icons.article_outlined;
    }
  }
}

/// 把表情代码渲染成消息里的图。
///
/// 互动表情（骰子/猜拳 `@IMFC&N_M`）用图集结果帧/动图；动态表情（`[mdemo]...`）
/// 用内置动图。
class _EmojiMessageBody extends StatelessWidget {
  /// 气泡里表情的渲染尺寸（比行内表情大得多，和游戏里一致）。
  static const double kSize = 96;

  final String code;

  /// 是否播动画：新收到/刚发的播，历史消息直接显示结果帧。
  final bool animate;

  const _EmojiMessageBody({required this.code, this.animate = true});

  @override
  Widget build(BuildContext context) {
    final imfc = parseImfc(code);
    return imfc != null
        ? ImfcEmojiImage(ref: imfc, size: kSize, animate: animate)
        : EmojiCodeImage(code: code, size: kSize, animate: animate);
  }
}

/// 「拿不到表情代码的动态表情」的中性提示。
///
/// 老数据 / 离线历史（`chat_query` 只回三元组）/ 游戏本身就缺素材的那一个，
/// 都解不出 interCode —— 此时不要把「请升级到最新版本查看」当正文显示。
class _DynamicEmojiHintChip extends StatelessWidget {
  const _DynamicEmojiHintChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.emoji_emotions_outlined,
          size: 18,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Text(
          '动态表情',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// 单条消息外框：沿用 flutter_chat_ui 的 [ChatMessage]（动画 / 内边距 /
/// 分组 / 点击手势全部保留），另外附加：
/// - 时间戳：**气泡外**下方灰字常显，与气泡同侧对齐。此前内嵌在气泡顶部、
///   默认透明并靠悬停淡入；手机端点按虽然接了 `GestureDetector`，但点按多半
///   落在气泡内的富文本上被其手势吃掉，实际永远看不到；
/// - `leadingWidget` / `trailingWidget` 展示双方头像：对方在气泡左、自己在右；
/// - `headerWidget` 在消息间隔超过 [kChatTimeDividerGap] 时插入居中时间条。
class _ChatMessageRow extends StatelessWidget {
  final Message message;
  final int index;
  final Animation<double> animation;
  final bool? isRemoved;
  final MessageGroupStatus? groupStatus;

  /// 对方消息的头像；自己的消息为 null（不显示）。
  final Widget? avatar;

  /// 是否在消息上方插入时间分隔条（见 [_ChatPageState._showTimeDivider]）。
  final bool showTimeDivider;

  /// 是否为自己发送（决定时间戳与气泡的左右对齐）。
  final bool isSentByMe;

  final Widget child;

  const _ChatMessageRow({
    required this.message,
    required this.index,
    required this.animation,
    required this.isSentByMe,
    required this.child,
    this.isRemoved,
    this.groupStatus,
    this.avatar,
    this.showTimeDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final time = message.resolvedTime;
    return ChatMessage(
      message: message,
      index: index,
      animation: animation,
      isRemoved: isRemoved,
      groupStatus: groupStatus,
      // 对方头像在气泡左侧、自己的头像在右侧 —— ChatMessage 的 Row 依次摆放
      // leadingWidget / trailingWidget，正好让两侧头像对称。
      leadingWidget: isSentByMe ? null : avatar,
      trailingWidget: isSentByMe ? avatar : null,
      headerWidget: showTimeDivider && time != null
          ? _TimeDivider(time: time)
          : null,
      // 气泡下方不再常显灰字时间戳（观感差）。跨段的时间信息仍由 headerWidget
      // 的居中时间条承载。
      child: child,
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
