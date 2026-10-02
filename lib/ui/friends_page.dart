import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/friend_tag.dart';
import '../core/models/messages.dart';
import '../core/services/chat_service.dart' show SessionSnapshot;
import '../core/services/partner.dart';
import '../core/services/rich_media.dart' show RichMedia;
import '../state/providers.dart';
import 'friend_request_page.dart' show FriendRequestPage, showAddFriendDialog;
import 'blacklist_page.dart';
import 'family_page.dart';
import 'my_qr_page.dart';
import 'partner_page.dart';
import 'player_home_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/friend_filter_dialog.dart';
import 'widgets/friend_tag_dialog.dart';
import 'widgets/head_frame.dart';
import 'widgets/partner_badges.dart';
import 'widgets/session_menu.dart';
import 'widgets/session_player_info_popup.dart';
import 'widgets/rich_text_view.dart';

/// 好友页 —— 通讯录：全部联系人 + 关系分类 + 好友申请入口。
///
/// 数据源与"会话"共享 ChatService 的好友会话（每个好友一条 session），
/// 展示昵称 / 迷你号 / 在线游玩状态 / 关系。点击任意好友直接进入聊天。
class FriendsPage extends ConsumerStatefulWidget {
  /// 点击好友（uin）发起聊天时回调，供外层导航切换到会话 tab。
  final ValueChanged<int>? onOpenChat;

  const FriendsPage({super.key, this.onOpenChat});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

/// 左侧分类。
enum _FriendCat { friend, follow, group }

/// 排序方式 —— 文案对齐游戏 `friendSortText`（stringdef 156007-156010）。
enum _SortMode {
  defaultOrder('好友默认排序'),
  tacitDesc('默契度从高到低'),
  loginDesc('登录从近到远'),
  loginAsc('登录从远到近');

  const _SortMode(this.label);
  final String label;
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  String _search = '';

  /// 窄屏：搜索平时只是一个按钮，点开才展开成输入框并隐藏其它控件
  /// （工具条一行放不下所有控件，400dp 内会溢出）。
  bool _searchOpen = false;

  _FriendCat _cat = _FriendCat.friend;
  _SortMode _sort = _SortMode.defaultOrder;

  /// 筛选（通用多选 + 标签多选，见 friend_filter_dialog.dart）。
  FriendFilterState _filter = const FriendFilterState();

  /// 批量管理：勾选中的好友（非空即处于批量模式）。
  final Set<int> _selected = <int>{};
  bool _batchMode = false;

  /// 开了「上线通知」的好友（筛选用；`SettingsStore` 是按 uin 分键存的，
  /// 没有批量读接口，这里在进页面 / 改筛选时一次性读进内存）。
  Set<int> _notifyUins = <int>{};

  /// 从会话快照取全部会话。
  List<ChatSession> _all(SessionSnapshot? snap) => snap?.sessions ?? const [];

  /// 当前分类下的会话。
  List<ChatSession> _ofCategory(List<ChatSession> all) {
    switch (_cat) {
      case _FriendCat.friend:
        return [
          for (final s in all)
            if (s.type == ChatSessionType.friend && (s.relation & 8) != 0) s,
        ];
      case _FriendCat.follow:
        return [
          for (final s in all)
            if (s.type == ChatSessionType.friend && (s.relation & 16) != 0) s,
        ];
      case _FriendCat.group:
        return [
          for (final s in all)
            if (s.type == ChatSessionType.group) s,
        ];
    }
  }

  /// 筛选：搜索（昵称/迷你号）+ 通用条件 + 标签，条件之间都是 AND
  /// （对齐 `main_newfriendsmgrmodel.lua:117-143`）。
  List<ChatSession> _applyFilter(
    List<ChatSession> pool,
    PartnerDirectory directory,
    Map<int, Set<int>> tagIndex,
  ) {
    return [
      for (final s in pool)
        if (_matches(s, directory, tagIndex)) s,
    ];
  }

  bool _matches(
    ChatSession s,
    PartnerDirectory directory,
    Map<int, Set<int>> tagIndex,
  ) {
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      if (!s.name.toLowerCase().contains(q) && !'${s.id}'.contains(q)) {
        return false;
      }
    }
    // 通用筛选对群无效（群没有在线/拍档/标签）。
    if (_cat == _FriendCat.group) return true;

    for (final c in _filter.common) {
      switch (c) {
        case FriendFilterCommon.online:
          if (!s.isOnline) return false;
        case FriendFilterCommon.partner:
          // 拍档判定用 lab > 0（非拍档也会出现在 get_list 里）。
          if (!directory.isPartner(s.id)) return false;
        case FriendFilterCommon.onlineNotify:
          // 本地设置里的开关（游戏用好友列表的 notify_flag + 拍档兜底，
          // 本客户端只写本地与 set_online_notify_flag，没有回读）。
          if (!_onlineNotifyOf(s.id)) return false;
        case FriendFilterCommon.invitedMe:
          if (!_invitedMe(s)) return false;
      }
    }
    if (_filter.tagIds.isNotEmpty) {
      final mine = tagIndex[s.id] ?? const <int>{};
      for (final id in _filter.tagIds) {
        if (!mine.contains(id)) return false;
      }
    }
    return true;
  }

  bool _onlineNotifyOf(int uin) => _notifyUins.contains(uin);

  /// 最近有没有给我发过"邀请一起玩"（`InviteJoinRoom*` / `InviteJoinTeam`）。
  bool _invitedMe(ChatSession s) {
    final ext = s.lastMessage?.extendData;
    if (ext == null || ext.isEmpty) return false;
    final media = RichMedia.decode(ext);
    return media != null && media.isRoomInvite;
  }

  /// 排序（对齐 `newfriendmgr.lua:631-692`）：
  /// - 默认：在线优先，离线里未读 → 登录时间近 → 昵称；
  /// - 默契度从高到低（拍档目录里的 tacitnum，稳定回退原顺序）；
  /// - 登录从近到远 / 从远到近（在线组在前，组内按 lastLoginTime）。
  List<ChatSession> _applySort(
    List<ChatSession> list,
    PartnerDirectory directory,
  ) {
    final sorted = [...list];
    int byName(ChatSession a, ChatSession b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    switch (_sort) {
      case _SortMode.defaultOrder:
        sorted.sort((a, b) {
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          if (a.unreadCount != b.unreadCount) {
            return b.unreadCount.compareTo(a.unreadCount);
          }
          if (a.isOnline) {
            final at = a.lastMessage?.time ?? 0;
            final bt = b.lastMessage?.time ?? 0;
            if (at != bt) return bt.compareTo(at);
          } else if (a.lastLoginTime != b.lastLoginTime) {
            return b.lastLoginTime.compareTo(a.lastLoginTime);
          }
          return byName(a, b);
        });
      case _SortMode.tacitDesc:
        final idx = <int, int>{
          for (var i = 0; i < sorted.length; i++) sorted[i].id: i,
        };
        sorted.sort((a, b) {
          final ta = directory.tacitOf(a.id);
          final tb = directory.tacitOf(b.id);
          if (ta != tb) return tb.compareTo(ta);
          return (idx[a.id] ?? 0).compareTo(idx[b.id] ?? 0);
        });
      case _SortMode.loginDesc:
        sorted.sort((a, b) {
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          if (a.lastLoginTime != b.lastLoginTime) {
            return b.lastLoginTime.compareTo(a.lastLoginTime);
          }
          return byName(a, b);
        });
      case _SortMode.loginAsc:
        sorted.sort((a, b) {
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          if (a.lastLoginTime != b.lastLoginTime) {
            return a.lastLoginTime.compareTo(b.lastLoginTime);
          }
          return byName(a, b);
        });
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = ref.watch(sessionListProvider).asData?.value;
    final reqCount = ref.watch(friendRequestCountProvider);
    final pool = _ofCategory(_all(snap));
    final onlineCount = pool.where((s) => s.isOnline).length;

    final directory =
        ref.watch(partnerDirectoryProvider).asData?.value ??
        PartnerDirectory.empty;
    final tags = ref.watch(friendTagPoolProvider).asData?.value ??
        const <FriendTag>[];
    final tagIndex = friendTagIndex(tags);

    final filtered = _applyFilter(pool, directory, tagIndex);
    final sorted = _applySort(filtered, directory);

    return Scaffold(
      appBar: AppBar(
        title: const Text('好友', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // 好友申请（红点）
          IconButton(
            tooltip: '好友申请',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FriendRequestPage()),
            ),
            icon: Badge(
              isLabelVisible: reqCount > 0,
              label: Text('$reqCount'),
              child: const Icon(Icons.person_add_alt_1_outlined),
            ),
          ),
          // 添加好友
          IconButton(
            tooltip: '添加好友',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => showAddFriendDialog(context, ref),
          ),
          // 更多：黑名单 / 我的二维码
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) {
              switch (v) {
                case 'blacklist':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BlacklistPage()),
                  );
                case 'qr':
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const MyQrPage()));
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'blacklist',
                child: ListTile(
                  leading: Icon(Icons.block),
                  title: Text('黑名单'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'qr',
                child: ListTile(
                  leading: Icon(Icons.qr_code),
                  title: Text('我的二维码'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.listContent),
          child: Column(
            children: [
              _buildToolbar(theme, onlineCount, pool.length),
              const Divider(height: 1),
              // 手机（紧凑宽度）：分类改为列表**上方**的横向 chip 行，把整屏宽度
              // 让给好友列表；宽屏保留左侧竖排分类栏。
              if (isCompactWidth(context)) ...[
                _buildCategoryChips(theme),
                const Divider(height: 1),
              ],
              if (_batchMode) _buildBatchBar(theme),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isCompactWidth(context)) ...[
                      _buildCategoryRail(theme),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: sorted.isEmpty
                          ? _EmptyFriends(
                              isGroup: _cat == _FriendCat.group,
                              hasData: pool.isNotEmpty,
                              onAddFriend: () =>
                                  showAddFriendDialog(context, ref),
                            )
                          : ListView.separated(
                              // 行改为圆角卡片后不再用 Divider 分隔；四边内缩到
                              // 与 CardThemeData.margin 一致：左右避免圆角贴住
                              // 分类栏 / VerticalDivider，上下避免首/末卡片贴住
                              // 工具栏分隔线与窗口底边。
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.sm,
                              ),
                              itemCount: sorted.length,
                              // 行间留白与 CardThemeData.margin.vertical 一致。
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (context, i) {
                                final f = sorted[i];
                                return _FriendTile(
                                  session: f,
                                  batchMode: _batchMode,
                                  selected: _selected.contains(f.id),
                                  onSelectToggle: () => setState(() {
                                    _selected.contains(f.id)
                                        ? _selected.remove(f.id)
                                        : _selected.add(f.id);
                                  }),
                                  onTap: () {
                                    if (_batchMode) {
                                      setState(() {
                                        _selected.contains(f.id)
                                            ? _selected.remove(f.id)
                                            : _selected.add(f.id);
                                      });
                                      return;
                                    }
                                    _open(f);
                                  },
                                  onLongPress: (pos) => _showFriendMenu(f, pos),
                                  // 桌面端右键打开同一菜单
                                  onSecondaryTap: (pos) => _showFriendMenu(f, pos),
                                  // 点击头像：玩家简要信息浮窗（仅好友）
                                  onAvatarTap: f.type == ChatSessionType.friend
                                      ? (pos) => _showPlayerInfo(f, pos)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开筛选对话框（通用 4 项 + 标签）。
  Future<void> _openFilterDialog() async {
    final tags = ref.read(friendTagPoolProvider).asData?.value ?? const [];
    final next = await showFriendFilterDialog(
      context,
      current: _filter,
      tags: tags,
      onCreateTag: () async {
        Navigator.of(context).pop();
        await showFriendTagDialog(context, ref, uins: const []);
      },
    );
    if (next == null || !mounted) return;
    setState(() => _filter = next);
    await _loadNotifyFlags();
  }

  /// 批量操作条：打标签 / 清除标签 / 上线通知。
  Widget _buildBatchBar(ThemeData theme) {
    final count = _selected.length;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Text('已选 $count 人', style: theme.textTheme.labelMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: count == 0
                  ? null
                  : () => showFriendTagDialog(
                      context,
                      ref,
                      uins: _selected.toList(),
                    ),
              icon: const Icon(Icons.label_outline, size: 16),
              label: const Text('打标签'),
            ),
            TextButton.icon(
              onPressed: count == 0 ? null : _clearTagsForSelected,
              icon: const Icon(Icons.label_off_outlined, size: 16),
              label: const Text('清除标签'),
            ),
            // 对齐游戏 `btn_multSetOnlineNotify`：批量开「上线通知」。
            TextButton.icon(
              onPressed: count == 0 ? null : _setOnlineNotifyForSelected,
              icon: const Icon(Icons.notifications_active_outlined, size: 16),
              label: const Text('上线通知'),
            ),
          ],
        ),
      ),
    );
  }

  /// 批量开「上线通知」：服务端 `batch_set_online_notify_flag` +
  /// 本地设置（筛选与上线提醒都读它）。
  Future<void> _setOnlineNotifyForSelected() async {
    final uins = _selected.toList();
    try {
      await ref
          .read(chatServiceProvider)
          .setOnlineNotifyBatch(uins, on: true);
    } catch (_) {
      // 服务端失败也写本地（与单个设置的行为一致：本地生效 + 提示）
    }
    final store = ref.read(settingsProvider);
    for (final u in uins) {
      try {
        await store.setFriendOnlineNotify(u, true);
      } catch (_) {
        // 忽略单条写入失败
      }
    }
    if (!mounted) return;
    setState(() => _notifyUins = {..._notifyUins, ...uins});
    _toast('已设置上线通知（${uins.length} 人）');
  }

  Future<void> _clearTagsForSelected() async {
    try {
      await ref
          .read(chatServiceProvider)
          .clearFriendLabels(_selected.toList());
      ref.invalidate(friendTagPoolProvider);
      _toast('已清除标签');
    } catch (e) {
      _toast('操作失败: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 把当前候选好友的上线通知开关读进 [_notifyUins]（筛选「上线通知」要用）。
  Future<void> _loadNotifyFlags() async {
    try {
      final store = ref.read(settingsProvider);
      final snap = ref.read(sessionListProvider).asData?.value;
      final next = <int>{};
      for (final s in _all(snap)) {
        if (s.type != ChatSessionType.friend) continue;
        if (await store.friendOnlineNotify(s.id)) next.add(s.id);
      }
      if (!mounted) return;
      setState(() => _notifyUins = next);
    } catch (_) {
      // 设置不可用（例如没有本地库）时，筛选里的「上线通知」按"都没开"处理。
    }
  }

  /// 点击好友/群 → 进入聊天（好友经回调切 tab）。
  void _open(ChatSession s) {
    final cb = widget.onOpenChat;
    if (cb != null && s.type == ChatSessionType.friend) {
      cb(s.id);
    } else {
      ref.read(activeSessionProvider.notifier).open(s.type, s.id);
    }
  }

  /// 好友长按 / 右键：与会话页同款浮动菜单（上线通知、置顶、免打扰、
  /// 拍一拍、备注、家园、删除好友）。好友页不传 onRemoved —— 这里是按好友
  /// 维度列人，没有「移除会话」这回事。
  Future<void> _showFriendMenu(ChatSession s, Offset globalPosition) {
    return showSessionMenu(context, ref, session: s, globalPosition: globalPosition);
  }

  /// 点击头像：与会话页同款玩家信息浮窗（锚在指针位置）。
  Future<void> _showPlayerInfo(ChatSession s, Offset globalPosition) {
    return showSessionPlayerInfoPopup(
      context,
      ref,
      uin: s.id,
      name: s.name,
      anchor: Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      avatarUrl: s.avatar,
      headType: s.headType,
      headId: s.headId,
      headFrameId: s.headFrameId,
    );
  }

  /// 顶部工具条（对齐游戏 `main_NewFriendsMgr`）：
  /// `在线好友 X/Y` + 刷新 + 批量管理 + 排序下拉 + 筛选 + 搜索。
  ///
  /// 工具条位于列表上方的 Column 中，必须是不透明实心条：透明背景会让下方
  /// 内容透出（"遮不住卡片"）。用页面底色铺底，保持与页面视觉无缝。
  Widget _buildToolbar(ThemeData theme, int online, int total) {
    // 搜索框：高度随系统字号缩放，避免大字号下输入文字被裁切。
    Widget searchField({bool autofocus = false}) => SizedBox(
      height: MediaQuery.textScalerOf(context).scale(36),
      child: TextField(
        autofocus: autofocus,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: '搜索好友昵称 / 迷你号…',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () => setState(() => _search = ''),
                ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 6,
            horizontal: 8,
          ),
        ),
      ),
    );
    // 窄屏：搜索平时是个图标按钮（有查询词时高亮）；点开才展开成输入框。
    //
    // 工具条一排 5 个图标按钮，默认 48dp 会把「在线好友 X/Y」挤到只剩
    // 「在线好友…」；统一收到 40dp（仍近 Material 推荐的 44dp 触控区）。
    Widget toolbarIcon({
      required String tooltip,
      required VoidCallback onPressed,
      required Widget icon,
    }) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      visualDensity: adaptiveDensity(context),
      icon: icon,
    );

    final searchToggle = toolbarIcon(
      tooltip: _search.isEmpty ? '搜索' : '搜索：$_search',
      onPressed: () => setState(() => _searchOpen = true),
      icon: Icon(
        Icons.search,
        size: 18,
        color: _search.isEmpty ? null : theme.colorScheme.primary,
      ),
    );
    // 刷新 / 批量管理（窄屏收成 40dp 图标，大屏同样用）
    final refreshButton = toolbarIcon(
      tooltip: '刷新',
      onPressed: () => ref.read(chatServiceProvider).loadSessions(),
      icon: const Icon(Icons.refresh, size: 18),
    );
    final batchButton = toolbarIcon(
      tooltip: _batchMode ? '退出批量管理' : '批量管理',
      onPressed: () => setState(() {
        _batchMode = !_batchMode;
        _selected.clear();
      }),
      icon: Icon(
        _batchMode ? Icons.checklist : Icons.checklist_outlined,
        size: 18,
      ),
    );
    // 游戏文案：`GetS(156004)` =「在线好友@1/@2」
    final countText = Text(
      '在线好友 $online/$total',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final controls = <Widget>[
      // 宽屏：与搜索框按 1:1 分剩余宽度。
      Flexible(child: countText),
      refreshButton,
      batchButton,
    ];
    // 筛选入口：有生效条件时高亮（游戏里漏斗的 selSt 控制器）。
    final filterButton = toolbarIcon(
      tooltip: '筛选',
      onPressed: _openFilterDialog,
      icon: Badge(
        isLabelVisible: !_filter.isEmpty,
        smallSize: 8,
        child: Icon(
          Icons.filter_alt_outlined,
          size: 18,
          color: _filter.isEmpty ? null : theme.colorScheme.primary,
        ),
      ),
    );
    final sortButton = PopupMenuButton<_SortMode>(
      tooltip: '排序方式',
      onSelected: (m) => setState(() => _sort = m),
      itemBuilder: _sortMenuItems,
      child: Chip(
        visualDensity: adaptiveDensity(context),
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(_sort.label, style: const TextStyle(fontSize: 12)),
      ),
    );

    // 窄屏排序：纯图标（带当前排序的 tooltip），标签版留给宽屏 ——
    // 否则“在线好友 X/Y + 刷新 + 批量 + 排序标签 + 筛选”在 360dp 下必然溢出。
    final sortIconButton = PopupMenuButton<_SortMode>(
      tooltip: '排序方式：${_sort.label}',
      onSelected: (m) => setState(() => _sort = m),
      itemBuilder: _sortMenuItems,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        child: Icon(Icons.sort, size: 18),
      ),
    );

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        // 手机（紧凑宽度）：搜索平时只是一个按钮，点开才占整行并隐藏其它控件；
        // 其余控件保持一行且保证不溢出（此前固定宽度控件相加超屏，实测溢出
        // 32dp@360 / 72dp@320）。
        child: isCompactWidth(context)
            ? (_searchOpen
                  ? Row(
                      children: [
                        Expanded(child: searchField(autofocus: true)),
                        toolbarIcon(
                          tooltip: '关闭搜索',
                          onPressed: () => setState(() {
                            _searchOpen = false;
                            _search = '';
                          }),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        searchToggle,
                        // `Expanded`（而不是 Flexible + Spacer）：计数占满
                        // 中间并把右侧图标顶到行尾，不会和 Spacer 抢宽度。
                        Expanded(child: countText),
                        refreshButton,
                        batchButton,
                        sortIconButton,
                        filterButton,
                      ],
                    ))
            : Row(
                children: [
                  ...controls,
                  const SizedBox(width: 8),
                  sortButton,
                  filterButton,
                  const SizedBox(width: 8),
                  Expanded(child: searchField()),
                ],
              ),
      ),
    );
  }

  /// 排序菜单项（宽屏标签版与窄屏图标版共用）。
  List<PopupMenuEntry<_SortMode>> _sortMenuItems(BuildContext ctx) => [
    for (final m in _SortMode.values)
      PopupMenuItem(
        value: m,
        child: Row(
          children: [
            if (m == _sort)
              Icon(
                Icons.check,
                size: 16,
                color: Theme.of(ctx).colorScheme.primary,
              )
            else
              const SizedBox(width: 16),
            const SizedBox(width: 8),
            Text(m.label),
          ],
        ),
      ),
  ];

  /// 左侧分类栏（黑名单 / 家族复用已有页面）。
  /// 手机端分类：横向可滚动的 chip 行（宽屏用 [_buildCategoryRail] 竖排）。
  ///
  /// 与竖排栏同一组分类、同一选中态，只是方向不同 —— 手机上竖栏会占掉近三成
  /// 屏宽，把好友列表挤到只剩一半，名字被迫截断。
  Widget _buildCategoryChips(ThemeData theme) {
    final style = theme.textTheme.bodyMedium?.copyWith(fontSize: 13);
    Widget chip(String label, {bool active = false, VoidCallback? onTap}) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ChoiceChip(
          label: Text(label, style: style),
          selected: active,
          visualDensity: adaptiveDensity(context),
          onSelected: (_) => onTap?.call(),
        ),
      );
    }

    // 与工具栏一样铺不透明底色：分类栏下方就是好友列表，底色透明时列表内容
    // 会在下拉 / 过滚时透出来，看上去像「列表穿透到分类栏下面」。
    return Container(
      color: theme.scaffoldBackgroundColor,
      // 高度随系统字号缩放，避免大字号下 chip 被裁切。
      height: MediaQuery.textScalerOf(context).scale(52),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        children: [
          chip(
            '我的好友',
            active: _cat == _FriendCat.friend,
            onTap: () => setState(() => _cat = _FriendCat.friend),
          ),
          chip(
            '最佳拍档',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PartnerPage())),
          ),
          chip(
            '关注',
            active: _cat == _FriendCat.follow,
            onTap: () => setState(() => _cat = _FriendCat.follow),
          ),
          chip(
            '群组',
            active: _cat == _FriendCat.group,
            onTap: () => setState(() => _cat = _FriendCat.group),
          ),
          chip(
            '黑名单',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BlacklistPage())),
          ),
          chip(
            '家族',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FamilyPage())),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRail(ThemeData theme) {
    Widget item(String label, {bool active = false, VoidCallback? onTap}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: active
              ? theme.colorScheme.secondaryContainer
              : Colors.transparent,
          borderRadius: AppRadius.inputR,
          child: InkWell(
            borderRadius: AppRadius.inputR,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: active
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 118,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          item(
            '我的好友',
            active: _cat == _FriendCat.friend,
            onTap: () => setState(() => _cat = _FriendCat.friend),
          ),
          item(
            '最佳拍档',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PartnerPage())),
          ),
          item(
            '关注',
            active: _cat == _FriendCat.follow,
            onTap: () => setState(() => _cat = _FriendCat.follow),
          ),
          item(
            '群组',
            active: _cat == _FriendCat.group,
            onTap: () => setState(() => _cat = _FriendCat.group),
          ),
          item(
            '黑名单',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BlacklistPage())),
          ),
          item(
            '家族',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FamilyPage())),
          ),
        ],
      ),
    );
  }
}

/// 好友行：头像 + 昵称 + 迷你号 / 关系 / 在线状态。
class _FriendTile extends ConsumerWidget {
  final ChatSession session;
  final VoidCallback onTap;

  /// 长按 / 桌面端右键打开好友操作菜单（参数为指针全局坐标）。
  final ValueChanged<Offset>? onLongPress;
  final ValueChanged<Offset>? onSecondaryTap;

  /// 点击头像打开玩家信息浮窗（仅好友会话传入），参数为指针全局坐标。
  final ValueChanged<Offset>? onAvatarTap;

  /// 批量管理模式下：行首显示勾选框。
  final bool batchMode;
  final bool selected;
  final VoidCallback? onSelectToggle;

  const _FriendTile({
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onAvatarTap,
    this.batchMode = false,
    this.selected = false,
    this.onSelectToggle,
  });

  String _relationLabel(int relation) {
    // 黑名单优先；然后是「好友」——同为好友且互相关注时（relation 含 8|16）
    // 必须显示「好友」而非「关注」，因此 bit3(8) 要先于 bit4(16) 判断。
    if ((relation & 64) != 0) return '黑名单';
    if ((relation & 8) != 0) return '好友';
    if ((relation & 16) != 0) return '关注';
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isGroup = session.type == ChatSessionType.group;
    final rel = _relationLabel(session.relation);
    final gameText = isGroup
        ? '群聊'
        : (session.gameStatus ?? (session.isOnline ? '在线' : '离线'));
    final name = session.name.isNotEmpty ? session.name : '${session.id}';

    // 等级 / 拍档 / 大会员 / 默契度：来自会话级批量缓存（随会话流一次拉取）。
    final directory =
        ref.watch(partnerDirectoryProvider).asData?.value ??
        PartnerDirectory.empty;
    final level = isGroup ? 0 : directory.levelOf(session.id);
    final partner = isGroup ? null : directory.partnerOf(session.id);
    final isVip = !isGroup && directory.isVip(session.id);
    // 关系等级阈值（服务端 visual-cfg）；缺失时为空列表 → 默契度徽标不画进度条。
    final levelCfg =
        ref.watch(partnerLevelConfigProvider).asData?.value ??
        const <(int, int)>[];

    // ListTile 给 leading 的高度上限是 (isDense ? 48 : 56) + 密度纵向调整，
    // 桌面紧凑密度下只有 48，会把有框槽位（radius * 2 / 0.76 ≈ 63.2）压成
    // 非正方形并被 cover 裁掉框外圈。故抬高纵向密度（见 [kAvatarListTileDensity]），
    // 并用 minTileHeight 兜住行高，保证槽位完整可见。
    final avatar = AvatarView(
      avatarUrl: session.avatar,
      name: name,
      type: session.type,
      radius: 24,
      headType: session.headType,
      headId: session.headId,
      frameId: session.headFrameId,
    );

    final tile = ListTile(
      // 与全局 cardTheme 一致：surfaceContainerLow 底色 + cardR 圆角 + 细描边，
      // ListTile 的 shape 同时作为 InkWell 的 customBorder，选中 / 悬停 / 水波
      // 反馈会被裁进圆角内（不会出现直角溢出）。
      shape: _cardLikeShape(theme),
      tileColor: theme.colorScheme.surfaceContainerLow,
      contentPadding: AppSpacing.listTilePadding,
      visualDensity: kAvatarListTileDensity,
      minTileHeight: headFrameSlotSize(24),
      // 批量管理：行首换成勾选框
      leading: batchMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => onSelectToggle?.call(),
            )
          : onAvatarTap == null
          ? avatar
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              // onTapUp 才拿得到指针坐标（浮窗要锚在点击处）。
              onTapUp: (d) => onAvatarTap!(d.globalPosition),
              child: avatar,
            ),
      // `Row` 给非 flex 子节点的是无界主轴约束，徽标拿不到行宽，所以这里用
      // `LayoutBuilder` 量出标题行宽度并显式传给槽位（见 [PartnerBadgeSlot]）。
      title: LayoutBuilder(
        builder: (context, titleConstraints) => Row(
          children: [
            Flexible(
              child: RichTextView(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 默契度是**每个好友都有**的（`get_list` 里非拍档项 `lab == 0`），
            // 所以这里显式传值 —— 非拍档也显示，配色用 lab（0 = 默认色）。
            // 徽标宽度受限 + 内部按预算降级 → 昵称永远不会被挤没。
            if (!isGroup) ...[
              const SizedBox(width: AppSpacing.xs),
              PartnerBadgeSlot(
                rowWidth: titleConstraints.maxWidth,
                child: PartnerNameBadges(
                  level: level,
                  partner: partner,
                  isVip: isVip,
                  levels: levelCfg,
                  tacitnum: directory.tacitOf(session.id),
                  lab: partner?.lab ?? 0,
                ),
              ),
            ],
            if (rel.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: AppRadius.chipR,
                ),
                child: Text(
                  rel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: isGroup
          ? null
          : IconButton(
              tooltip: '查看主页',
              icon: const Icon(Icons.account_circle_outlined, size: 22),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlayerHomePage(targetUin: session.id),
                ),
              ),
            ),
      subtitle: isGroup
          ? Text(
              '点击进入群聊',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: session.isOnline
                        ? semantic.success
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '$gameText · 迷你号 ${session.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: session.isOnline
                          ? semantic.success
                          : theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
      onTap: onTap,
      // 长按不挂 ListTile 上：它不给指针坐标，而浮动菜单要锚在按下处。
    );

    // 长按 / 右键（桌面端）由外层 GestureDetector 接管（ListTile 不暴露
    // secondary tap，onLongPress 也没有坐标）。
    return GestureDetector(
      onLongPressStart: onLongPress == null
          ? null
          : (d) => onLongPress!(d.globalPosition),
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (d) => onSecondaryTap!(d.globalPosition),
      child: tile,
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  final bool isGroup;
  final bool hasData;
  final VoidCallback onAddFriend;

  const _EmptyFriends({
    required this.isGroup,
    required this.hasData,
    required this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!hasData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            const Text('暂无好友\n下拉刷新或点击右上角添加'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAddFriend,
              icon: const Icon(Icons.person_search),
              label: const Text('按迷你号添加'),
            ),
          ],
        ),
      );
    }
    return Center(child: Text(isGroup ? '暂无群聊' : '没有符合条件的好友'));
  }
}

/// 复刻全局 `cardTheme` 的外形：cardR 圆角 + 同一条 1px 描边。
///
/// 优先取主题里 `CardThemeData.shape` 的描边，保证与全站卡片完全一致；
/// 拿不到时退回到 `outlineVariant`（与 `buildAppTheme` 中的 border 同源）。
RoundedRectangleBorder _cardLikeShape(ThemeData theme) {
  final shape = theme.cardTheme.shape;
  final side = shape is RoundedRectangleBorder
      ? shape.side
      : BorderSide(color: theme.colorScheme.outlineVariant);
  return RoundedRectangleBorder(borderRadius: AppRadius.cardR, side: side);
}
