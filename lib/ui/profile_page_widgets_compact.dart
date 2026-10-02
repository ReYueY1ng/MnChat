part of 'profile_page.dart';

/// 统计项：数值在上、标签在下；[hint] 非空时挂 Tooltip 说明数据来源缺口。
class _HomeStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;

  const _HomeStatTile({required this.label, required this.value, this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
    final h = hint;
    return h == null ? tile : Tooltip(message: h, child: tile);
  }
}

/// 统计行内的竖直分隔线。
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
    );
  }
}

/// 无协议数据版块的降级说明：一行浅色文字（绝不臆造数据）。
class _UnavailableNote extends StatelessWidget {
  final String text;

  const _UnavailableNote(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

/// 参考图中并排的两个版块：宽度足够时并排，窄屏降级为上下堆叠。
class _ResponsivePair extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _ResponsivePair({required this.first, required this.second});

  /// 并排所需的最小宽度；低于该值则堆叠（避免卡片内文字被挤成竖排）。
  static const double _sideBySideMinWidth = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBySideMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: AppSpacing.md),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// 紧凑版块网格（参考图右列 2×2 小卡）：宽屏两列、窄屏单列。
class _CompactModuleGrid extends StatelessWidget {
  final List<Widget> children;

  const _CompactModuleGrid({required this.children});

  /// 两列所需的最小宽度；低于该值单列堆叠。
  static const double _twoColumnMinWidth = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= _twoColumnMinWidth;
        final width = twoCol
            ? (constraints.maxWidth - AppSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// 可点选瓦片（皮肤 / 立绘共用）：选中时主题色描边。
class _SelectableTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableTile({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.inputR,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: AppRadius.inputR,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 页脚：`IP属地` + 迷你号（对齐参考图底边）。
///
/// IP 属地取自 `miniw/user_ext?act=get_user_addr`
/// （见 [PlayerHomeClient.getUserAddr]）；失败时解析器已回退为「未知」，
/// [ipAddr] 为 null 仅表示尚未取到，此处显示占位。
class _HomeFooter extends StatelessWidget {
  final int uin;

  /// IP 属地；null = 尚未取到（显示占位）。
  final String? ipAddr;

  const _HomeFooter({required this.uin, this.ipAddr});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    return Row(
      children: [
        Icon(Icons.public, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: AppSpacing.xs),
        Text('IP属地：${ipAddr ?? kHomeUnknownValue}', style: style),
        const Spacer(),
        Text('$uin', style: style),
      ],
    );
  }
}

/// 个人主页「最佳拍档」版块的单条拍档：头像（含头像框）+ 昵称 +
/// 等级 / 默契度 / 大会员徽标（与最佳拍档页同源控件）。
class HomePartnerTile extends StatelessWidget {
  final PartnerInfo partner;

  /// 拍档资料（昵称 / 头像 / 头像框）；为空时退回迷你号 + 首字头像。
  final PlayerProfile? profile;

  /// 拍档平台等级（0 = 未知，不展示 `Lv` 徽标）。
  final int level;

  /// 拍档是否大会员。
  final bool isVip;

  final VoidCallback? onTap;

  const HomePartnerTile({
    super.key,
    required this.partner,
    this.profile,
    this.level = 0,
    this.isVip = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final name = (p != null && p.nickname.isNotEmpty)
        ? p.nickname
        : '${partner.bestUin}';
    // 无人物中心头信息时用资料的 SkinID / Model 回退角色头像（与好友列表同源）。
    final fallback = p == null
        ? null
        : PlayerProfile.resolveRoleHeadFallback(
            skinId: p.headSkinId,
            model: p.headModel,
          );
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            AvatarView(
              avatarUrl: p?.avatarUrl,
              name: name,
              radius: 24,
              headType: fallback?.type,
              headId: fallback?.id,
              frameId: p?.headFrameId,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: LayoutBuilder(
                builder: (context, nameConstraints) => Row(
                  children: [
                    Flexible(
                      child: RichTextView(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (level > 0 || isVip) ...[
                      const SizedBox(width: AppSpacing.xs),
                      PartnerBadgeSlot(
                        rowWidth: nameConstraints.maxWidth,
                        child: PartnerNameBadges(
                          level: level,
                          partner: partner,
                          isVip: isVip,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
