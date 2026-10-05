part of 'mail_page.dart';

/// 顶部圆入口按钮（圆底图标 + 标题 + 未读角标）。
class _TopEntryButton extends StatelessWidget {
  final MsgBoxEntry entry;
  final int unread;
  final bool selected;
  final VoidCallback onTap;

  const _TopEntryButton({
    required this.entry,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _entryStyle(theme, entry);
    // M3 选中态：secondaryContainer 圆底 + onSecondaryContainer 图标；
    // 未选中用 surfaceContainerHighest + 入口品牌色图标。无描边、无光晕。
    final circle = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(
        style.icon,
        color: selected ? theme.colorScheme.onSecondaryContainer : style.color,
        size: 26,
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            if (unread > 0)
              Badge(
                label: Text(entry == MsgBoxEntry.fans ? 'NEW' : '$unread'),
                child: circle,
              )
            else
              circle,
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 未读角标（红底白字，>99 显示 99+）。
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: AppRadius.pillR,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.colorScheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 行内 `详情` 链接。
class _DetailButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DetailButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 28),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('详情'),
    );
  }
}

/// 分类图标 / 颜色（对齐截图左列的彩色圆角图标）。
({IconData icon, Color color}) _categoryStyle(ThemeData theme, int channel) {
  switch (channel) {
    case MsgChannel.gift:
      return (icon: Icons.card_giftcard, color: const Color(0xFFC158DC));
    case MsgChannel.systemMail:
      return (icon: Icons.mail_outline, color: const Color(0xFF2196F3));
    case MsgChannel.sysMsg:
      return (icon: Icons.settings, color: const Color(0xFF5C6BC0));
    case MsgChannel.creator:
      return (icon: Icons.brush_outlined, color: const Color(0xFF4CAF50));
    case MsgChannel.friendMail:
      return (
        icon: Icons.contact_mail_outlined,
        color: const Color(0xFFFFA726),
      );
    case MsgChannel.activityAssistant:
      return (icon: Icons.flag, color: const Color(0xFFEC407A));
    case MsgChannel.activity:
      return (icon: Icons.campaign_outlined, color: const Color(0xFFFF7043));
    default:
      return (icon: Icons.mail_outline, color: theme.colorScheme.primary);
  }
}

/// 左列分类图标：饱合色圆角方块 + 白色字形（对齐截图）。
class _CategoryIcon extends StatelessWidget {
  final ({IconData icon, Color color}) style;

  const _CategoryIcon({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: style.color,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Icon(style.icon, color: Colors.white, size: 22),
    );
  }
}

/// 右栏「全部 ▾」类型筛选胶囊（深底 pill，对齐截图）。
class _TypeFilterPill extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const _TypeFilterPill({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: '筛选类型',
      onSelected: onChanged,
      itemBuilder: (ctx) => [
        for (final o in options)
          PopupMenuItem<String>(
            value: o,
            child: Row(
              children: [
                if (o == value)
                  Icon(Icons.check, size: 16, color: theme.colorScheme.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(o),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: AppRadius.pillR,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

/// 粉丝条目的「关注」按钮（M3 filled 按钮）。
class _FollowButton extends StatelessWidget {
  final bool followed;
  final VoidCallback? onPressed;

  const _FollowButton({required this.followed, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: FilledButton(
        onPressed: followed ? null : onPressed,
        style: FilledButton.styleFrom(
          // M3 默认配色（primary / onPrimary），与全局强调色一致。
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(followed ? '已关注' : '关注'),
      ),
    );
  }
}

/// 顶部入口图标 / 颜色。
({IconData icon, Color color}) _entryStyle(ThemeData theme, MsgBoxEntry entry) {
  switch (entry) {
    case MsgBoxEntry.dynamics:
      return (icon: Icons.favorite_border, color: const Color(0xFFE91E63));
    case MsgBoxEntry.fans:
      return (
        icon: Icons.person_add_alt_1_outlined,
        color: const Color(0xFFFF9800),
      );
    case MsgBoxEntry.works:
      return (
        icon: Icons.photo_library_outlined,
        color: theme.colorScheme.primary,
      );
  }
}
