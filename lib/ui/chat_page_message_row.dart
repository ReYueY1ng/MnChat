part of 'chat_page.dart';

/// 单条消息外框：沿用 flutter_chat_ui 的 [ChatMessage]（动画 / 内边距 /
/// 分组 / 点击手势全部保留），另外附加：
/// - 时间戳：**气泡外**下方灰字常显，与气泡同侧对齐。此前内嵌在气泡顶部、
///   默认透明并靠悬停淡入；手机端点按虽然接了 `GestureDetector`，但点按多半
///   落在气泡内的富文本上被其手势吃掉，实际永远看不到；
/// - `leadingWidget` / `trailingWidget` 展示双方头像：对方在气泡左、自己在右；
/// - `headerWidget` 在消息间隔超过 [kChatTimeDividerGap] 时插入居中时间条。
class _ChatMessageRow extends StatelessWidget {
  final Message message;
  final int index;
  final Animation<double> animation;
  final bool? isRemoved;
  final MessageGroupStatus? groupStatus;

  /// 对方消息的头像；自己的消息为 null（不显示）。
  final Widget? avatar;

  /// 是否在消息上方插入时间分隔条（见 [_ChatPageState._showTimeDivider]）。
  final bool showTimeDivider;

  /// 是否在此消息上方插入「以下为新消息」分隔条（进入会话时的未读边界）。
  final bool showUnreadDivider;

  /// 是否为自己发送（决定时间戳与气泡的左右对齐）。
  final bool isSentByMe;

  final Widget child;

  const _ChatMessageRow({
    required this.message,
    required this.index,
    required this.animation,
    required this.isSentByMe,
    required this.child,
    this.isRemoved,
    this.groupStatus,
    this.avatar,
    this.showTimeDivider = false,
    this.showUnreadDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final time = message.resolvedTime;
    return ChatMessage(
      message: message,
      index: index,
      animation: animation,
      isRemoved: isRemoved,
      groupStatus: groupStatus,
      // 对方头像在气泡左侧、自己的头像在右侧 —— ChatMessage 的 Row 依次摆放
      // leadingWidget / trailingWidget，正好让两侧头像对称。
      leadingWidget: isSentByMe ? null : avatar,
      trailingWidget: isSentByMe ? avatar : null,
      headerWidget: showUnreadDivider || (showTimeDivider && time != null)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showUnreadDivider) const _UnreadDivider(),
                if (showTimeDivider && time != null) _TimeDivider(time: time),
              ],
            )
          : null,
      // 气泡下方不再常显灰字时间戳（观感差）。跨段的时间信息仍由 headerWidget
      // 的居中时间条承载。
      child: child,
    );
  }
}

/// 消息列表中的居中时间分隔条（相邻消息间隔超过 [kChatTimeDividerGap] 时）。
class _TimeDivider extends StatelessWidget {
  final DateTime time;

  const _TimeDivider({required this.time});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _fmtDividerTime(time),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 「以下为新消息」分隔条。
///
/// 未读数在 `_ChatPageState.initState` 里、**标记已读之前**取，之后不再变
/// （否则自己一进会话就归零了）。
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    final line = color.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Divider(color: line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              '以下为新消息',
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
          Expanded(child: Divider(color: line)),
        ],
      ),
    );
  }
}

/// 搜索结果行：发送方 + 时间 + 命中关键词高亮的正文片段。
///
/// 正文取 [_ChatPageState._searchableText]，与搜索时的判定同一份文本 ——
/// 否则会出现「搜到了但显示空白行」（卡片类消息的正文在 metadata 里）。
class _SearchHitTile extends StatelessWidget {
  const _SearchHitTile({
    required this.message,
    required this.query,
    required this.isMine,
    required this.onTap,
  });

  final Message message;
  final String query;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _ChatPageState._searchableText(message);
    final createdAt = message.createdAt?.toLocal();
    final time = createdAt == null ? '' : _fmtDividerTime(createdAt);
    final who = isMine ? '我' : '对方';
    return ListTile(
      dense: true,
      onTap: onTap,
      title: _highlighted(context, text),
      subtitle: Text(
        time.isEmpty ? who : '$who · $time',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  /// 命中片段高亮（大小写不敏感，只高亮第一处）。
  Widget _highlighted(BuildContext context, String text) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    if (text.isEmpty) {
      return Text(
        '（无文本内容）',
        style: base,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    final at = query.isEmpty ? -1 : text.toLowerCase().indexOf(query);
    if (at < 0) {
      return Text(text, style: base, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final end = at + query.length;
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
