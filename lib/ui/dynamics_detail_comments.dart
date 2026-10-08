part of 'dynamics_detail_page.dart';

/// 右侧/底部：评论区。
class _CommentPanel extends StatelessWidget {
  /// 是否占满剩余高度（横屏双栏）。false=内联随页面滚动（竖屏单列）。
  final bool fill;
  final List<DynamicsComment> comments;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final bool latest;
  final ValueChanged<bool> onToggle;
  final VoidCallback onLoadMore;
  final VoidCallback onWrite;

  /// 评论下标 → 回复列表 / 正在加载回复的评论下标 / 已展开的评论下标。
  final Map<int, List<DynamicsComment>> replies;
  final Set<int> replyLoading;
  final Set<int> expandedReplies;
  final void Function(int) onToggleReplies;

  /// 评论条目键（定位参数组合）、我已点赞的评论、评论点赞增量、置顶评论键。
  final String Function(DynamicsComment) commentKey;
  final Set<String> likedCommentKeys;
  final Map<String, int> commentLikeDelta;
  final String? topCommentKey;

  /// 评论菜单：条目构造 / 选中回调 / 长按弹菜单。
  final List<PopupMenuEntry<_CommentAction>> Function(DynamicsComment)
  commentMenuItems;
  final void Function(int index, _CommentAction action) onCommentAction;
  final void Function(int index, Offset globalPosition) onCommentMenu;

  /// 回复菜单：条目构造 / 选中回调 / 长按弹菜单。
  final List<PopupMenuEntry<_ReplyAction>> Function(DynamicsComment)
  replyMenuItems;
  final void Function(DynamicsComment reply, _ReplyAction action) onReplyAction;
  final void Function(DynamicsComment reply, Offset globalPosition) onReplyMenu;

  /// 本人 uin（回复菜单按作者判定显示）。
  final int myUin;
  final Set<String> likedReplyIds;
  final Map<String, int> replyLikeDelta;

  /// 点头像 → 玩家卡片（透传给每条评论）。
  final PlayerCardTap? onAvatarTap;

  const _CommentPanel({
    required this.fill,
    required this.comments,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.latest,
    required this.onToggle,
    required this.onLoadMore,
    required this.onWrite,
    required this.replies,
    required this.replyLoading,
    required this.expandedReplies,
    required this.onToggleReplies,
    required this.commentKey,
    required this.likedCommentKeys,
    required this.commentLikeDelta,
    required this.topCommentKey,
    required this.commentMenuItems,
    required this.onCommentAction,
    required this.onCommentMenu,
    required this.replyMenuItems,
    required this.onReplyAction,
    required this.onReplyMenu,
    required this.myUin,
    required this.likedReplyIds,
    required this.replyLikeDelta,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = loading
        ? const Center(child: CircularProgressIndicator())
        : comments.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: Text('暂无评论')),
          )
        : ListView.separated(
            // fill=true 时占满父高自滚；fill=false 时内联不滚动
            // （由外层页面 ListView 统一滚动）
            shrinkWrap: !fill,
            physics: fill ? null : const NeverScrollableScrollPhysics(),
            itemCount:
                comments.length + ((hasMore && !fill) ? 1 : 0), // 内联模式末尾加"加载更多"
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i >= comments.length) {
                // 加载更多按钮（fill 模式外层监听滚动自动加载，不显示按钮）
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Center(
                    child: loadingMore
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton.icon(
                            onPressed: onLoadMore,
                            icon: const Icon(Icons.expand_more),
                            label: const Text('加载更多评论'),
                          ),
                  ),
                );
              }
              return _CommentTile(
                comment: comments[i],
                replies: replies[i],
                expanded: expandedReplies.contains(i),
                replyLoading: replyLoading.contains(i),
                onToggleReplies: () => onToggleReplies(i),
                // 行内点赞按钮与菜单项走同一个 action（本人已赞则取消）。
                onToggleLike: () {
                  final k = commentKey(comments[i]);
                  onCommentAction(
                    i,
                    likedCommentKeys.contains(k)
                        ? _CommentAction.unlike
                        : _CommentAction.like,
                  );
                },
                liked: likedCommentKeys.contains(commentKey(comments[i])),
                likeDelta: commentLikeDelta[commentKey(comments[i])] ?? 0,
                pinned: topCommentKey != null &&
                    topCommentKey == commentKey(comments[i]),
                menuItems: () => commentMenuItems(comments[i]),
                onAction: (a) => onCommentAction(i, a),
                onLongPressMenu: (pos) => onCommentMenu(i, pos),
                replyMenuItems: replyMenuItems,
                onReplyAction: onReplyAction,
                onReplyMenu: onReplyMenu,
                myUin: myUin,
                likedReplyIds: likedReplyIds,
                replyLikeDelta: replyLikeDelta,
                onAvatarTap: onAvatarTap,
              );
            },
          );
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        // tab：共N条评论 | 默认/最新
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          child: Row(
            children: [
              Text('共${comments.length}条评论', style: theme.textTheme.bodySmall),
              const Spacer(),
              InkWell(
                onTap: () => onToggle(false),
                child: Text(
                  '默认',
                  style: TextStyle(
                    color: latest
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              InkWell(
                onTap: () => onToggle(true),
                child: Text(
                  '最新',
                  style: TextStyle(
                    color: latest
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // fill 模式：监听滚动到底自动加载更多
        if (fill)
          Expanded(
            child: hasMore
                ? NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                        onLoadMore();
                      }
                      return false;
                    },
                    child: list,
                  )
                : list,
          )
        else
          list,
        // 写评论
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: GestureDetector(
              onTap: onWrite,
              child: const _WriteCommentBar(),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final DynamicsComment comment;
  final List<DynamicsComment>? replies;
  final bool expanded;
  final bool replyLoading;
  final VoidCallback onToggleReplies;

  /// 本人点赞态 / 点赞增量 / 是否置顶。
  final bool liked;
  final int likeDelta;
  final bool pinned;

  /// 直接点赞 / 取消点赞（对齐游戏评论行的 btn_like / btn_unlike）。
  final VoidCallback onToggleLike;

  final List<PopupMenuEntry<_CommentAction>> Function() menuItems;
  final void Function(_CommentAction) onAction;
  final void Function(Offset globalPosition) onLongPressMenu;

  final List<PopupMenuEntry<_ReplyAction>> Function(DynamicsComment)
  replyMenuItems;
  final void Function(DynamicsComment reply, _ReplyAction action) onReplyAction;
  final void Function(DynamicsComment reply, Offset globalPosition) onReplyMenu;
  final int myUin;
  final Set<String> likedReplyIds;
  final Map<String, int> replyLikeDelta;

  /// 点头像 → 玩家卡片。
  final PlayerCardTap? onAvatarTap;

  const _CommentTile({
    required this.comment,
    required this.replies,
    required this.expanded,
    required this.replyLoading,
    required this.onToggleReplies,
    required this.liked,
    required this.likeDelta,
    required this.pinned,
    required this.onToggleLike,
    required this.menuItems,
    required this.onAction,
    required this.onLongPressMenu,
    required this.replyMenuItems,
    required this.onReplyAction,
    required this.onReplyMenu,
    required this.myUin,
    required this.likedReplyIds,
    required this.replyLikeDelta,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (comment.nickname ?? '${comment.uin}').isEmpty
        ? '${comment.uin}'
        : (comment.nickname ?? '${comment.uin}');
    final meta = [
      if (comment.createTime > 0) _relative(comment.createTime),
      'IP ${comment.location.isNotEmpty ? comment.location : comment.uin}',
    ].join('  ');
    final likeCount = comment.likeCount + likeDelta;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTapUp: onAvatarTap == null
                ? null
                : (d) => onAvatarTap!(
                    comment.uin,
                    name,
                    comment.avatar,
                    comment.headFrameId,
                    d.globalPosition,
                  ),
            child: AvatarView(
              name: name,
              avatarUrl: comment.avatar,
              radius: 18,
              frameId: comment.headFrameId,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // 长按评论 → 与 overflow 同一个菜单
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (d) => onLongPressMenu(d.globalPosition),
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (pinned) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.push_pin,
                          size: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    meta,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text.rich(
                    TextSpan(
                      children: buildRichSpans(comment.content, context: context),
                    ),
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                  if (comment.replyCount > 0)
                    InkWell(
                      onTap: onToggleReplies,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          expanded ? '收起回复' : '共${comment.replyCount}条回复',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  if (replyLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (expanded && replies != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    if (replies!.isEmpty)
                      Text(
                        '暂无回复',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      )
                    else
                      ...replies!.map(
                        (r) => _ReplyRow(
                          reply: r,
                          liked: likedReplyIds.contains(r.repId),
                          likeDelta: replyLikeDelta[r.repId] ?? 0,
                          menuItems: () => replyMenuItems(r),
                          onAction: (a) => onReplyAction(r, a),
                          onLongPressMenu: (pos) => onReplyMenu(r, pos),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // 点赞（可点，对齐游戏评论行 btn_like=344 / btn_unlike=345）+ 更多操作菜单
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onToggleLike,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            liked
                                ? Icons.thumb_up_alt
                                : Icons.thumb_up_alt_outlined,
                            size: 14,
                            color: liked
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          if (likeCount > 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              '$likeCount',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // 行内「回复」（对齐游戏评论行 btn_reply=678），与菜单里的回复同一个 action。
                  InkWell(
                    onTap: () => onAction(_CommentAction.reply),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      child: Icon(Icons.reply, size: 14),
                    ),
                  ),
                ],
              ),
              PopupMenuButton<_CommentAction>(
                tooltip: dynamicsCommentMenuTooltip,
                icon: const Icon(Icons.more_horiz, size: 18),
                padding: EdgeInsets.zero,
                onSelected: onAction,
                itemBuilder: (_) => menuItems(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一条二级回复：长按 / overflow 菜单（点赞、删除）。
class _ReplyRow extends StatelessWidget {
  final DynamicsComment reply;
  final bool liked;
  final int likeDelta;
  final List<PopupMenuEntry<_ReplyAction>> Function() menuItems;
  final void Function(_ReplyAction action) onAction;
  final void Function(Offset globalPosition) onLongPressMenu;

  const _ReplyRow({
    required this.reply,
    required this.liked,
    required this.likeDelta,
    required this.menuItems,
    required this.onAction,
    required this.onLongPressMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final likeCount = reply.likeCount + likeDelta;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.reply, size: 12),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (d) => onLongPressMenu(d.globalPosition),
              child: Text.rich(
                TextSpan(
                  children: buildRichSpans(
                    '${reply.nickname ?? reply.uin}: ${reply.content}',
                    context: context,
                  ),
                ),
                style: const TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // 回复点赞（可点，对齐游戏回复行 btn_like / btn_unlike）。
          InkWell(
            onTap: () =>
                onAction(liked ? _ReplyAction.unlike : _ReplyAction.like),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                    size: 12,
                    color: liked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  if (likeCount > 0) ...[
                    const SizedBox(width: 2),
                    Text('$likeCount', style: theme.textTheme.labelSmall),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<_ReplyAction>(
            tooltip: dynamicsReplyMenuTooltip,
            icon: const Icon(Icons.more_horiz, size: 16),
            padding: EdgeInsets.zero,
            onSelected: onAction,
            itemBuilder: (_) => menuItems(),
          ),
        ],
      ),
    );
  }
}

class _WriteCommentBar extends StatelessWidget {
  const _WriteCommentBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_outlined,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '点击写评论',
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}
