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

  /// 点头像 → 玩家卡片。
  final PlayerCardTap? onAvatarTap;

  const _CommentTile({
    required this.comment,
    required this.replies,
    required this.expanded,
    required this.replyLoading,
    required this.onToggleReplies,
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
                      (r) => Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.reply, size: 12),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: buildRichSpans(
                                    '${r.nickname ?? r.uin}: ${r.content}',
                                    context: context,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.thumb_up_alt_outlined,
                size: 14,
                color: theme.colorScheme.outline,
              ),
              if (comment.likeCount > 0) ...[
                const SizedBox(width: 3),
                Text('${comment.likeCount}', style: theme.textTheme.labelSmall),
              ],
            ],
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
