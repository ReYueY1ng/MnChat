import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../state/providers.dart';
import 'dynamics_page.dart';
import 'family_page.dart';
import 'friend_request_page.dart';
import 'settings_page.dart';
import 'widgets/avatar_view.dart';

/// 会话列表页（左侧栏 / 手机单页）。
/// 顶部用 AppBar（自动处理状态栏 SafeArea），操作按钮在 Drawer 侧边栏菜单。
class SessionListPage extends ConsumerStatefulWidget {
  final List<ChatSession> sessions;

  const SessionListPage({super.key, required this.sessions});

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  String _search = '';
  bool _onlyOnline = false;
  String? _cat; // null=全部 / '好友' / '关注' / '黑名单'（按 relation 位）

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final active = ref.watch(activeSessionProvider);
    final sortMode = ref.watch(sessionSortModeProvider);
    final theme = Theme.of(context);
    final sessions = widget.sessions;

    // 过滤：关系分类 + 只看在线（仅好友会话）+ 搜索（名称/迷你号）
    final filtered = sessions.where((s) {
      switch (_cat) {
        case '好友':
          if (s.type != ChatSessionType.friend || (s.relation & 8) == 0) return false;
        case '关注':
          if (s.type != ChatSessionType.friend || (s.relation & 16) == 0) return false;
        case '黑名单':
          if (s.type != ChatSessionType.friend || (s.relation & 64) == 0) return false;
      }
      if (_onlyOnline && s.type == ChatSessionType.friend && !s.isOnline) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!s.name.toLowerCase().contains(q) && !'${s.id}'.contains(q)) return false;
      }
      return true;
    }).toList();

    // 排序（time 模式对齐游戏：未读优先 → 最后消息时间倒序）
    final sorted = [...filtered]..sort((a, b) => switch (sortMode) {
          SessionSortMode.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          SessionSortMode.unread => b.unreadCount.compareTo(a.unreadCount),
          SessionSortMode.time => () {
              // 未读会话置前（二元，同游戏 unReadStat），再按时间倒序
              final au = a.unreadCount > 0 ? 0 : 1;
              final bu = b.unreadCount > 0 ? 0 : 1;
              if (au != bu) return au.compareTo(bu);
              return (b.lastMessage?.time ?? 0).compareTo(a.lastMessage?.time ?? 0);
            }(),
        });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '会话',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      drawer: _buildDrawer(context, ref, auth),
      body: Column(
        children: [
          _buildFilterBar(theme),
          const Divider(height: 1),
          Expanded(
            child: sorted.isEmpty
                ? _EmptySessions(onAddFriend: () => showAddFriendDialog(context, ref))
                : ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 72,
                        color: theme.colorScheme.outlineVariant),
                    itemBuilder: (context, i) {
                      final s = sorted[i];
                      final isActive = active != null &&
                          active.type == s.type &&
                          active.id == s.id;
                      return _SessionTile(
                        session: s,
                        isActive: isActive,
                        onTap: () => ref
                            .read(activeSessionProvider.notifier)
                            .open(s.type, s.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 顶部：只看在线开关 + 搜索框 + 好友关系分类 chips。
  Widget _buildFilterBar(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              // 只看在线
              InkWell(
                onTap: () => setState(() => _onlyOnline = !_onlyOnline),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      Icon(_onlyOnline ? Icons.visibility : Icons.visibility_off_outlined,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('只看在线', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              Expanded(
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 好友关系分类
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: const ['全部', '好友', '关注', '黑名单'].map((c) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CatChip(
                  label: c,
                  selected: _cat == (c == '全部' ? null : c),
                  onTap: () => setState(() => _cat = c == '全部' ? null : c),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 侧边栏菜单：账号信息 / 排序 / 刷新 / 设置 / 退出登录。
  Drawer _buildDrawer(BuildContext context, WidgetRef ref, authState) {
    final theme = Theme.of(context);
    final sortMode = ref.watch(sessionSortModeProvider);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 头部：账号信息 + 状态
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Row(
                children: [
                  AvatarView(
                    avatarUrl: null,
                    name: authState.auth?.name ?? '',
                    radius: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authState.auth?.name ?? '未登录',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Uin: ${authState.auth?.uin ?? '-'}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 排序
            ExpansionTile(
              leading: const Icon(Icons.sort),
              title: const Text('排序方式'),
              subtitle: Text(sortMode.label),
              children: [
                for (final m in SessionSortMode.values)
                  RadioListTile<SessionSortMode>(
                    dense: true,
                    title: Text(m.label),
                    value: m,
                    groupValue: sortMode,
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(sessionSortModeProvider.notifier).setMode(v);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新会话'),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(chatServiceProvider).loadSessions();
              },
            ),
            // 好友申请：红点显示待处理数
            Badge(
              isLabelVisible: ref.watch(friendRequestCountProvider) > 0,
              label: Text('${ref.watch(friendRequestCountProvider)}'),
              child: ListTile(
                leading: const Icon(Icons.group_add),
                title: const Text('好友申请'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FriendRequestPage()),
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('家族'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FamilyPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('动态'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DynamicsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text('退出登录',
                  style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(authProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 好友关系分类 chip（全部/好友/关注/黑名单）。
class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CatChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isActive;
  final VoidCallback onTap;

  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
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

    return ListTile(
      selected: isActive,
      selectedTileColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AvatarView(
        avatarUrl: session.avatar,
        name: session.name,
        type: session.type,
        radius: 24,
      ),
      title: Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        ? Colors.green.shade400
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
                          ? Colors.green.shade400
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
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
        ],
      ),
      onTap: onTap,
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
          Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          const Text('暂无会话\n下拉刷新或点击刷新按钮'),
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
  final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}