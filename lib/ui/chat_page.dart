import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import '../core/models/nickname.dart' show plainNickname;
import '../core/models/session_key.dart' show sessionKeyOf;
import '../core/services/chat_service.dart';
import '../core/services/dynamics.dart' show DynamicsClient;
import '../core/services/rich_media.dart' show RichMedia, ShareType;
import '../core/storage/settings_store.dart' show SettingsKeys, SettingsStore;
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'group_detail_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/emoji_code_image.dart' show EmojiCodeImage;
import 'widgets/emoji_picker.dart' show showEmojiPicker;
import 'widgets/floating_panel.dart' show showFloatingPanel;
import 'widgets/gift_picker.dart' show showGiftPicker;
import 'widgets/rich_text_view.dart';
import '../core/services/image_disk_cache.dart';

part 'chat_page_composer.dart';
part 'chat_page_bubbles.dart';
part 'chat_page_message_row.dart';

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

  /// 设置存储（草稿用）。测试环境可能未注入 databaseProvider → null，草稿逻辑整体跳过。
  SettingsStore? _settings;

  /// 本会话草稿的存储 key（`friend_123` / `group_456`）。
  late final String _draftKey = sessionKeyOf(widget.type, widget.sessionId);

  /// 草稿落盘防抖：输入停顿 600ms 才写一次库，避免每个按键一次 SQLite 写入。
  Timer? _draftTimer;

  /// 会话内搜索：是否展开搜索栏、当前关键词，以及搜索框控制器。
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  /// 成员选择器是否已弹出（防止刚敲下的 `@` 反复触发）。
  bool _mentionOpen = false;

  /// 进入会话时的未读数，以及据此定位出的「第一条未读消息」id。
  ///
  /// 未读数必须在标记已读**之前**取（见 initState），否则自己一进会话就归零。
  int _unreadAtOpen = 0;
  String? _firstUnreadId;
  bool _unreadResolved = false;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(chatBridgeProvider);
    _controller = _bridge.controllerFor(widget.type, widget.sessionId);
    // 进入会话即与最新历史对账一次：会话关闭期间到达的消息（那时没有控制器）、
    // 或历史拉回导致的增删，都要在这里补齐 —— 否则要等到「发一条消息」触发的
    // 那次 reconcile 才会补上，表现为「只收不发就吞消息」。幂等（无差异走 NoOp）。
    _bridge.reconcile(_controller, widget.type, widget.sessionId);
    // 提前持有：Riverpod 3.x 禁止在 dispose 中再访问 ref。
    _service = ref.read(chatServiceProvider);
    // 未读边界：现在取（setViewing 会把未读清零，取晚了永远是 0）。
    try {
      final snap = ref.read(sessionListProvider).asData?.value;
      for (final s in snap?.sessions ?? const <ChatSession>[]) {
        if (s.type == widget.type && s.id == widget.sessionId) {
          _unreadAtOpen = s.unreadCount;
          break;
        }
      }
    } catch (_) {
      _unreadAtOpen = 0;
    }
    // 草稿：读回上次没发出去的内容，并在输入变化时防抖写回。
    try {
      _settings = ref.read(settingsProvider);
    } catch (_) {
      _settings = null; // 测试环境未注入 databaseProvider
    }
    _composerController.addListener(_onComposerChanged);
    _restoreDraft();
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

  /// 恢复上次未发送的草稿。
  ///
  /// 只在输入框还空着时回填：异步读库期间用户可能已经开始打字，不能覆盖他刚敲的。
  void _restoreDraft() {
    final settings = _settings;
    if (settings == null) return;
    settings
        .draft(_draftKey)
        .then((text) {
          if (!mounted || text == null) return;
          if (_composerController.text.isNotEmpty) return;
          _composerController.text = text;
          _composerController.selection = TextSelection.collapsed(
            offset: text.length,
          );
        })
        .catchError((Object _) {});
  }

  void _onComposerChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
    // 群聊里刚敲下 `@` 就把成员选择器弹出来（与常见 IM 一致）。
    if (!_mentionOpen &&
        widget.type == ChatSessionType.group &&
        _composerController.text.endsWith('@')) {
      unawaited(_showMentionPicker(fromTyped: true));
    }
  }

  /// 群成员候选（昵称优先，没资料就显示迷你号），按昵称排序、自己排最后。
  List<({int uin, String name})> _mentionCandidates() {
    final myUin = ref.read(myUinProvider);
    final list = <({int uin, String name})>[];
    for (final uin in _service.groupMembers(widget.sessionId)) {
      final nick = plainNickname(
        _service.groupMemberProfile(widget.sessionId, uin)?.nickname ?? '',
      ).trim();
      list.add((uin: uin, name: nick.isEmpty ? '$uin' : nick));
    }
    list.sort((a, b) {
      if (a.uin == myUin) return 1;
      if (b.uin == myUin) return -1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// @群成员：列出群成员，选中后把 `@昵称 ` 插到光标处。
  ///
  /// [fromTyped] 表示是用户刚敲下 `@` 触发的 —— 选中后要先删掉那个 `@`，
  /// 否则会插成 `@@昵称`。
  Future<void> _showMentionPicker({bool fromTyped = false}) async {
    if (!mounted) return;
    final members = _mentionCandidates();
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('还没拉到群成员名单，稍后再试'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    _mentionOpen = true;
    final name = await showFloatingPanel<String>(
      context,
      builder: (ctx, close) =>
          _MentionPicker(members: members, onPick: (n) => close(n)),
    );
    _mentionOpen = false;
    if (!mounted || name == null) return;
    if (fromTyped) {
      final t = _composerController.text;
      final sel = _composerController.selection;
      final at = (sel.isValid ? sel.start : t.length).clamp(0, t.length);
      if (at > 0 && t[at - 1] == '@') {
        _composerController.value = TextEditingValue(
          text: t.replaceRange(at - 1, at, ''),
          selection: TextSelection.collapsed(offset: at - 1),
        );
      }
    }
    _insertText('@$name ');
  }

  /// 把输入框当前内容写进草稿（空白即清空该会话的草稿）。
  void _saveDraft() {
    final settings = _settings;
    if (settings == null) return;
    unawaited(
      settings
          .setDraft(_draftKey, _composerController.text)
          .catchError((Object _) {}),
    );
  }

  /// 取消息的可搜索 / 可复制文本。
  ///
  /// 文本消息直接取正文；卡片类（礼物 / 动态分享 / 房间邀请 …）的正文在
  /// `metadata['text']` 里（见 `chat/message_adapter.dart` 的映射）。
  static String _searchableText(Message m) {
    if (m is TextMessage) return m.text;
    final t = m.metadata?['text'];
    return t is String ? t : '';
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  /// 搜索命中（时间倒序，最多 100 条）。
  List<Message> _searchHits(String query) {
    if (query.isEmpty) return const [];
    final all = _controller.messages;
    final hits = <Message>[];
    for (var i = all.length - 1; i >= 0 && hits.length < 100; i--) {
      final m = all[i];
      if (m.deletedAt != null) continue;
      if (_searchableText(m).toLowerCase().contains(query)) hits.add(m);
    }
    return hits;
  }

  /// 会话内消息搜索面板。
  ///
  /// 这里做的是「找到并读全文」：命中按时间倒序列出，点一条看完整正文并可复制。
  /// flutter_chat_ui 的 `ChatAnimatedList` 没有暴露「滚动到某条消息」的能力，
  /// 所以这一版**不做**点击后滚动定位 —— 与其做一个跳不准的定位，
  /// 不如把内容给全（长消息在气泡里本来也是截断显示的）。
  Widget _buildSearchPanel(BuildContext context, ColorScheme scheme) {
    final query = _query.trim().toLowerCase();
    final hits = _searchHits(query);
    final theme = Theme.of(context);
    final caption = query.isEmpty
        ? '输入关键词搜索本会话消息'
        : (hits.isEmpty
              ? '没有匹配的消息'
              : '找到 ${hits.length} 条${hits.length >= 100 ? '（只列出最近 100 条）' : ''}');

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      color: scheme.surfaceContainerHighest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    caption,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (query.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    child: const Text('清空'),
                  ),
              ],
            ),
          ),
          if (hits.isNotEmpty)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: hits.length,
                itemBuilder: (context, i) => _SearchHitTile(
                  message: hits[i],
                  query: query,
                  isMine:
                      hits[i].authorId == ref.read(myUinProvider).toString(),
                  onTap: () => _showSearchHit(hits[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 点搜索结果：弹出完整正文（列表里是截断的），可复制。
  Future<void> _showSearchHit(Message m) async {
    final text = _searchableText(m);
    final mine = m.authorId == ref.read(myUinProvider).toString();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mine ? '我发出的消息' : '对方的消息'),
        content: SingleChildScrollView(
          child: SelectableText(text.isEmpty ? '（无文本内容）' : text),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 定位「第一条未读消息」：历史还没加载完，所以只能首帧之后再算一次。
  void _scheduleUnreadResolve() {
    if (_unreadResolved || _unreadAtOpen <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _unreadResolved) return;
      final msgs = _controller.messages;
      if (msgs.length >= _unreadAtOpen) {
        _unreadResolved = true;
        setState(() => _firstUnreadId = msgs[msgs.length - _unreadAtOpen].id);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 离开会话：清空「正在查看」并把刚在看的会话补标已读 —— 否则停留期间到达的
    // 消息会一直留在未读数里，返回列表后红点消不掉（见 [ChatService.setViewing]）。
    _service.setViewing(null, null, autoRead: _autoRead);
    // 释放本会话控制器，避免 ChatBridge 的控制器映射随会话开关累积泄漏。
    _bridge.release(widget.type, widget.sessionId);
    // 离开会话立刻落盘一次草稿：防抖窗口内退出会丢掉最后几个字。
    _draftTimer?.cancel();
    _saveDraft();
    _composerController.removeListener(_onComposerChanged);
    _composerController.dispose();
    _searchController.dispose();
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
    _scheduleUnreadResolve();

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
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: '搜索本会话消息',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                )
              : RichTextView(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          actions: [
            if (widget.type == ChatSessionType.group && !_searching)
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
            IconButton(
              tooltip: _searching ? '退出搜索' : '搜索消息',
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
            ),
          ],
        ),
        const Divider(height: 1),
        if (_searching) _buildSearchPanel(context, scheme),
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
                      // @成员只在群聊里给：好友会话没有成员可 @。
                      onMention: widget.type == ChatSessionType.group
                          ? _showMentionPicker
                          : null,
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
                        // 进入会话时的未读边界。
                        showUnreadDivider:
                            _firstUnreadId != null &&
                            message.id == _firstUnreadId,
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
      // 发出去了就清掉草稿：Composer 此时已把输入框清空，这里显式写一次，
      // 避免「消息已发出、草稿还留在下一句」的错乱。
      _draftTimer?.cancel();
      _saveDraft();
    } catch (e) {
      if (!mounted) return;
      // 发送失败：Composer 在回调前已经把输入框清空了，不把内容塞回去用户就得
      // 重新敲一遍。这里回填 + 给一个「重试」，同时把草稿存下来（万一他直接关掉
      // 会话，内容也不丢）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _composerController.text = trimmed;
        _composerController.selection = TextSelection.collapsed(
          offset: trimmed.length,
        );
        _saveDraft();
      });
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '发送失败: $e',
            style: TextStyle(color: scheme.onError),
          ),
          backgroundColor: scheme.error,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '重试',
            textColor: scheme.onError,
            onPressed: () {
              _composerController.clear();
              unawaited(_send(trimmed));
            },
          ),
        ),
      );
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
