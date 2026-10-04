part of 'friends_page.dart';

/// 好友行：头像 + 昵称 + 迷你号 / 关系 / 在线状态。
class _FriendTile extends ConsumerWidget {
  final ChatSession session;
  final VoidCallback onTap;

  /// 长按 / 桌面端右键打开好友操作菜单（参数为指针全局坐标）。
  final ValueChanged<Offset>? onLongPress;
  final ValueChanged<Offset>? onSecondaryTap;

  /// 点击头像打开玩家信息浮窗（仅好友会话传入），参数为指针全局坐标。
  final ValueChanged<Offset>? onAvatarTap;

  /// 批量管理模式下：行首显示勾选框。
  final bool batchMode;
  final bool selected;
  final VoidCallback? onSelectToggle;

  const _FriendTile({
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onAvatarTap,
    this.batchMode = false,
    this.selected = false,
    this.onSelectToggle,
  });

  String _relationLabel(int relation) {
    // 黑名单优先；然后是「好友」——同为好友且互相关注时（relation 含 8|16）
    // 必须显示「好友」而非「关注」，因此 bit3(8) 要先于 bit4(16) 判断。
    if ((relation & 64) != 0) return '黑名单';
    if ((relation & 8) != 0) return '好友';
    if ((relation & 16) != 0) return '关注';
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isGroup = session.type == ChatSessionType.group;
    final rel = _relationLabel(session.relation);
    final gameText = isGroup
        ? '群聊'
        : (session.gameStatus ?? (session.isOnline ? '在线' : '离线'));
    final name = session.name.isNotEmpty ? session.name : '${session.id}';

    // 等级 / 拍档 / 大会员 / 默契度：来自会话级批量缓存（随会话流一次拉取）。
    final directory =
        ref.watch(partnerDirectoryProvider).asData?.value ??
        PartnerDirectory.empty;
    final level = isGroup ? 0 : directory.levelOf(session.id);
    final partner = isGroup ? null : directory.partnerOf(session.id);
    final isVip = !isGroup && directory.isVip(session.id);
    // 关系等级阈值（服务端 visual-cfg）；缺失时为空列表 → 默契度徽标不画进度条。
    final levelCfg =
        ref.watch(partnerLevelConfigProvider).asData?.value ??
        const <(int, int)>[];

    // ListTile 给 leading 的高度上限是 (isDense ? 48 : 56) + 密度纵向调整，
    // 桌面紧凑密度下只有 48，会把有框槽位（radius * 2 / 0.76 ≈ 63.2）压成
    // 非正方形并被 cover 裁掉框外圈。故抬高纵向密度（见 [kAvatarListTileDensity]），
    // 并用 minTileHeight 兜住行高，保证槽位完整可见。
    final avatar = AvatarView(
      avatarUrl: session.avatar,
      name: name,
      type: session.type,
      radius: 24,
      headType: session.headType,
      headId: session.headId,
      frameId: session.headFrameId,
    );

    final tile = ListTile(
      // 与全局 cardTheme 一致：surfaceContainerLow 底色 + cardR 圆角 + 细描边，
      // ListTile 的 shape 同时作为 InkWell 的 customBorder，选中 / 悬停 / 水波
      // 反馈会被裁进圆角内（不会出现直角溢出）。
      shape: _cardLikeShape(theme),
      tileColor: theme.colorScheme.surfaceContainerLow,
      contentPadding: AppSpacing.listTilePadding,
      visualDensity: kAvatarListTileDensity,
      minTileHeight: headFrameSlotSize(24),
      // 批量管理：行首换成勾选框
      leading: batchMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => onSelectToggle?.call(),
            )
          : onAvatarTap == null
          ? avatar
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              // onTapUp 才拿得到指针坐标（浮窗要锚在点击处）。
              onTapUp: (d) => onAvatarTap!(d.globalPosition),
              child: avatar,
            ),
      // `Row` 给非 flex 子节点的是无界主轴约束，徽标拿不到行宽，所以这里用
      // `LayoutBuilder` 量出标题行宽度并显式传给槽位（见 [PartnerBadgeSlot]）。
      title: LayoutBuilder(
        builder: (context, titleConstraints) => Row(
          children: [
            Flexible(
              child: RichTextView(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 默契度是**每个好友都有**的（`get_list` 里非拍档项 `lab == 0`），
            // 所以这里显式传值 —— 非拍档也显示，配色用 lab（0 = 默认色）。
            // 徽标宽度受限 + 内部按预算降级 → 昵称永远不会被挤没。
            if (!isGroup) ...[
              const SizedBox(width: AppSpacing.xs),
              PartnerBadgeSlot(
                rowWidth: titleConstraints.maxWidth,
                child: PartnerNameBadges(
                  level: level,
                  partner: partner,
                  isVip: isVip,
                  levels: levelCfg,
                  tacitnum: directory.tacitOf(session.id),
                  lab: partner?.lab ?? 0,
                ),
              ),
            ],
            if (rel.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: AppRadius.chipR,
                ),
                child: Text(
                  rel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: isGroup
          ? null
          : IconButton(
              tooltip: '查看主页',
              icon: const Icon(Icons.account_circle_outlined, size: 22),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlayerHomePage(targetUin: session.id),
                ),
              ),
            ),
      subtitle: isGroup
          ? Text(
              '点击进入群聊',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: session.isOnline
                        ? semantic.success
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '$gameText · 迷你号 ${session.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: session.isOnline
                          ? semantic.success
                          : theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
      onTap: onTap,
      // 长按不挂 ListTile 上：它不给指针坐标，而浮动菜单要锚在按下处。
    );

    // 长按 / 右键（桌面端）由外层 GestureDetector 接管（ListTile 不暴露
    // secondary tap，onLongPress 也没有坐标）。
    return GestureDetector(
      onLongPressStart: onLongPress == null
          ? null
          : (d) => onLongPress!(d.globalPosition),
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (d) => onSecondaryTap!(d.globalPosition),
      child: tile,
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  final bool isGroup;
  final bool hasData;
  final VoidCallback onAddFriend;

  const _EmptyFriends({
    required this.isGroup,
    required this.hasData,
    required this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!hasData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('暂无好友\n下拉刷新或点击右上角添加'),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onAddFriend,
              icon: const Icon(Icons.person_search),
              label: const Text('按迷你号添加'),
            ),
          ],
        ),
      );
    }
    return Center(child: Text(isGroup ? '暂无群聊' : '没有符合条件的好友'));
  }
}

/// 复刻全局 `cardTheme` 的外形：cardR 圆角 + 同一条 1px 描边。
///
/// 优先取主题里 `CardThemeData.shape` 的描边，保证与全站卡片完全一致；
/// 拿不到时退回到 `outlineVariant`（与 `buildAppTheme` 中的 border 同源）。
RoundedRectangleBorder _cardLikeShape(ThemeData theme) {
  final shape = theme.cardTheme.shape;
  final side = shape is RoundedRectangleBorder
      ? shape.side
      : BorderSide(color: theme.colorScheme.outlineVariant);
  return RoundedRectangleBorder(borderRadius: AppRadius.cardR, side: side);
}
