import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../state/providers.dart';

/// 会话列表页（左侧栏）。
class SessionListPage extends ConsumerWidget {
  final List<ChatSession> sessions;

  const SessionListPage({super.key, required this.sessions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final active = ref.watch(activeSessionProvider);

    return Column(
      children: [
        // 顶部标题栏
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text('会话', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.read(chatServiceProvider).loadSessions(),
                ),
                IconButton(
                  tooltip: '退出登录',
                  icon: const Icon(Icons.logout),
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                ),
              ],
            ),
          ),
        ),
        // 用户信息条
        ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              auth.auth?.name.isNotEmpty == true ? auth.auth!.name.characters.first : '?',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(auth.auth?.name ?? ''),
          subtitle: Text('Uin: ${auth.auth?.uin ?? '-'}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        const Divider(height: 1),
        // 会话列表
        Expanded(
          child: sessions.isEmpty
              ? const _EmptySessions()
              : ListView.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = sessions[i];
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

    return ListTile(
      selected: isActive,
      selectedTileColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      leading: CircleAvatar(
        backgroundColor: session.type == ChatSessionType.group
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.primaryContainer,
        child: Icon(
          session.type == ChatSessionType.group ? Icons.group : Icons.person,
          color: session.type == ChatSessionType.group
              ? theme.colorScheme.onTertiaryContainer
              : theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
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
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          const Text('暂无会话\n下拉刷新或点击刷新按钮'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {},
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