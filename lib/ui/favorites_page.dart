/// 收藏夹页 —— 本机收藏（星标）的消息，按收藏时间倒序。
///
/// 数据源：drift `message_marks`（kind=favorite）左连 `chat_messages`。历史替换
/// （`replaceMessages`）可能已把消息行清掉，此时仍列出这条收藏，只是正文取不到。
/// 点一条跳回对应会话：打开会话走 `activeSessionProvider`（与通知点击同一路径），
/// 不新增导航模型。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/chat_search.dart';
import '../core/models/messages.dart' show ChatSessionType;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_l10n.dart' show l10nOf;
import 'widgets/empty_state.dart';
import 'widgets/rich_text_view.dart';

/// 收藏夹页。
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  List<ChatSearchHit>? _hits;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(databaseProvider);
      final owner = ref.read(myUinProvider);
      final hits = await db.favoriteMessages(owner);
      if (!mounted) return;
      setState(() => _hits = hits);
    } catch (_) {
      // 未注入数据库（测试）/读库失败：空列表 + 空态，不抛。
      if (!mounted) return;
      setState(() => _hits = const <ChatSearchHit>[]);
    }
  }

  /// 取消收藏：写标记后重载列表。
  Future<void> _unfavorite(ChatSearchHit hit) async {
    final marks = ref.read(messageMarksStoreProvider);
    await marks.setFavorite(hit.sessionKey, hit.uin, hit.time, false);
    await _load();
  }

  /// 跳回该条消息所在的会话。
  void _openSession(ChatSearchHit hit) {
    final parsed = parseSessionKey(hit.sessionKey);
    if (parsed == null) return;
    final type = parsed.typeName == ChatSessionType.group.name
        ? ChatSessionType.group
        : ChatSessionType.friend;
    ref.read(activeSessionProvider.notifier).open(type, parsed.id);
    Navigator.of(context).maybePop();
  }

  /// 会话显示名：会话快照里的昵称优先（好友会话会做历史坏数据净化），
  /// 找不到时回退会话 key。
  String _sessionName(String sessionKey) {
    final sessions =
        ref.watch(sessionListProvider).asData?.value.sessions ?? const [];
    for (final s in sessions) {
      if ((s.type == ChatSessionType.group ? 'group' : 'friend') ==
              parseSessionKey(sessionKey)?.typeName &&
          s.id == parseSessionKey(sessionKey)?.id) {
        return s.name;
      }
    }
    return sessionKey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = l10nOf(context);
    final hits = _hits;
    return Scaffold(
      appBar: AppBar(title: Text(l10n?.favoritesTitle ?? '收藏')),
      body: hits == null
          ? const Center(child: CircularProgressIndicator())
          : hits.isEmpty
          ? EmptyState(
              icon: Icons.star_border,
              title: l10n?.favoritesEmpty ?? '还没有收藏的消息',
              hint: l10n?.favoritesEmptyHint ?? '长按任意消息即可收藏',
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.listContent,
                ),
                child: ListView.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final hit = hits[i];
                    return ListTile(
                      title: RichTextView(
                        hit.text.isEmpty ? '（内容已不在本机）' : hit.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_sessionName(hit.sessionKey)} · ${_fmtTime(hit.time)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: l10n?.menuUnfavorite ?? '取消收藏',
                        icon: Icon(Icons.star, color: theme.colorScheme.primary),
                        onPressed: () => _unfavorite(hit),
                      ),
                      onTap: () => _openSession(hit),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// 收藏时间显示：`MM-DD HH:MM`（与消息中心左列同口径，不引额外本地化依赖）。
String _fmtTime(int epochSeconds) {
  if (epochSeconds <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
