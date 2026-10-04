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
    final circle = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: selected ? Border.all(color: style.color, width: 2) : null,
      ),
      child: Icon(style.icon, color: style.color, size: 26),
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

/// 分类图标 / 颜色。
({IconData icon, Color color}) _categoryStyle(ThemeData theme, int channel) {
  switch (channel) {
    case MsgChannel.gift:
      return (icon: Icons.card_giftcard, color: const Color(0xFFE91E63));
    case MsgChannel.systemMail:
      return (icon: Icons.mail_outline, color: theme.colorScheme.primary);
    case MsgChannel.creator:
      return (icon: Icons.auto_awesome_outlined, color: const Color(0xFF7C4DFF));
    case MsgChannel.sysMsg:
      return (icon: Icons.notifications_none, color: const Color(0xFF546E7A));
    case MsgChannel.friendMail:
      return (icon: Icons.drafts_outlined, color: const Color(0xFFFF9800));
    case MsgChannel.activityAssistant:
      return (icon: Icons.assistant_outlined, color: const Color(0xFF009688));
    case MsgChannel.activity:
      return (icon: Icons.campaign_outlined, color: const Color(0xFFF44336));
    default:
      return (icon: Icons.mail_outline, color: theme.colorScheme.primary);
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
