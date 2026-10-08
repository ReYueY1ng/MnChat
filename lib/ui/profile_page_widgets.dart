part of 'profile_page.dart';

/// 个人主页顶部资料卡（对齐参考图顶栏）：
/// 头像（含头像框）+ 昵称 + 等级 / 大会员徽标 + `迷你号`（可复制）
/// + `关注`·`粉丝`·`人气值`·`信用分` 统计行 + 入口按钮行。
class _ProfileHeaderCard extends StatelessWidget {
  final String name;
  final int uin;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? frameId;

  /// 平台等级（0 = 未知，不展示徽标）。
  final int level;

  /// 是否大会员。
  final bool isVip;

  /// 主页四项统计（`role_info` 模块）；null = 未取到，展示「—」占位。
  final HomeStats? stats;

  /// 家族名（`family` 模块）；空则不显示。
  final String familyName;

  final VoidCallback onCopyUin;

  /// 以下入口只在自己主页出现：为空即不渲染（看别人主页时传 null）。
  final VoidCallback? onVisitors;
  final VoidCallback? onEditLayout;

  /// 打开「头像编辑」弹窗（点按头像或顶栏按钮均可）。
  final VoidCallback? onEditAvatar;

  const _ProfileHeaderCard({
    required this.name,
    required this.uin,
    required this.avatarUrl,
    required this.headType,
    required this.headId,
    required this.frameId,
    required this.level,
    required this.isVip,
    required this.stats,
    required this.familyName,
    required this.onCopyUin,
    this.onVisitors,
    this.onEditLayout,
    this.onEditAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HomeSectionCard(
      title: '个人资料',
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 头像本体 + 头像框统一由 AvatarView 渲染（槽位按 headFrameSlotSize
              // 放大，框不会被裁切）。点按头像打开「头像编辑」弹窗。
              Tooltip(
                message: onEditAvatar == null ? name : '头像编辑',
                child: InkWell(
                  onTap: onEditAvatar,
                  borderRadius: AppRadius.cardR,
                  child: AvatarView(
                    avatarUrl: avatarUrl,
                    name: name,
                    radius: 36,
                    headType: headType,
                    headId: headId,
                    frameId: frameId,
                  ),
                ),
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
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (level > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          LevelBadge(level: level),
                        ],
                        if (isVip) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const VipBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '迷你号 $uin',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '复制迷你号',
                          iconSize: 16,
                          visualDensity: adaptiveDensity(context),
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: onCopyUin,
                        ),
                      ],
                    ),
                    if (familyName.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.home_outlined,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              '家族: $familyName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          // 统计行：4 项计数 + 分隔线（取自 role_info 模块；缺失项 → 「—」）。
          SizedBox(
            // 该行含按钮文字，高度随系统字号缩放以免裁切。
            height: MediaQuery.textScalerOf(context).scale(44),
            child: Row(
              children: [
                Expanded(
                  child: _HomeStatTile(
                    label: '关注',
                    value: _statText(stats?.following),
                    hint: stats?.following == null
                        ? kHomeUnavailableHint
                        : null,
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _HomeStatTile(
                    label: '粉丝',
                    value: _statText(stats?.followers),
                    hint: stats?.followers == null
                        ? kHomeUnavailableHint
                        : null,
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _HomeStatTile(
                    label: '人气值',
                    value: _statText(stats?.popularity),
                    hint: stats?.popularity == null
                        ? kHomeUnavailableHint
                        : null,
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _HomeStatTile(
                    label: '信用分',
                    value: _statText(stats?.credit),
                    hint: stats?.credit == null ? kHomeUnavailableHint : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (onVisitors != null)
                OutlinedButton.icon(
                  onPressed: onVisitors,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('最近访客'),
                ),
              if (onEditLayout != null)
                FilledButton.icon(
                  // 参考图存在「编辑布局」；外部客户端无主页布局协议 → 仅外壳。
                  onPressed: onEditLayout,
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 16),
                  label: const Text('编辑布局'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 他人主页的关系操作条：关注 / 拉黑。
class _RelationActions extends StatelessWidget {
  final bool following;
  final bool blacklisted;
  final bool busy;
  final VoidCallback onFollow;
  final VoidCallback onBlacklist;

  const _RelationActions({
    required this.following,
    required this.blacklisted,
    required this.busy,
    required this.onFollow,
    required this.onBlacklist,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: following
              ? OutlinedButton.icon(
                  onPressed: busy ? null : onFollow,
                  icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                  label: const Text('已关注'),
                )
              : FilledButton.icon(
                  onPressed: busy ? null : onFollow,
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('关注'),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onBlacklist,
            icon: Icon(
              blacklisted ? Icons.person_remove : Icons.block,
              size: 18,
              color: blacklisted ? theme.colorScheme.onSurface : theme.colorScheme.error,
            ),
            label: Text(
              blacklisted ? '已在黑名单' : '拉黑',
              style: TextStyle(
                color: blacklisted ? null : theme.colorScheme.error,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 个人主页横幅（对齐参考图中央大卡）：交友宣言气泡 + `编辑` + 昵称名牌。
///
/// 参考图的 3D 角色 / 场景底图无 2D 资源可用，这里以主题渐变近似，
/// 不引入新配色。
class _HomeBannerCard extends StatelessWidget {
  final String name;

  /// 已格式化的交友宣言；空串表示未设置。
  final String declaration;

  /// 为空则不显示「编辑」（看别人主页时）。
  final VoidCallback? onEdit;

  const _HomeBannerCard({
    required this.name,
    required this.declaration,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_quote,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '交友宣言',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('编辑'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: AppRadius.inputR,
              ),
              child: Text(
                declaration.isEmpty ? '还没有设置交友宣言' : declaration,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerRight, child: _NameTag(name)),
          ],
        ),
      ),
    );
  }
}

/// 昵称名牌（参考图角色脚下的蓝色渐变名牌）：主题色胶囊 + 前景色文字。
class _NameTag extends StatelessWidget {
  final String name;

  const _NameTag(this.name);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 名牌走纯文本，必须先清洗掉 `[i][color][b]` 这类标记。
    final label = plainNickname(name);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: AppRadius.pillR,
      ),
      child: Text(
        label.isEmpty ? '未命名' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 称号胶囊（参考图紫 / 橙红渐变称号）：浅色容器底 + 图标 + 称号名。
class _TitlePill extends StatelessWidget {
  final String title;

  const _TitlePill(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: AppRadius.chipR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_police_outlined,
            size: 14,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 个人主页版块卡：标题 +（可选）计数 + 右上角操作 + 内容。
///
/// 圆角 / 描边完全沿用 [ThemeData.cardTheme]（不自定义卡片样式）。
class _HomeSectionCard extends StatelessWidget {
  final String title;

  /// 右上角计数（null 不展示）。
  final String? count;

  /// 右上角操作（如 `置顶` / `编辑`）。
  final Widget? action;

  final Widget child;
  final EdgeInsetsGeometry padding;

  const _HomeSectionCard({
    required this.title,
    this.count,
    this.action,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    count!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                ?action,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// 紧凑版块卡（参考图 `追光计划` / `勋章` 等小卡）：标题 + 计数 + 说明。
class _CompactModuleCard extends StatelessWidget {
  final String title;
  final String count;
  final String caption;

  const _CompactModuleCard({
    required this.title,
    required this.count,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Spacer(),
                Text(
                  count,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
