/// 搭子页：拍档默契度 / 该互动提醒 / 最近玩伴。
///
/// 三块数据来源与口径：
/// - **拍档与默契度**：`partnerDirectoryProvider`（`/miniw/bestpartner`
///   get_list/get_data 聚合）。`lab > 0` 才是拍档，`tacitnum` 每个好友都有。
/// - **该互动了**：官方规则是「连续 30 天不互动起每天 -7」（见
///   `models/partner_nudge.dart`）。服务端**不下发**上次互动时间，所以这里用
///   **本机聊天记录**的最后一条消息时间兜底（`AppDatabase.lastMessageTimesByUin`），
///   只提醒、不臆造数值。
/// - **最近玩伴**：`/server/friend query_recent_partner`（`FriendClient`）。
///   线上实测可达，但返回的五元组只有元素 0（迷你号）有确定含义，因此时间列
///   只在元素 4 落在合理 epoch 区间时显示，并标注为推测。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart' show ChatSession, ChatSessionType;
import '../core/models/partner_nudge.dart';
import '../core/models/recent_partner.dart';
import '../core/services/friend.dart' show FriendClient;
import '../core/services/partner.dart' show PartnerDirectory, partnerLevelFor;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/empty_state.dart';
import 'widgets/rich_text_view.dart';

/// 搭子页。
class PartnersPage extends ConsumerStatefulWidget {
  const PartnersPage({super.key});

  @override
  ConsumerState<PartnersPage> createState() => _PartnersPageState();
}

class _PartnersPageState extends ConsumerState<PartnersPage> {
  /// uin → 本机最后一条消息时间（epoch 秒）。
  Map<int, int> _lastInteract = const <int, int>{};

  /// 最近玩伴：null = 正在拉；空列表 = 拉到了但没有（或失败，见 [_recentError]）。
  List<RecentPartner>? _recent;

  /// 最近玩伴拉取失败的原因（可见的失败，不静默降级）。
  String? _recentError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocalInteractions());
    unawaited(_loadRecent());
  }

  /// 载入"上次互动时间"（本机聊天记录）。
  Future<void> _loadLocalInteractions() async {
    Set<int> uins = const <int>{};
    try {
      final dir = await ref.read(partnerDirectoryProvider.future);
      uins = dir.partners.keys.toSet();
    } catch (_) {
      // 拍档目录拉不到：仍然把整个账号的聚合拉出来（提醒只用得上这些 uin 的交集）。
    }
    try {
      final db = ref.read(databaseProvider);
      final owner = ref.read(myUinProvider);
      final times = await db.lastMessageTimesByUin(owner, uins: uins);
      if (!mounted) return;
      setState(() => _lastInteract = times);
    } catch (_) {
      // 测试环境未注入 databaseProvider：保持空表，页面照常渲染。
    }
  }

  /// 拉最近玩伴（只读接口）。
  Future<void> _loadRecent() async {
    setState(() {
      _recent = null;
      _recentError = null;
    });
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) {
      if (!mounted) return;
      setState(() => _recent = const <RecentPartner>[]);
      return;
    }
    try {
      final client = FriendClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final decoded = await client.queryRecentPartner();
      if (!mounted) return;
      setState(() => _recent = parseRecentPartners(decoded));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recent = const <RecentPartner>[];
        _recentError = '$e';
      });
    }
  }

  /// 打开与该 uin 的好友会话。
  void _openFriend(int uin) {
    ref.read(activeSessionProvider.notifier).open(ChatSessionType.friend, uin);
    Navigator.of(context).maybePop();
  }

  /// 显示名：优先会话列表里的名字，取不到回退迷你号。
  String _nameOf(int uin) {
    final sessions =
        ref.watch(sessionListProvider).asData?.value.sessions ??
        const <ChatSession>[];
    for (final s in sessions) {
      if (s.id == uin) return s.name;
    }
    return '迷你号 $uin';
  }

  DateTime? _lastAt(int uin) {
    final t = _lastInteract[uin];
    return t == null ? null : DateTime.fromMillisecondsSinceEpoch(t * 1000);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dir =
        ref.watch(partnerDirectoryProvider).asData?.value ??
        PartnerDirectory.empty;
    final levels =
        ref.watch(partnerLevelConfigProvider).asData?.value ??
        const <(int level, int intimacyValue)>[];

    // 进入衰减区的拍档（≥30 天没互动）。
    final stale = <(int uin, int tacit, int days, int floor)>[];
    // 全部拍档（lab > 0）。
    final partners = <(int uin, int tacit, int level, int next)>[];
    for (final entry in dir.partners.entries) {
      final uin = entry.key;
      final tacit = entry.value.tacitnum;
      if (!dir.isPartner(uin)) continue;
      final (cur, next) = partnerLevelFor(tacit, levels);
      partners.add((uin, tacit, cur, next));
      final days = daysSinceInteraction(_lastAt(uin), now: now);
      if (days != null && days >= kPartnerStaleDays) {
        stale.add((
          uin,
          tacit,
          days,
          projectTacitnum(tacit, days: days, hasRelation: true),
        ));
      }
    }
    stale.sort((a, b) => b.$3.compareTo(a.$3));
    partners.sort((a, b) => b.$2.compareTo(a.$2));

    return Scaffold(
      appBar: AppBar(
        title: const Text('搭子'),
        actions: [
          IconButton(
            tooltip: '刷新最近玩伴',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_loadRecent()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.listContent),
          child: ListView(
            children: [
              if (stale.isNotEmpty) ...[
                _sectionHeader(
                  theme,
                  '该互动了',
                  '连续 $kPartnerStaleDays 天不互动，默契度每天 -$kPartnerDecayPerDay',
                ),
                for (final (uin, tacit, days, floor) in stale)
                  _tile(
                    uin: uin,
                    trailing: Text(
                      staleDaysLabel(days),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    subtitle: '默契度 $tacit → 再不互动会降到 $floor',
                  ),
              ],
              _sectionHeader(theme, '我的拍档', '默契度与关系等级（服务端数据）'),
              if (partners.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: EmptyState(
                    icon: Icons.favorite_border,
                    title: '还没有拍档',
                    hint: '在游戏里与好友的默契度达到 100 即可建立拍档关系',
                  ),
                )
              else
                for (final (uin, tacit, level, next) in partners)
                  _tile(
                    uin: uin,
                    trailing: Text(
                      'LV$level',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    subtitle: next > 0
                        ? '默契度 $tacit / 下一级 $next'
                        : '默契度 $tacit',
                  ),
              _sectionHeader(theme, '最近玩伴', '退出房间后也能找回一起玩过的人'),
              ..._recentSection(theme),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  /// 最近玩伴区块（加载中 / 失败 / 空 / 列表）。
  List<Widget> _recentSection(ThemeData theme) {
    final error = _recentError;
    final recent = _recent;
    if (error != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: ErrorRetryCard(
            message: '最近玩伴拉取失败',
            detail: error,
            onRetry: () => unawaited(_loadRecent()),
          ),
        ),
      ];
    }
    if (recent == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (recent.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: EmptyState(
            icon: Icons.people_outline,
            title: '还没有一起玩过的伙伴',
            hint: '进过房间后这里会出现一起玩过的人',
          ),
        ),
      ];
    }
    return [
      for (final p in recent)
        _tile(
          uin: p.uin,
          trailing: Text(
            _recentTimeLabel(p),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          subtitle: '最近一起玩过',
        ),
    ];
  }

  /// 最近玩伴的时间列：只有元素 4 落在合理 epoch 区间才显示（字段含义为推测）。
  String _recentTimeLabel(RecentPartner p) {
    final at = p.lastTime;
    if (at == null) return '';
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  Widget _sectionHeader(ThemeData theme, String title, String hint) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.xs,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    ),
  );

  Widget _tile({
    required int uin,
    required Widget trailing,
    required String subtitle,
  }) => ListTile(
    title: RichTextView(
      _nameOf(uin),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    ),
    trailing: trailing,
    onTap: () => _openFriend(uin),
  );
}
