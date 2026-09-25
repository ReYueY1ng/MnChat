/// 最佳拍档页 —— 从好友页左侧分类栏进入。
///
/// 展示头部「可建立拍档数 <当前>/<上限>」与拍档卡片（头像 / 昵称 / `Lv<N>` /
/// 别称 / 结成关系天数 / 默契度）。数据来源：
///   - 拍档列表 `miniw/bestpartner?act=get_list`
///   - 槽位 `act=get_bestpartner_data`（`unlock_normal + unlock_special` 为上限）
///   - 等级 `miniw/upgrade?act=get_level_info_batch`
///   - 资料（昵称 / 头像 / 头像框）`miniw/profile getProfileBatch3`
///
/// 已知限制：
///   - 关系等级进度依赖服务端 `FriendSystem.levelIntimacy.partnerLevel_list`，
///     本地未获取，故只展示默契度数值、不画臆造的进度条；
///   - 别称（`title_id`）的名称映射来自服务端配置，本地未获取，暂以
///     `别称 #<id>` 展示原始 id。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/partner.dart';
import '../core/services/profile.dart';
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/partner_badges.dart';
import 'widgets/rich_text_view.dart';

class PartnerPage extends ConsumerWidget {
  const PartnerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final partnersAsync = ref.watch(myPartnerListProvider);
    final slot = ref.watch(partnerSlotProvider).asData?.value;
    final levels =
        ref.watch(partnerLevelsProvider).asData?.value ??
        const <int, int>{};
    final profiles =
        ref.watch(partnerProfilesProvider).asData?.value ??
        const <int, PlayerProfile>{};
    // 关系等级阈值（服务端 visual-cfg）；缺失时为空列表 → 不画进度条。
    final levelCfg =
        ref.watch(partnerLevelConfigProvider).asData?.value ??
        const <(int, int)>[];
    final count = partnersAsync.asData?.value.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '最佳拍档',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(myPartnerListProvider);
              ref.invalidate(partnerSlotProvider);
              ref.invalidate(partnerLevelsProvider);
              ref.invalidate(partnerProfilesProvider);
              ref.invalidate(partnerLevelConfigProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.listContent),
          child: Column(
            children: [
              _buildHeader(theme, count, slot),
              const Divider(height: 1),
              Expanded(
                child: partnersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败: $e')),
                  data: (list) => list.isEmpty
                      ? const Center(child: Text('暂无最佳拍档'))
                      : _buildList(theme, list, levels, profiles, levelCfg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 头部：可建立拍档数 `<当前>/<上限>`。
  Widget _buildHeader(ThemeData theme, int current, PartnerSlotInfo? slot) {
    final total = slot?.total ?? 0;
    return Padding(
      padding: AppSpacing.pagePadding,
      child: Row(
        children: [
          Icon(
            Icons.handshake_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('可建立拍档数', style: theme.textTheme.bodyMedium),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$current/$total',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    ThemeData theme,
    List<PartnerInfo> partners,
    Map<int, int> levels,
    Map<int, PlayerProfile> profiles,
    List<(int level, int intimacyValue)> levelCfg,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      itemCount: partners.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) => _partnerCard(
        theme,
        partners[i],
        levels[partners[i].bestUin] ?? 0,
        profiles[partners[i].bestUin],
        levelCfg,
        now,
      ),
    );
  }

  /// 单张拍档卡片。
  Widget _partnerCard(
    ThemeData theme,
    PartnerInfo partner,
    int level,
    PlayerProfile? profile,
    List<(int level, int intimacyValue)> levelCfg,
    int now,
  ) {
    final name = (profile != null && profile.nickname.isNotEmpty)
        ? profile.nickname
        : '${partner.bestUin}';
    // 无人物中心头信息时用资料的 SkinID / Model 回退角色头像（与好友列表同源）。
    final fallback = profile == null
        ? null
        : PlayerProfile.resolveRoleHeadFallback(
            skinId: profile.headSkinId,
            model: profile.headModel,
          );
    // 关系等级进度：阈值来自 FriendSystem 配置；缺失时 next 为 null，仅展示数值。
    final (_, nextScore) = partnerLevelFor(partner.tacitnum, levelCfg);
    final progress = RelationProgress(
      current: partner.tacitnum,
      next: nextScore > 0 ? nextScore : null,
    );

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.cardR,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarView(
            avatarUrl: profile?.avatarUrl,
            name: name,
            radius: 26,
            headType: fallback?.type,
            headId: fallback?.id,
            frameId: profile?.headFrameId,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: RichTextView(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (level > 0) ...[
                      const SizedBox(width: AppSpacing.xs),
                      LevelBadge(level: level),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  partner.labName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (partner.titleId > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '别称 #${partner.titleId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  '结成关系天数：${partner.daysAt(now)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildTacitRow(theme, partner, progress),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 默契度行：数值（`<tacitnum>/<nextLevelScore>`）+ 进度条；阈值未知时只展示数值。
  Widget _buildTacitRow(
    ThemeData theme,
    PartnerInfo partner,
    RelationProgress progress,
  ) {
    final color = tacitBadgeColor(partner.lab);
    final ratio = progress.ratio;
    final next = progress.next;
    final label = next == null
        ? '默契度 ${partner.tacitnum}'
        : '默契度 ${partner.tacitnum}/$next';
    return Tooltip(
      message: next == null
          ? '默契度 · ${partner.labName}'
          : '默契度 · ${partner.labName}（${partner.tacitnum}/$next）',
      child: Row(
        children: [
          Icon(Icons.hexagon, size: 12, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (ratio != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ClipRRect(
                borderRadius: AppRadius.pillR,
                child: LinearProgressIndicator(value: ratio, minHeight: 6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
