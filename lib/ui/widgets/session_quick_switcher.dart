/// Ctrl+K 快速切换会话：一个可搜索的会话列表弹层。
///
/// 与服务端无关，只读 `sessionListProvider` 的快照；回车打开第一条匹配，
/// 点击任意一行也会打开并关闭弹层。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/messages.dart' show ChatSession;
import '../../core/models/nickname.dart' show plainNickname;
import '../../state/providers.dart';
import '../theme/app_tokens.dart';
import 'avatar_view.dart';

import 'app_l10n.dart' show l10nOf;

/// 快速切换弹层的测试定位 key（保持名字稳定）。
const Key sessionQuickSwitcherKey = Key('session_quick_switcher');
const Key sessionQuickSwitcherFieldKey = Key('session_quick_switcher_field');

/// 打开快速切换弹层。
Future<void> showSessionQuickSwitcher(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const SessionQuickSwitcher(),
  );
}

class SessionQuickSwitcher extends ConsumerStatefulWidget {
  const SessionQuickSwitcher({super.key});

  @override
  ConsumerState<SessionQuickSwitcher> createState() =>
      _SessionQuickSwitcherState();
}

class _SessionQuickSwitcherState extends ConsumerState<SessionQuickSwitcher> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ChatSession> _matches(List<ChatSession> sessions) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return sessions;
    return [
      for (final s in sessions)
        if (plainNickname(s.name).toLowerCase().contains(q) ||
            '${s.id}'.contains(q))
          s,
    ];
  }

  void _open(ChatSession s) {
    ref.read(activeSessionProvider.notifier).open(s.type, s.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sessions =
        ref.watch(sessionListProvider).asData?.value.sessions ??
        const <ChatSession>[];
    final matches = _matches(sessions);
    final theme = Theme.of(context);
    return Dialog(
      key: sessionQuickSwitcherKey,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: sessionQuickSwitcherFieldKey,
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: l10nOf(context)?.sessionsSearchConversationsNicknameMini ?? '搜索会话（昵称或迷你号）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (matches.isNotEmpty) _open(matches.first);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: matches.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          l10nOf(context)?.sessionsNoMatchingConversations ?? '没有匹配的会话',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        itemBuilder: (context, i) {
                          final s = matches[i];
                          return ListTile(
                            dense: true,
                            leading: AvatarView(
                              name: s.name,
                              avatarUrl: s.avatar,
                              type: s.type,
                              radius: 16,
                              headType: s.headType,
                              headId: s.headId,
                              frameId: s.headFrameId,
                            ),
                            title: Text(
                              plainNickname(s.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              s.type.name == 'group'
                                  ? l10nOf(context)?.sessionsGroup(s.id) ?? '群 ${s.id}'
                                  : l10nOf(context)?.sessionsFriend(s.id) ?? '好友 ${s.id}',
                            ),
                            onTap: () => _open(s),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
