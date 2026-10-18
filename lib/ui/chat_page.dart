import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HapticFeedback;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
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
import '../core/models/chat_envelope.dart';
import '../core/models/nickname.dart' show plainNickname;
import '../core/models/session_key.dart' show sessionKeyOf;
import '../core/services/chat_service.dart';
import '../core/services/chat_image.dart'
    show kVoiceCarrierExt, uploadChatImage, uploadChatMedia;
import '../core/services/profile.dart' show ProfileClient;
import '../core/services/voice_clip.dart'
    show voiceDurationSeconds, voiceSecondsLabel;
import '../core/services/dynamics.dart' show DynamicsClient;
import '../core/services/rich_media.dart' show RichMedia, ShareType;
import '../core/services/chat/message_marks.dart' show MessageMarksStore;
import '../core/storage/settings_store.dart' show SettingsKeys, SettingsStore;
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'group_detail_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/emoji_code_image.dart' show EmojiCodeImage;
import 'widgets/emoji_picker.dart' show showEmojiPicker;
import 'widgets/voice_message_bar.dart' show VoiceMessageBar;
import 'widgets/voice_record_dialog.dart' show showVoiceRecordDialog;
import 'widgets/floating_panel.dart' show showFloatingPanel;
import 'widgets/gift_picker.dart' show showGiftPicker;
import 'widgets/app_l10n.dart' show l10nOf;
import 'widgets/rich_text_view.dart';
import '../core/services/image_disk_cache.dart';

part 'chat_page_composer.dart';
part 'chat_page_bubbles.dart';
part 'chat_page_message_row.dart';
part 'chat_page_actions.dart';

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

  /// 是否嵌在「会话列表 + 聊天」双栏布局里（列表就在旁边，不需要返回箭头）。
  ///
  /// 必须由主壳告知：聊天面板自身的宽度是「内容区宽 - 会话列表栏」，永远小于
  /// 双栏断点，所以本页不能用 `MediaQuery` 的窗口宽自己判定 —— 否则在
  /// [700, 760) 这段窗口宽度上会判错（手机横屏正落在这段：主壳走单栏、聊天
  /// 顶掉列表，却不显示返回箭头）。
  final bool wide;

  const ChatPage({
    super.key,
    required this.type,
    required this.sessionId,
    required this.name,
    this.wide = false,
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

  /// 本机消息标记（收藏 / 本机删除）的会话级内存镜像。
  late final MessageMarksStore _marks;

  /// 多选模式：已选中的消息 id；null 表示未进入多选。
  Set<String>? _selectedIds;

  /// 「正在输入」接收侧：对方用过私有信封才会触发（见 [ChatBridge.typingStream]）。
  StreamSubscription<(String, int)>? _typingSub;
  Timer? _typingHideTimer;
  bool _peerTyping = false;

  /// 最近一次发出「正在输入」的时间（发送侧 8 秒限流）。
  DateTime? _lastTypingSentAt;

  /// 草稿落盘防抖：输入停顿 600ms 才写一次库，避免每个按键一次 SQLite 写入。
  Timer? _draftTimer;

  /// 会话内搜索：是否展开搜索栏、当前关键词，以及搜索框控制器。
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  /// 成员选择器是否已弹出（防止刚敲下的 `@` 反复触发）。
  bool _mentionOpen = false;

  /// 发图进行中：防止重复点「图片」触发第二遍上传。
  bool _imageSending = false;

  /// 引用回复的待发信封：点「引用」时记下，下一条发出的消息带上
  /// （走 extend_data；可见前缀照旧进正文，官方客户端也读得懂）。
  MnEnvelope? _pendingEnvelope;

  /// 发语音进行中：与发图同理。
  bool _voiceSending = false;

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
    _marks = ref.read(messageMarksStoreProvider);
    // 「正在输入」：只对当前会话生效，6 秒内没新信号就收起（信号本身不带有效期）。
    _typingSub = _bridge.typingStream.listen((event) {
      if (!mounted || event.$1 != _draftKey) return;
      if (event.$2 == ref.read(myUinProvider)) return; // 自己多端打字不提示
      setState(() => _peerTyping = true);
      _typingHideTimer?.cancel();
      _typingHideTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _peerTyping = false);
      });
    });
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
    // 本机标记（收藏 / 本机删除）先载入再对账：bridge 的 hiddenKeys 钩子读的就是
    // 这份镜像，载入完成后必须再对账一次，否则「本机已删除」的消息会在进会话时
    // 被随历史一起重新渲染出来（服务端仍会把它推回来）。
    unawaited(
      _marks.ensureLoaded(_draftKey).then((_) {
        if (!mounted) return;
        setState(() {});
        _bridge.reconcile(_controller, widget.type, widget.sessionId);
      }),
    );
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
    unawaited(_maybeSendTypingSignal());
  }

  /// 回发「正在输入」信号（零宽字符隐写，可见正文为空）。
  ///
  /// 三个门：正文非空 → **对方用过私有信封**（说明也是 MNChat）→ 距上次 ≥8 秒。
  /// 中间那个门很关键：官方客户端会把空正文当成一条空消息，不能打扰他们；
  /// 限流是因为网关按账号排队，连发会回 `code=9/23`。
  Future<void> _maybeSendTypingSignal() async {
    if (_composerController.text.trim().isEmpty) return;
    if (!_bridge.peerEnvelopeCapable(_draftKey)) return;
    final now = DateTime.now();
    final last = _lastTypingSentAt;
    if (last != null && now.difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastTypingSentAt = now;
    try {
      final payload = attachMnEnvelope(
        '',
        const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
      );
      if (widget.type == ChatSessionType.friend) {
        await _service.sendFriendMessage(widget.sessionId, payload);
      } else {
        await _service.sendGroupMessage(widget.sessionId, payload);
      }
    } catch (_) {
      // 发不出去就算了：这只是个即时提示，不重试也不打扰用户。
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
    _typingSub?.cancel();
    _typingSub = null;
    _typingHideTimer?.cancel();
    _typingHideTimer = null;
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
    _scheduleUnreadResolve();

    return Column(
      children: [
        // 标题栏与会话列表 AppBar 对齐：同主题底色 / 同 toolbarHeight /
        // 左对齐粗体标题；单栏（列表被聊天顶掉）时显示返回箭头回到会话列表，
        // 双栏时不需要（关闭由再次点击当前会话卡片完成）。
        AppBar(
          automaticallyImplyLeading: false,
          leading: widget.wide
              ? null
              : IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () =>
                      ref.read(activeSessionProvider.notifier).close(),
                ),
          title: _selectedIds != null
              ? Text(
                  l10nOf(context)?.selectedCount(_selectedIds!.length) ??
                      '已选 ${_selectedIds!.length} 条',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )
              : _searching
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
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichTextView(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 对方正在输入：只在收到过私有信封的会话里出现。
                    // 放在标题里（两行、min 高度）而不是 AppBar.bottom —— 后者会
                    // 让 AppBar 内部的 Column 在无界高度下断言（见本文件的测试）。
                    if (_peerTyping)
                      Text(
                        l10nOf(context)?.typingIndicator ?? '对方正在输入…',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
          actions: [
            if (_selectedIds != null)
              IconButton(
                tooltip: l10nOf(context)?.commonCancel ?? '取消',
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              ),
            if (_selectedIds == null &&
                widget.type == ChatSessionType.group &&
                !_searching)
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
            if (_selectedIds == null)
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
                // 消息级操作：长按（手机）/ 右键（桌面）弹菜单；点击在多选模式下
                // 切换选中。
                onMessageLongPress: _onMessageLongPress,
                onMessageTap: _onMessageTap,
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
                      onPickImage: _sendImage,
                      onSendVoice: _sendVoice,
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
                        isFavorite: _isFavorite(message),
                        isSelected:
                            _selectedIds?.contains(message.id) ?? false,
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
                      // 与系统无障碍字号**相乘**组合，而不是整体替换：早期写法
                      // 直接覆盖 textScaler，系统字号调到 1.5x/2x 的人只有聊天
                      // 记录这块文字不跟着变大。
                      textScaler: composeTextScaler(
                        MediaQuery.textScalerOf(context),
                        chatFontScale,
                      ),
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
        // 多选模式的操作条（选择时输入区被它顶掉：不该还能打字发消息）。
        if (_selectedIds != null)
          _SelectionBar(
            count: _selectedIds!.length,
            onFavorite: _favoriteSelected,
            onForward: _forwardSelected,
            onDelete: _deleteSelected,
            onCancel: _exitSelection,
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

  /// 发送消息：trim/空值守卫 → 发送 → 本地乐观回显；失败则插入一条
  /// `is_success=0` 的本地消息（气泡带错误标记，长按可重发）。返回是否成功。
  Future<bool> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final service = ref.read(chatServiceProvider);
    // 引用回复的「待发信封」：可见前缀已在正文里（人人可读），结构化引用走
    // extend_data（无正文长度约束，见 sendFriendMessageWithEnvelope）。
    final envelope = _pendingEnvelope;
    _pendingEnvelope = null;
    final extend = envelope == null ? null : encodeMnExtendData(envelope);
    try {
      if (widget.type == ChatSessionType.friend) {
        if (envelope == null) {
          await service.sendFriendMessage(widget.sessionId, trimmed);
        } else {
          await service.sendFriendMessageWithEnvelope(
            widget.sessionId,
            trimmed,
            envelope: envelope,
          );
        }
      } else {
        if (envelope == null) {
          await service.sendGroupMessage(widget.sessionId, trimmed);
        } else {
          await service.sendGroupMessageWithEnvelope(
            widget.sessionId,
            trimmed,
            envelope: envelope,
          );
        }
      }
      // 本地乐观消息：立即回显（ChatBridge 经 eventStream 增量 reconcile 上屏，
      // 无需在此处手动操作 controller）；带 extend_data 才能在回显气泡里也画出引用块。
      service.addLocalMessage(
        widget.type,
        widget.sessionId,
        trimmed,
        extendData: extend,
      );
      // 发出去了就清掉草稿：Composer 此时已把输入框清空，这里显式写一次，
      // 避免「消息已发出、草稿还留在下一句」的错乱。
      _draftTimer?.cancel();
      _saveDraft();
      return true;
    } catch (e) {
      // 失败也要上屏：以 is_success=0 插入一条本地消息（气泡带错误状态），
      // 用户长按即可重发 —— 早先只把内容回填进输入框，关掉会话就彻底没了。
      try {
        service.addLocalMessage(
          widget.type,
          widget.sessionId,
          trimmed,
          isSuccess: false,
          extendData: extend,
        );
      } catch (_) {
        // 连本地回显都失败（未登录等）：退回「回填输入框」这条老路。
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _composerController.text = trimmed;
            _composerController.selection = TextSelection.collapsed(
              offset: trimmed.length,
            );
          });
        }
      }
      _draftTimer?.cancel();
      _saveDraft();
      if (!mounted) return false;
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '发送失败: $e',
            style: TextStyle(color: scheme.onError),
          ),
          backgroundColor: scheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
      return false;
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

  /// 发图：选图 → 预签名分片直传 → 发送「图片」分享卡。
  ///
  /// 好友走 [ChatService.sendImageShare]，群聊走
  /// [ChatService.sendGroupImageShare]（群通道没有 `issys`）。
  Future<void> _sendImage() async {
    if (_imageSending) return;
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择要发送的图片',
      type: FileType.image,
    );
    if (picked == null || !mounted) return;
    setState(() => _imageSending = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await uploadChatImage(
        ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t),
        bytes: bytes,
        fileName: picked.name,
      );
      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片上传失败，请稍后重试')),
        );
        return;
      }
      final service = ref.read(chatServiceProvider);
      if (widget.type == ChatSessionType.group) {
        await service.sendGroupImageShare(widget.sessionId, url: url);
      } else {
        await service.sendImageShare(widget.sessionId, url: url);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _imageSending = false);
    }
  }

  /// 发语音：先选「录音」或「选文件」，再统一走 上传 → 私有信封 发出。
  ///
  /// 传输与发图共用 [uploadChatMedia]（同一条预签名分片直传）；载荷走
  /// `MnEnvelopeKind.voice` → `{url, seconds}`，所以**官方客户端看到的是**
  /// `[语音] 3″` 这样的可读正文，只有 MNChat 之间会渲染成可点的语音条。
  Future<void> _sendVoice() async {
    if (_voiceSending) return;
    if (ref.read(authProvider).auth == null) return;
    final record = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: voiceRecordEntryKey,
              leading: const Icon(Icons.mic),
              title: const Text('录音'),
              subtitle: const Text('现在用麦克风录一段'),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            ListTile(
              key: voicePickFileEntryKey,
              leading: const Icon(Icons.folder_open),
              title: const Text('选择音频文件'),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    if (record == null || !mounted) return;

    final Uint8List bytes;
    final String fileName;
    final String defaultExt;
    if (record) {
      final recorded = await showVoiceRecordDialog(context);
      if (recorded == null || !mounted) return;
      bytes = recorded;
      fileName = 'voice.wav';
      defaultExt = 'wav';
    } else {
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择要发送的语音文件',
        type: FileType.audio,
      );
      if (picked == null || !mounted) return;
      bytes = await picked.readAsBytes();
      fileName = picked.name;
      defaultExt = 'mp3';
    }
    await _sendVoiceBytes(bytes, fileName: fileName, defaultExt: defaultExt);
  }

  /// 上传音频并作为语音消息发出。
  ///
  /// 载荷走信封（`extend_data`）：**实测服务端会保留并随 live push 转发自定义键**
  /// （2026-10-17 三发三中：自定义 `mn` 键在对端在线时原样到达；対端**离线**时
  /// 走 `chat_query` 离线队列取回则不带 extend_data —— 与游戏自己的礼物卡同一条路）。
  ///
  /// 音频不按 `.wav` 上传：存储 CDN **只发布图片扩展名**（七臂实测 png/jpg/webp
  /// 200，m4a/mp4/ogg/amr 404），所以套 [kVoiceCarrierExt]；播放靠内容嗅探不受影响。
  Future<void> _sendVoiceBytes(
    Uint8List bytes, {
    required String fileName,
    required String defaultExt,
  }) async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) return;
    setState(() => _voiceSending = true);
    try {
      final seconds = voiceDurationSeconds(bytes);
      final url = await uploadChatMedia(
        ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t),
        bytes: bytes,
        fileName: fileName,
        defaultExt: defaultExt,
        // 音频没有可发布的扩展名 → 套图片扩展名上传（见 kVoiceCarrierExt）。
        forceExt: kVoiceCarrierExt,
      );
      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音上传失败，请稍后重试')),
        );
        return;
      }
      final visible =
          seconds > 0 ? '[语音] ${voiceSecondsLabel(seconds)}' : '[语音]';
      // 信封走 extend_data：URL 载荷远超正文 128 字节上限（会被服务端回 13）。
      final envelope = MnEnvelope(MnEnvelopeKind.voice, <String, Object?>{
        'url': url,
        'seconds': seconds,
      });
      final service = ref.read(chatServiceProvider);
      if (widget.type == ChatSessionType.group) {
        await service.sendGroupMessageWithEnvelope(
          widget.sessionId,
          visible,
          envelope: envelope,
        );
      } else {
        await service.sendFriendMessageWithEnvelope(
          widget.sessionId,
          visible,
          envelope: envelope,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _voiceSending = false);
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

  // ── 消息级操作（长按菜单 / 多选）────────────────────────────────────────

  /// 消息在本机标记表里的定位：与服务端存储口径一致（发送者 uin + epoch 秒）。
  ///
  /// `chat/message_adapter.dart` 构造 [Message] 时把 `time`（秒）乘 1000 放进
  /// `createdAt`，所以这里除回来就是存库用的秒（毫秒时间戳与时区无关）。
  (int, int) _markLocator(Message m) {
    final uin = int.tryParse(m.authorId) ?? 0;
    final ms = m.createdAt?.millisecondsSinceEpoch ?? 0;
    return (uin, ms ~/ 1000);
  }

  bool _isFavorite(Message m) {
    final (uin, time) = _markLocator(m);
    return _marks.isFavorite(_draftKey, uin, time);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  /// 长按一条消息：弹操作菜单（桌面右键走的是同一个回调）。
  Future<void> _onMessageLongPress(
    BuildContext context,
    Message message, {
    required int index,
    required LongPressStartDetails details,
  }) async {
    // 触觉反馈：手机上是真震动，桌面端是 no-op。
    unawaited(HapticFeedback.mediumImpact());
    final action = await showMessageActionMenu(
      context,
      position: details.globalPosition,
      isMine: message.authorId == ref.read(myUinProvider).toString(),
      isSystem: message is SystemMessage,
      hasText: _searchableText(message).trim().isNotEmpty,
      isFavorite: _isFavorite(message),
      canResend: message.resolvedStatus == MessageStatus.error,
    );
    if (!mounted || action == null) return;
    await _runMessageAction(action, message);
  }

  /// 点消息：多选模式下切换选中；非多选模式保持原行为（什么都不做）。
  void _onMessageTap(
    BuildContext context,
    Message message, {
    required int index,
    required TapUpDetails details,
  }) {
    final selected = _selectedIds;
    if (selected == null) return;
    setState(() {
      if (!selected.remove(message.id)) selected.add(message.id);
      if (selected.isEmpty) _selectedIds = null;
    });
  }

  Future<void> _runMessageAction(MessageAction action, Message message) async {
    switch (action) {
      case MessageAction.copy:
        // 跨 await 用 context 会被 use_build_context_synchronously 拦下（fatal-infos
        // 门禁），因此文案在 await 之前取好。
        final copiedLabel = l10nOf(context)?.toastCopied ?? '已复制';
        await Clipboard.setData(ClipboardData(text: _searchableText(message)));
        unawaited(HapticFeedback.selectionClick());
        _toast(copiedLabel);
      case MessageAction.quote:
        // 可见前缀进输入框（官方客户端也读得懂），结构化引用等发送时走
        // extend_data；两条载体同时给，老版本 MNChat 仍能靠隐写读出来。
        _pendingEnvelope = MnEnvelope(MnEnvelopeKind.quote, <String, Object?>{
          'text': _searchableText(message).trim(),
          'uin': int.tryParse(message.authorId) ?? 0,
        });
        _insertText(_quotePrefixFor(message));
      case MessageAction.forward:
        await _forwardMessages(<Message>[message]);
      case MessageAction.multiSelect:
        setState(() => _selectedIds = <String>{message.id});
      case MessageAction.favorite:
        await _setFavorite(message, true);
      case MessageAction.unfavorite:
        await _setFavorite(message, false);
      case MessageAction.resend:
        await _resend(message);
      case MessageAction.deleteLocal:
        await _deleteLocal(<Message>[message]);
    }
  }

  /// 引用回复的前缀文案 + 私有信封。
  ///
  /// 迷你世界聊天协议没有「引用」字段（反编译 `friendservice.lua` 里既无撤回
  /// 也无引用类消息），所以引用只能以**可读文本**随回复一起发出：对方——包括
  /// 官方客户端——看到的是引用块加我的回复，不依赖任何私有字段。
  ///
  /// 在此之上再隐写一份结构化引用（零宽字符，官方客户端看不见）：MNChat 收到后
  /// 能把它渲染成真正的引用块。
  String _quotePrefixFor(Message m) {
    final mine = m.authorId == ref.read(myUinProvider).toString();
    var body = _searchableText(m).trim();
    if (body.length > 60) body = '${body.substring(0, 60)}…';
    final visible = '「${mine ? '我' : _senderNameOf(m)}：$body」\n';
    return attachMnEnvelope(
      visible,
      MnEnvelope(MnEnvelopeKind.quote, {
        'text': body,
        'uin': int.tryParse(m.authorId) ?? 0,
      }),
    );
  }

  /// 一条消息的发送方显示名（好友会话用会话名；群会话查成员资料，取不到回退
  /// 迷你号）。昵称可能带富文本标记，走 [plainNickname] 清洗。
  String _senderNameOf(Message m) {
    final uin = int.tryParse(m.authorId) ?? 0;
    if (widget.type == ChatSessionType.friend) {
      return widget.name.isNotEmpty ? widget.name : '$uin';
    }
    final member = _service.groupMemberProfile(widget.sessionId, uin);
    final nick = plainNickname(member?.nickname ?? '').trim();
    return nick.isNotEmpty ? nick : '$uin';
  }

  /// 转发若干条消息到其它会话（文本转发；卡片类消息转发其正文）。
  Future<void> _forwardMessages(List<Message> messages) async {
    final sessions =
        (ref.read(sessionListProvider).asData?.value.sessions ??
                const <ChatSession>[])
            .where((s) => !(s.type == widget.type && s.id == widget.sessionId))
            .toList();
    if (!mounted) return;
    if (sessions.isEmpty) {
      _toast(l10nOf(context)?.forwardNoTarget ?? '没有可转发的好友或群');
      return;
    }
    final target = await showModalBottomSheet<ChatSession>(
      context: context,
      builder: (ctx) =>
          SafeArea(child: _ForwardTargetPicker(sessions: sessions)),
    );
    if (!mounted || target == null) return;
    var text = messages
        .map(_searchableText)
        .where((t) => t.trim().isNotEmpty)
        .join('\n');
    if (text.trim().isEmpty) {
      _toast('这条消息没有可转发的文本');
      return;
    }
    if (messages.length > 1) text = '转发聊天记录：\n$text';
    final service = ref.read(chatServiceProvider);
    try {
      if (target.type == ChatSessionType.friend) {
        await service.sendFriendMessage(target.id, text);
      } else {
        await service.sendGroupMessage(target.id, text);
      }
      service.addLocalMessage(target.type, target.id, text);
      if (!mounted) return;
      setState(() => _selectedIds = null);
      _toast(l10nOf(context)?.toastForwarded ?? '已转发');
    } catch (e) {
      _toast('转发失败: $e');
    }
  }

  Future<void> _setFavorite(Message m, bool on) async {
    final (uin, time) = _markLocator(m);
    await _marks.setFavorite(_draftKey, uin, time, on);
    if (!mounted) return;
    setState(() {});
    final l10n = l10nOf(context);
    _toast(
      on
          ? (l10n?.toastFavorited ?? '已收藏')
          : (l10n?.toastUnfavorited ?? '已取消收藏'),
    );
  }

  /// 本机删除（仅本机隐藏）：确认后写 hidden 标记并对账，消息立即从列表消失。
  Future<void> _deleteLocal(List<Message> messages) async {
    if (messages.isEmpty) return;
    final l10n = l10nOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.deleteLocalConfirmTitle ?? '在本机删除消息？'),
        content: Text(
          l10n?.deleteLocalConfirmBody ??
              '只影响本机记录，对方和其他设备仍能看到这条消息。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n?.commonCancel ?? '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n?.actionDelete ?? '删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    for (final m in messages) {
      final (uin, time) = _markLocator(m);
      await _marks.setHidden(_draftKey, uin, time, true);
    }
    if (!mounted) return;
    setState(() => _selectedIds = null);
    _bridge.reconcile(_controller, widget.type, widget.sessionId);
    _toast(l10nOf(context)?.toastDeletedLocal ?? '已在本机删除');
  }

  /// 重发失败的消息：发成功后再把那条失败记录在本机隐藏，避免留下两条一样的。
  Future<void> _resend(Message m) async {
    final text = _searchableText(m).trim();
    if (text.isEmpty) {
      _toast('这条消息没有可重发的文本');
      return;
    }
    final ok = await _send(text);
    if (!mounted || !ok) return;
    final (uin, time) = _markLocator(m);
    await _marks.setHidden(_draftKey, uin, time, true);
    if (!mounted) return;
    _bridge.reconcile(_controller, widget.type, widget.sessionId);
  }

  void _exitSelection() => setState(() => _selectedIds = null);

  /// 当前多选中的消息（按时间序）。
  List<Message> get _selectedMessages {
    final ids = _selectedIds;
    if (ids == null || ids.isEmpty) return const <Message>[];
    return [
      for (final m in _controller.messages)
        if (ids.contains(m.id)) m,
    ];
  }

  Future<void> _favoriteSelected() async {
    final picked = _selectedMessages;
    if (picked.isEmpty) return;
    for (final m in picked) {
      final (uin, time) = _markLocator(m);
      await _marks.setFavorite(_draftKey, uin, time, true);
    }
    if (!mounted) return;
    setState(() => _selectedIds = null);
    _toast(l10nOf(context)?.toastFavorited ?? '已收藏');
  }

  Future<void> _forwardSelected() async {
    final picked = _selectedMessages;
    if (picked.isEmpty) return;
    await _forwardMessages(picked);
  }

  Future<void> _deleteSelected() async {
    final picked = _selectedMessages;
    if (picked.isEmpty) return;
    await _deleteLocal(picked);
  }
}
