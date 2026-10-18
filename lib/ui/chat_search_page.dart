/// 跨会话聊天记录搜索页。
///
/// 走 `AppDatabase.searchMessages`：≥3 字用 FTS5 trigram（中文子串可命中），
/// 1~2 字自动回退 LIKE；本机已删除的消息不会出现。结果按时间倒序，点一条跳回
/// 对应会话（`activeSessionProvider`，与通知点击同一条路径）。
///
/// 不做输入防抖：本地 SQLite 上一次查询是毫秒级，省掉 Timer 也让 widget 测试不必
/// 处理悬挂定时器；用 [_seq] 丢弃过期响应，避免乱序回写。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/chat_search.dart';
import '../core/models/messages.dart' show ChatSessionType;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_l10n.dart' show l10nOf;
import 'widgets/empty_state.dart';
import 'widgets/rich_text_view.dart';

/// 跨会话搜索页。
class ChatSearchPage extends ConsumerStatefulWidget {
  const ChatSearchPage({super.key});

  @override
  ConsumerState<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends ConsumerState<ChatSearchPage> {
  final TextEditingController _controller = TextEditingController();

  /// 当前关键词（已 trim）。
  String _query = '';

  /// 命中结果；null 表示正在查/尚未查。
  List<ChatSearchHit>? _hits = const <ChatSearchHit>[];

  /// 查询序号：只接受最后一次查询的回写（快速连打时防乱序）。
  int _seq = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    setState(() {
      _query = q;
      _hits = q.isEmpty ? const <ChatSearchHit>[] : null;
    });
    if (q.isEmpty) return;
    final seq = ++_seq;
    List<ChatSearchHit> hits;
    try {
      final db = ref.read(databaseProvider);
      hits = await db.searchMessages(
        ref.read(myUinProvider),
        q,
        limit: 200,
      );
    } catch (_) {
      // 未注入数据库（测试）/查询失败：空结果 + 提示态，不抛。
      hits = const <ChatSearchHit>[];
    }
    if (!mounted || seq != _seq) return;
    setState(() => _hits = hits);
  }

  /// 跳回命中消息所在的会话。
  void _openHit(ChatSearchHit hit) {
    final parsed = parseSessionKey(hit.sessionKey);
    if (parsed == null) return;
    final type = parsed.typeName == ChatSessionType.group.name
        ? ChatSessionType.group
        : ChatSessionType.friend;
    ref.read(activeSessionProvider.notifier).open(type, parsed.id);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = l10nOf(context);
    final hits = _hits;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: l10n?.searchHint ?? '搜索全部会话',
            border: InputBorder.none,
            isDense: true,
          ),
          onChanged: (v) => unawaited(_search(v)),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: l10n?.commonCancel ?? '取消',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                unawaited(_search(''));
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.listContent),
          child: switch (hits) {
            null => const Center(child: CircularProgressIndicator()),
            [] when _query.isEmpty => EmptyState(
              icon: Icons.search,
              title: l10n?.searchTitle ?? '搜索聊天记录',
              hint: l10n?.searchEmptyHint ?? '换个关键词试试，支持单字搜索',
            ),
            [] => EmptyState(
              icon: Icons.search,
              title: l10n?.searchEmpty ?? '没有匹配的消息',
              hint: l10n?.searchEmptyHint ?? '换个关键词试试，支持单字搜索',
            ),
            _ => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n?.searchCount(hits.length) ?? '找到 ${hits.length} 条',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: hits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: _Highlighted(text: hits[i].text, query: _query),
                      subtitle: Text(
                        '${_sessionLabel(hits[i].sessionKey)} · '
                        '${_fmtTime(hits[i].time)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      onTap: () => _openHit(hits[i]),
                    ),
                  ),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }

  /// 会话标签：能解析出会话时用会话名（好友会话名会做历史坏数据净化）。
  String _sessionLabel(String sessionKey) {
    final parsed = parseSessionKey(sessionKey);
    if (parsed == null) return sessionKey;
    final sessions =
        ref.watch(sessionListProvider).asData?.value.sessions ?? const [];
    for (final s in sessions) {
      if (s.id == parsed.id &&
          (s.type == ChatSessionType.group ? 'group' : 'friend') ==
              parsed.typeName) {
        return s.name;
      }
    }
    return sessionKey;
  }
}

/// `YYYY-MM-DD HH:MM` 之外只保留 `MM-DD HH:MM`（列表里够用）。
String _fmtTime(int epochSeconds) {
  if (epochSeconds <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 命中片段高亮（只高亮第一处，大小写不敏感）。
class _Highlighted extends StatelessWidget {
  final String text;
  final String query;

  const _Highlighted({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    if (text.isEmpty) {
      return Text('（无文本内容）', style: base);
    }
    final at = query.isEmpty ? -1 : text.toLowerCase().indexOf(query);
    if (at < 0) {
      return RichTextView(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final end = (at + query.length).clamp(0, text.length);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: text.substring(at, end),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      style: base,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 搜索页的空态/提示态已收敛到 `widgets/empty_state.dart` 的 [EmptyState]。
