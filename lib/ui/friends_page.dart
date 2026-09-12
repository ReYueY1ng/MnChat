import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../core/services/chat_service.dart' show SessionSnapshot;
import '../state/providers.dart';
import 'friend_request_page.dart' show FriendRequestPage, showAddFriendDialog;
import 'blacklist_page.dart';
import 'my_qr_page.dart';
import 'player_home_page.dart';
import 'widgets/avatar_view.dart';

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

class _FriendsPageState extends ConsumerState<FriendsPage> {
  String _search = '';
  bool _onlyOnline = false;

  /// 从会话快照中取全部好友 session（query_friend_list 为每个好友建一条）。
  List<ChatSession> _friends(SessionSnapshot? snap) {
    if (snap == null) return const [];
    return snap.sessions.where((s) => s.type == ChatSessionType.friend).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = ref.watch(sessionListProvider).asData?.value;
    final reqCount = ref.watch(friendRequestCountProvider);
    final friends = _friends(snap);

    // 好友页只显示"双向好友"（relation&8）：关注/黑名单不是好友，
    // 无法发起聊天，不在此列出。
    final filtered = friends.where((f) {
      if ((f.relation & 8) == 0) return false;
      if (_onlyOnline && !f.isOnline) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!f.name.toLowerCase().contains(q) && !'${f.id}'.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) {
        // 在线优先，再按昵称拼音/字符序
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('好友', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // 只看在线（单按钮切换）
          IconButton(
            tooltip: _onlyOnline ? '只看在线（开）' : '只看在线',
            onPressed: () => setState(() => _onlyOnline = !_onlyOnline),
            icon: Icon(
              _onlyOnline ? Icons.visibility : Icons.visibility_off_outlined,
              color: _onlyOnline ? theme.colorScheme.primary : null,
            ),
          ),
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
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyQrPage()),
                  );
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
      body: Column(
        children: [
          _buildFilterBar(theme),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyFriends(
                    hasData: friends.isNotEmpty,
                    onAddFriend: () => showAddFriendDialog(context, ref),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 72,
                        color: theme.colorScheme.outlineVariant),
                    itemBuilder: (context, i) {
                      final f = filtered[i];
                      return _FriendTile(
                        session: f,
                        onTap: () {
                          final cb = widget.onOpenChat;
                          if (cb != null) {
                            cb(f.id);
                          } else {
                            ref
                                .read(activeSessionProvider.notifier)
                                .open(ChatSessionType.friend, f.id);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 搜索框。
  Widget _buildFilterBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: '搜索好友昵称 / 迷你号…',
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
    );
  }
}

/// 好友行：头像 + 昵称 + 迷你号 / 关系 / 在线状态。
class _FriendTile extends StatelessWidget {
  final ChatSession session;
  final VoidCallback onTap;

  const _FriendTile({required this.session, required this.onTap});

  String _relationLabel(int relation) {
    if ((relation & 64) != 0) return '黑名单';
    if ((relation & 16) != 0) return '关注';
    if ((relation & 8) != 0) return '好友';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rel = _relationLabel(session.relation);
    final gameText = session.gameStatus ?? (session.isOnline ? '在线' : '离线');
    final name = session.name.isNotEmpty ? session.name : '${session.id}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AvatarView(
        avatarUrl: session.avatar,
        name: name,
        type: session.type,
        radius: 24,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (rel.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
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
      trailing: IconButton(
        tooltip: '查看主页',
        icon: const Icon(Icons.account_circle_outlined, size: 22),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerHomePage(targetUin: session.id),
          ),
        ),
      ),
      subtitle: Row(
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
              '$gameText · 迷你号 ${session.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: session.isOnline
                    ? Colors.green.shade400
                    : theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  final bool hasData;
  final VoidCallback onAddFriend;

  const _EmptyFriends({required this.hasData, required this.onAddFriend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!hasData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: theme.colorScheme.outline),
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
    return const Center(child: Text('没有符合条件的好友'));
  }
}
