part of 'avatar_edit_dialog.dart';

/// 左侧页签项：选中态为白色圆角胶囊。
class _NavItem extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey<String>('avatarEditNav-$label'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: active ? scheme.surface : Colors.transparent,
        borderRadius: AppRadius.pillR,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillR,
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部横向页签（`全部` / `装扮` / …），选中项加粗加深。
class _TopTabs extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Key? tabsKey;

  const _TopTabs({
    required this.labels,
    required this.index,
    required this.onChanged,
    this.tabsKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      // 页签含文字，高度随系统字号缩放以免裁切。
      height: MediaQuery.textScalerOf(context).scale(32),
      child: ListView.separated(
        key: tabsKey,
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final active = i == index;
          return InkWell(
            onTap: () => onChanged(i),
            borderRadius: AppRadius.chipR,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                labels[i],
                style: theme.textTheme.labelLarge?.copyWith(
                  color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 可点选格子：选中态为橙金描边 + 绿色勾选角标。
class _SelectableCell extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableCell({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warning = AppSemanticColors.of(context).warning;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.inputR,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppRadius.inputR,
          border: Border.all(
            color: selected ? warning : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: warning.withValues(alpha: 0.45), blurRadius: 8)]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            child,
            if (selected)
              const Positioned(top: 2, right: 2, child: _CheckBadge()),
          ],
        ),
      ),
    );
  }
}

/// 绿色圆形勾选角标（选中格子 / 选中家族共用）。
class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check_circle,
        size: 16,
        color: AppSemanticColors.of(context).success,
      ),
    );
  }
}

/// DIY 审核态角标（`审核中` / `审核失败`）。
class _AuditTag extends StatelessWidget {
  final String text;

  /// `true` = 审核中（警示色）；`false` = 审核失败（错误色）。
  final bool warning;

  const _AuditTag({required this.text, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = warning ? AppSemanticColors.of(context).warning : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: AppRadius.chipR,
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

/// 头像框格子的占位预览：灰色圆角底 + 框图片（尺寸按 [headFrameSlotSize]）。
class _FramePreview extends StatelessWidget {
  final int id;

  const _FramePreview({required this.id});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(constraints.maxWidth, constraints.maxHeight);
        // 半径随格子自适应；框槽位必须用 headFrameSlotSize，保证不裁切外圈。
        final radius = math.max(10.0, cell * 0.28);
        final avatarSize = radius * 2;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(avatarSize * 0.25),
              ),
            ),
            HeadFrameOverlay(frameId: id, size: headFrameSlotSize(radius)),
          ],
        );
      },
    );
  }
}

/// 称号卡片：称号名 + `有效期` + 日期区间；可点选佩戴。
class _TitleCard extends StatelessWidget {
  final String name;

  /// 日期区间（`2026.07.31--永久`）；数据缺失时为 `—`。
  final String dateRange;

  /// 是否为当前佩戴称号（选中态描边 + 勾选角标）。
  final bool selected;

  /// 是否已过期（文字淡化）。
  final bool expired;

  /// 点选佩戴回调。
  final VoidCallback onTap;

  const _TitleCard({
    super.key,
    required this.name,
    required this.dateRange,
    this.selected = false,
    this.expired = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = AppSemanticColors.of(context).warning;
    final baseColor = expired
        ? scheme.onSecondaryContainer.withValues(alpha: 0.55)
        : scheme.onSecondaryContainer;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardR,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: AppRadius.cardR,
          border: Border.all(
            color: selected ? warning : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichTextView(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: baseColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '有效期',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: baseColor.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      dateRange,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: baseColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (selected)
              const Positioned(top: 0, right: 0, child: _CheckBadge()),
          ],
        ),
      ),
    );
  }
}

/// 家族名牌卡片：选中态为橙色文字 + 橙色发光描边 + 绿色勾选角标。
class _FamilyCard extends StatelessWidget {
  final FamilyInfo family;
  final bool selected;
  final VoidCallback onTap;

  const _FamilyCard({
    super.key,
    required this.family,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = AppSemanticColors.of(context).warning;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardR,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppRadius.cardR,
          border: Border.all(
            color: selected ? warning : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: warning.withValues(alpha: 0.45), blurRadius: 8)]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            RichTextView(
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected ? warning : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (selected)
              const Positioned(top: 0, right: 0, child: _CheckBadge()),
          ],
        ),
      ),
    );
  }
}

/// 降级 / 空态说明（浅色文字，绝不臆造数据）。
class _EmptyHint extends StatelessWidget {
  final String text;
  final bool center;

  const _EmptyHint(this.text, {this.center = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}
