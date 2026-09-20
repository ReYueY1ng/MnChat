import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../core/services/chat_service.dart' show SessionSnapshot;
import '../core/services/partner.dart';
import '../state/providers.dart';
import 'friend_request_page.dart' show FriendRequestPage, showAddFriendDialog;
import 'blacklist_page.dart';
import 'family_page.dart';
import 'my_qr_page.dart';
import 'partner_page.dart';
import 'player_home_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/partner_badges.dart';
import 'widgets/player_info_sheet.dart';
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

/// 排序方式。
enum _SortMode {
  online('在线优先'),
  name('昵称'),
  recent('最近活跃');

  const _SortMode(this.label);
  final String label;
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  String _search = '';
  bool _onlyOnline = false;
  _FriendCat _cat = _FriendCat.friend;
  _SortMode _sort = _SortMode.online;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = ref.watch(sessionListProvider).asData?.value;
    final reqCount = ref.watch(friendRequestCountProvider);
    final pool = _ofCategory(_all(snap));
    final onlineCount = pool.where((s) => s.isOnline).length;

    final filtered =
        pool.where((s) {
          if (_cat != _FriendCat.group && _onlyOnline && !s.isOnline) {
            return false;
          }
          if (_search.isNotEmpty) {
            final q = _search.toLowerCase();
            if (!s.name.toLowerCase().contains(q) && !'${s.id}'.contains(q)) {
              return false;
            }
          }
          return true;
        }).toList()..sort((a, b) {
          switch (_sort) {
            case _SortMode.name:
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            case _SortMode.recent:
              return (b.lastMessage?.time ?? 0).compareTo(
                a.lastMessage?.time ?? 0,
              );
            case _SortMode.online:
              if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
        });

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
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isCompactWidth(context)) ...[
                      _buildCategoryRail(theme),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: filtered.isEmpty
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
                              itemCount: filtered.length,
                              // 行间留白与 CardThemeData.margin.vertical 一致。
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (context, i) {
                                final f = filtered[i];
                                return _FriendTile(
                                  session: f,
                                  onTap: () => _open(f),
                                  onLongPress: () => _showFriendMenu(f),
                                  // 桌面端右键打开同一菜单
                                  onSecondaryTap: () => _showFriendMenu(f),
                                  // 点击头像：玩家简要信息卡（仅好友）
                                  onAvatarTap: f.type == ChatSessionType.friend
                                      ? () => _showPlayerInfo(f)
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

  /// 点击好友/群 → 进入聊天（好友经回调切 tab）。
  void _open(ChatSession s) {
    final cb = widget.onOpenChat;
    if (cb != null && s.type == ChatSessionType.friend) {
      cb(s.id);
    } else {
      ref.read(activeSessionProvider.notifier).open(s.type, s.id);
    }
  }

  /// 好友长按 / 右键菜单（上线通知、置顶、备注、家园、删除好友）。
  Future<void> _showFriendMenu(ChatSession s) {
    return showFriendMenu(context, ref, uin: s.id, name: s.name, type: s.type);
  }

  /// 点击头像：玩家简要信息卡。
  Future<void> _showPlayerInfo(ChatSession s) {
    return showPlayerInfoSheet(
      context,
      ref,
      uin: s.id,
      name: s.name,
      avatarUrl: s.avatar,
      headType: s.headType,
      headId: s.headId,
      headFrameId: s.headFrameId,
    );
  }

  /// 顶部工具条：在线计数 / 刷新 / 只看在线 / 排序 / 搜索。
  ///
  /// 工具条位于列表上方的 Column 中，必须是不透明实心条：透明背景会让下方
  /// 内容透出（"遮不住卡片"）。用页面底色铺底，保持与页面视觉无缝。
  Widget _buildToolbar(ThemeData theme, int online, int total) {
    // 搜索框：高度随系统字号缩放，避免大字号下输入文字被裁切。
    final searchField = SizedBox(
      height: MediaQuery.textScalerOf(context).scale(36),
      child: TextField(
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
    final controls = <Widget>[
      Text(
        '在线 $online / $total',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      IconButton(
        tooltip: '刷新',
        visualDensity: adaptiveDensity(context),
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: () => ref.read(chatServiceProvider).loadSessions(),
      ),
      if (_cat != _FriendCat.group) ...[
        const SizedBox(width: 4),
        FilterChip(
          visualDensity: adaptiveDensity(context),
          label: const Text('只看在线', style: TextStyle(fontSize: 12)),
          selected: _onlyOnline,
          onSelected: (v) => setState(() => _onlyOnline = v),
        ),
      ],
    ];
    final sortButton = PopupMenuButton<_SortMode>(
      tooltip: '排序方式',
      onSelected: (m) => setState(() => _sort = m),
      itemBuilder: (ctx) => [
        for (final m in _SortMode.values)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                if (m == _sort)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: theme.colorScheme.primary,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(m.label),
              ],
            ),
          ),
      ],
      child: Chip(
        visualDensity: adaptiveDensity(context),
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(_sort.label, style: const TextStyle(fontSize: 12)),
      ),
    );

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        // 手机（紧凑宽度）：控件一行、搜索框独占下一行整宽。此前控件与搜索框全挤在
        // 同一个 Row 里，控件固定占掉近 300dp，搜索框只剩百来 dp 被挤到角落。
        child: isCompactWidth(context)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [...controls, const Spacer(), sortButton]),
                  const SizedBox(height: 8),
                  searchField,
                ],
              )
            : Row(
                children: [
                  ...controls,
                  const SizedBox(width: 8),
                  sortButton,
                  const SizedBox(width: 8),
                  Expanded(child: searchField),
                ],
              ),
      ),
    );
  }

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

    return SizedBox(
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

  /// 长按 / 桌面端右键打开好友操作菜单。
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  /// 点击头像打开玩家简要信息卡（仅好友会话传入）。
  final VoidCallback? onAvatarTap;

  const _FriendTile({
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onAvatarTap,
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

    // 等级 / 拍档 / 大会员：来自会话级批量缓存（随会话流一次拉取，逐行不请求）。
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
      // 头像可点击（仅好友）：opaque 保证不与整行 onTap 冲突
      leading: onAvatarTap == null
          ? avatar
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAvatarTap,
              child: avatar,
            ),
      title: Row(
        children: [
          Flexible(
            child: RichTextView(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isGroup)
            PartnerNameBadges(
              level: level,
              partner: partner,
              isVip: isVip,
              levels: levelCfg,
            ),
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
      onLongPress: onLongPress,
    );

    // 右键（桌面端）打开菜单：ListTile 不暴露 secondary tap，外层包一层
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (_) => onSecondaryTap!(),
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
