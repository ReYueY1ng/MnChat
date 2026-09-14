import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../core/storage/settings_store.dart';
import '../state/providers.dart';
import 'friend_request_page.dart' show showAddFriendDialog;
import 'theme/app_tokens.dart';
import 'widgets/account_menu.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/rich_text_view.dart';
import 'widgets/session_menu.dart';
import 'widgets/session_player_info_popup.dart';

/// 会话列表页（左侧栏 / 手机单页）。
///
/// 只展示"已对话"的会话：好友必须聊过天（由 HomeShell 过滤后传入），
/// 群全部保留。顶部工具条对齐游戏好友列表：在线计数 / 刷新 / 只看在线 /
/// 排序 / 可展开搜索（占位「支持迷你号和昵称查找」+ 取消）。
class SessionListPage extends ConsumerStatefulWidget {
  final List<ChatSession> sessions;

  /// 点击会话卡片的回调；为空时回退到 [activeSessionProvider].open。
  ///
  /// HomeShell 传入以实现"再次点击当前会话关闭聊天"的切换逻辑。
  final ValueChanged<ChatSession>? onOpenChat;

  const SessionListPage({super.key, required this.sessions, this.onOpenChat});

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

/// 工具条排序方式（文案对齐游戏好友列表）。
///
/// 会话数据层只有时间 / 名称 / 未读三种排序（[SessionSortMode]，设置页可配），
/// 参考列表的其余三项没有对应字段（默契度 / 登录时间），选中后仅切换标签、
/// 顺序仍沿用设置里的排序（no-op）。
enum _SessionSortMode {
  byDefault('好友默认排序'),
  tacitDesc('默契度从高到低'),
  loginRecent('登录从近到远'),
  loginOld('登录从远到近');

  const _SessionSortMode(this.label);
  final String label;
}

/// 「移除会话」本地持久化 key：JSON 对象 `{type_id: '1'}`。
///
/// core 层没有暴露删除 / 隐藏会话的接口且不允许改动，因此移除实现为本地
/// 隐藏：通过 UI 已可达的 `SettingsStore.getString/setString`（与好友备注 /
/// 置顶同一套通用字符串设置）落库，重启后仍隐藏；服务端的好友 / 群数据不动，
/// 下次 loadSessions 重建会话时由过滤器继续挡掉。
const String _removedSessionsSettingKey = 'session_removed_keys';

/// 已移除会话（`type_id`）的进程内缓存：页面重建（横竖屏切换等）立即生效。
final Set<String> _removedSessionKeys = <String>{};

class _SessionListPageState extends ConsumerState<SessionListPage> {
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  /// 搜索框是否展开（折叠时工具条只显示放大镜图标）。
  bool _searchOpen = false;

  /// 只看在线。
  bool _onlyOnline = false;

  /// 当前选中的排序（仅「好友默认排序」有真实数据支持）。
  _SessionSortMode _sort = _SessionSortMode.byDefault;

  @override
  void initState() {
    super.initState();
    _restoreRemovedSessions();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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

    // 过滤：已移除 → 只看在线 → 搜索（昵称 / 迷你号 / 群名）
    final filtered = sessions.where((s) {
      if (_removedSessionKeys.contains(
        SettingsKeys.sessionKey(s.type.name, s.id),
      )) {
        return false;
      }
      if (_onlyOnline && !s.isOnline) return false;
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

    final online = sessions.where((s) => s.isOnline).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话', style: TextStyle(fontWeight: FontWeight.bold)),
        // 竖屏/窄屏：账号入口放 AppBar；横屏由侧栏底部承担。
        actions: railLayout ? null : const [AccountAvatarButton()],
      ),
      body: Column(
        children: [
          _buildToolbar(theme, online, sessions.length),
          Expanded(
            child: sorted.isEmpty
                ? _EmptySessions(
                    onAddFriend: () => showAddFriendDialog(context, ref),
                  )
                : ListView.separated(
                    // 行改为圆角卡片后不再用 Divider 分隔；四边内缩到与
                    // CardThemeData.margin 一致：左右避免圆角贴住面板边缘，
                    // 上下避免首/末卡片贴住工具条与窗口底边。
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
                        onTap: () {
                          final open = widget.onOpenChat;
                          if (open != null) {
                            open(s);
                          } else {
                            ref
                                .read(activeSessionProvider.notifier)
                                .open(s.type, s.id);
                          }
                        },
                        // 长按 / 桌面右键：指针位置弹出浮动菜单
                        onLongPress: (pos) => _showSessionMenu(s, pos),
                        onSecondaryTap: (pos) => _showSessionMenu(s, pos),
                        // 点击好友头像：浮动的玩家简要信息卡
                        onAvatarTap: s.type == ChatSessionType.friend
                            ? (pos) => _showPlayerInfo(s, pos)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 顶部工具条（对齐游戏好友列表形态）：在线计数 / 刷新 / 只看在线 / 排序 /
  /// 可展开搜索（占位「支持迷你号和昵称查找」+ 取消）。
  ///
  /// 与好友页同样用页面底色铺底，避免卡片从工具条下透出；按需求不再在工具条
  /// 与列表之间加 Divider。
  Widget _buildToolbar(ThemeData theme, int online, int total) {
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: _searchOpen
            // 展开态：搜索框 + 取消（替代工具条其余内容，避免窄侧栏溢出）
            ? Row(
                children: [
                  Expanded(child: _buildSearchField()),
                  TextButton(onPressed: _closeSearch, child: const Text('取消')),
                ],
              )
            // 折叠态：计数 + 刷新 + 只看在线 + 排序（可换行）+ 搜索图标
            : Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '在线好友 $online / $total',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          tooltip: '刷新',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: () =>
                              ref.read(chatServiceProvider).loadSessions(),
                        ),
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: const Text(
                            '只看在线',
                            style: TextStyle(fontSize: 12),
                          ),
                          selected: _onlyOnline,
                          onSelected: (v) => setState(() => _onlyOnline = v),
                        ),
                        _buildSortMenu(theme),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '搜索',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => _searchOpen = true),
                  ),
                ],
              ),
      ),
    );
  }

  /// 展开后的搜索框：占位「支持迷你号和昵称查找」。
  Widget _buildSearchField() {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: '支持迷你号和昵称查找',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 6,
            horizontal: 8,
          ),
        ),
      ),
    );
  }

  /// 排序下拉：四项参考文案；仅「好友默认排序」有真实数据支持。
  Widget _buildSortMenu(ThemeData theme) {
    return PopupMenuButton<_SessionSortMode>(
      tooltip: '排序方式',
      onSelected: _selectSort,
      itemBuilder: (ctx) => [
        for (final m in _SessionSortMode.values)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                if (m == _sort)
                  Icon(Icons.check, size: 16, color: theme.colorScheme.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(m.label),
              ],
            ),
          ),
      ],
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(_sort.label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  /// 选择排序：数据层没有默契度 / 登录时间字段，其余三项只切标签不改顺序。
  void _selectSort(_SessionSortMode mode) {
    setState(() => _sort = mode);
    if (mode != _SessionSortMode.byDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该排序暂不支持，仍按默认顺序排列')),
      );
    }
  }

  /// 取消搜索：清空关键字并收起搜索框。
  void _closeSearch() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _searchOpen = false;
    });
  }

  /// 恢复本地「移除会话」标记（设置读取失败时保持进程内缓存）。
  Future<void> _restoreRemovedSessions() async {
    try {
      final raw = await ref
          .read(settingsProvider)
          .getString(_removedSessionsSettingKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final restored = <String>{
        for (final e in decoded.entries)
          if (e.value.toString() == '1') '${e.key}',
      };
      final added = restored.difference(_removedSessionKeys);
      if (added.isEmpty) return;
      setState(() => _removedSessionKeys.addAll(added));
    } catch (_) {
      // 设置不可用（测试等）时保持默认：不隐藏任何会话。
    }
  }

  /// 移除会话：加入本地隐藏集合并持久化；若正在聊天则一并关闭。
  Future<void> _removeSession(ChatSession s) async {
    final key = SettingsKeys.sessionKey(s.type.name, s.id);
    setState(() => _removedSessionKeys.add(key));
    final active = ref.read(activeSessionProvider);
    if (active != null && active.type == s.type && active.id == s.id) {
      ref.read(activeSessionProvider.notifier).close();
    }
    try {
      final settings = ref.read(settingsProvider);
      final raw = await settings.getString(_removedSessionsSettingKey);
      final map = <String, Object?>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) map.addAll(decoded.cast<String, Object?>());
      }
      map[key] = '1';
      await settings.setString(_removedSessionsSettingKey, jsonEncode(map));
    } catch (_) {
      // 持久化失败仅影响重启后的可见性；本次进程内已移除。
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已移除会话')));
    }
  }

  /// 长按 / 右键：在指针位置弹出浮动会话菜单。
  Future<void> _showSessionMenu(ChatSession s, Offset globalPosition) {
    return showSessionMenu(
      context,
      ref,
      session: s,
      globalPosition: globalPosition,
      onRemoved: () => _removeSession(s),
    );
  }

  /// 点击头像：头像附近弹出玩家信息浮窗（内容进程内缓存，重开不重复请求）。
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
}

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isActive;
  final VoidCallback onTap;

  /// 长按（移动端）/ 桌面右键：参数为指针全局坐标，作为浮动菜单锚点。
  final ValueChanged<Offset>? onLongPress;
  final ValueChanged<Offset>? onSecondaryTap;

  /// 点击头像（仅好友会话传入）：参数为指针全局坐标，作为浮窗锚点。
  final ValueChanged<Offset>? onAvatarTap;

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
      // 头像可点击（仅好友）：opaque 保证不与整行 onTap 冲突；onTapUp 带全局
      // 坐标，用于把信息浮窗锚到头像附近。
      leading: onAvatarTap == null
          ? avatar
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => onAvatarTap!(details.globalPosition),
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
    );

    // 右键（桌面端）/ 长按（移动端）打开浮动菜单：ListTile 不暴露 secondary
    // tap，长按也拿不到指针坐标，外层包一层统一取全局坐标。
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
