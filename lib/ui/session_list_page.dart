import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../state/providers.dart';
import 'friend_request_page.dart' show showAddFriendDialog;
import 'theme/app_tokens.dart';
import 'widgets/account_menu.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/player_info_sheet.dart';
import 'widgets/rich_text_view.dart';

/// 会话列表页（左侧栏 / 手机单页）。
///
/// 只展示"已对话"的会话：好友必须聊过天（由 HomeShell 过滤后传入），
/// 群全部保留。顶部保留搜索框，排序与快捷短语入口在设置页。
class SessionListPage extends ConsumerStatefulWidget {
  final List<ChatSession> sessions;

  const SessionListPage({super.key, required this.sessions});

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeSessionProvider);
    final sortMode = ref.watch(sessionSortModeProvider);
    final theme = Theme.of(context);
    final sessions = widget.sessions;

    // 与 HomeShell 一致：横屏且够宽时账号入口在侧栏底部，AppBar 不再重复展示。
    final railLayout =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        MediaQuery.sizeOf(context).width >= 800;

    // 搜索过滤（昵称/迷你号/群名）
    final filtered = sessions.where((s) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return s.name.toLowerCase().contains(q) || '${s.id}'.contains(q);
    }).toList();

    // 排序（time 模式对齐游戏：未读优先 → 最后消息时间倒序）
    final sorted = [...filtered]
      ..sort(
        (a, b) => switch (sortMode) {
          SessionSortMode.name => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
          SessionSortMode.unread => b.unreadCount.compareTo(a.unreadCount),
          SessionSortMode.time => () {
            // 未读会话置前（二元，同游戏 unReadStat），再按时间倒序
            final au = a.unreadCount > 0 ? 0 : 1;
            final bu = b.unreadCount > 0 ? 0 : 1;
            if (au != bu) return au.compareTo(bu);
            return (b.lastMessage?.time ?? 0).compareTo(
              a.lastMessage?.time ?? 0,
            );
          }(),
        },
      );

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话', style: TextStyle(fontWeight: FontWeight.bold)),
        // 竖屏/窄屏：账号入口放 AppBar；横屏由侧栏底部承担。
        actions: railLayout ? null : const [AccountAvatarButton()],
      ),
      body: Column(
        children: [
          _buildSearchBar(theme),
          const Divider(height: 1),
          Expanded(
            child: sorted.isEmpty
                ? _EmptySessions(
                    onAddFriend: () => showAddFriendDialog(context, ref),
                  )
                : ListView.separated(
                    // 行改为圆角卡片后不再用 Divider 分隔；四边内缩到与
                    // CardThemeData.margin 一致：左右避免圆角贴住面板边缘，
                    // 上下避免首/末卡片贴住搜索框分隔线与窗口底边。
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: sorted.length,
                    // 行间留白与 CardThemeData.margin.vertical 一致。
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final s = sorted[i];
                      final isActive =
                          active != null &&
                          active.type == s.type &&
                          active.id == s.id;
                      return _SessionTile(
                        session: s,
                        isActive: isActive,
                        onTap: () => ref
                            .read(activeSessionProvider.notifier)
                            .open(s.type, s.id),
                        onLongPress: () => _showSessionMenu(context, s),
                        // 桌面端右键打开同一菜单
                        onSecondaryTap: () => _showSessionMenu(context, s),
                        // 点击好友头像：玩家简要信息卡
                        onAvatarTap: s.type == ChatSessionType.friend
                            ? () => showPlayerInfoSheet(
                                context,
                                ref,
                                uin: s.id,
                                name: s.name,
                                avatarUrl: s.avatar,
                                headType: s.headType,
                                headId: s.headId,
                                headFrameId: s.headFrameId,
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 搜索框。
  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: '搜索会话…',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => _search = ''),
                ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 6,
            horizontal: 8,
          ),
        ),
      ),
    );
  }

  /// 会话长按 / 右键菜单：免打扰 / 置顶 + 好友专属操作（上线通知、备注、
  /// 家园、删除好友）。
  Future<void> _showSessionMenu(BuildContext context, ChatSession s) async {
    await showFriendMenu(
      context,
      ref,
      uin: s.id,
      name: s.name,
      type: s.type,
      showMute: true,
    );
    if (mounted) setState(() {}); // 刷新（置顶影响排序）
  }
}

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 桌面端右键（secondary tap）打开与长按相同的菜单。
  final VoidCallback? onSecondaryTap;

  /// 点击头像打开玩家简要信息卡（仅好友会话传入）。
  final VoidCallback? onAvatarTap;

  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = session.lastMessage;
    final timeText = last != null ? _fmtTime(last.time) : '';

    // 好友会话：显示在线/游玩状态；群会话：仅最后消息
    final isFriend = session.type == ChatSessionType.friend;
    final statusText = isFriend
        ? (session.gameStatus != null && session.gameStatus!.isNotEmpty
              ? session.gameStatus!
              : (session.isOnline ? '在线' : '离线'))
        : null;

    // ListTile 给 leading 的高度上限是 (isDense ? 48 : 56) + 密度纵向调整，
    // 桌面紧凑密度下只有 48，会把有框槽位（radius * 2 / 0.76 ≈ 63.2）压成
    // 非正方形并被 cover 裁掉框外圈。故抬高纵向密度（见 [kAvatarListTileDensity]），
    // 并用 minTileHeight 兜住行高，保证槽位完整可见。
    final avatar = AvatarView(
      avatarUrl: session.avatar,
      name: session.name,
      type: session.type,
      radius: 24,
      headType: session.headType,
      headId: session.headId,
      frameId: session.headFrameId,
    );

    final tile = ListTile(
      selected: isActive,
      selectedTileColor: theme.colorScheme.secondaryContainer,
      // 与全局 cardTheme 一致：surfaceContainerLow 底色 + cardR 圆角 + 细描边，
      // ListTile 的 shape 同时作为 InkWell 的 customBorder，选中 / 悬停 / 水波
      // 反馈会被裁进圆角内（不会出现直角溢出）。
      shape: _cardLikeShape(theme),
      tileColor: theme.colorScheme.surfaceContainerLow,
      // 与好友行一致：使用 listTilePadding（vertical 8）。此前手写的 vertical 4
      // 会让行高只有 68（好友行 76），同样的 48px 头像在更矮的行里显得偏大。
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
      title: RichTextView(
        session.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: isFriend
          // 好友：在线绿点 + 状态 + 最后消息（两行紧凑显示）
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: session.isOnline
                        ? AppSemanticColors.of(context).success
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    statusText ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: session.isOnline
                          ? AppSemanticColors.of(context).success
                          : theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (last != null) ...[
                  const Text(' · ', style: TextStyle(fontSize: 11)),
                  Flexible(
                    child: Text(
                      last.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            )
          : Text(
              last?.text ?? '暂无消息',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeText, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          if (session.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                session.unreadCount > 99 ? '99+' : '${session.unreadCount}',
                style: TextStyle(
                  color: theme.colorScheme.onError,
                  fontSize: 11,
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

class _EmptySessions extends StatelessWidget {
  final VoidCallback onAddFriend;

  const _EmptySessions({required this.onAddFriend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 8),
          const Text('暂无会话\n聊过天的人会出现在这里'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAddFriend,
            icon: const Icon(Icons.person_add),
            label: const Text('添加好友'),
          ),
        ],
      ),
    );
  }
}

/// 格式化时间：今天显示 HH:mm，否则 MM-dd。
String _fmtTime(int ts) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
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
