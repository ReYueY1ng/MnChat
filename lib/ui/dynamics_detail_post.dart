part of 'dynamics_detail_page.dart';

/// 左侧/顶部：动态全文。
class _PostPanel extends StatelessWidget {
  final DynamicsPost post;

  /// 点头像 → 玩家卡片。
  final PlayerCardTap? onAvatarTap;

  const _PostPanel({required this.post, this.onAvatarTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (post.nickname ?? '${post.uin}').isEmpty
        ? '${post.uin}'
        : (post.nickname ?? '${post.uin}');
    final meta = [
      if (post.createTime > 0) _relative(post.createTime),
      'IP ${post.location.isNotEmpty ? post.location : post.city}',
    ].join('  ');
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者
          Row(
            children: [
              GestureDetector(
                onTapUp: onAvatarTap == null
                    ? null
                    : (d) => onAvatarTap!(
                        post.uin,
                        name,
                        post.avatar,
                        post.headFrameId,
                        d.globalPosition,
                      ),
                child: AvatarView(
                  name: name,
                  avatarUrl: post.avatar,
                  radius: 22,
                  frameId: post.headFrameId,
                ),
              ),
              const SizedBox(width: 10),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 全文
          Text.rich(
            TextSpan(children: buildRichSpans(post.content, context: context)),
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          // 图片（整列自然比例）
          if (post.pics.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...post.pics.asMap().entries.map((e) {
              final idx = e.key;
              final p = e.value;
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: GestureDetector(
                  onTap: () => openImageViewer(
                    context,
                    post.pics.map((x) => x.url).toList(),
                    idx,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: p.aspect > 0
                          ? p.aspect.clamp(0.5, 2.5)
                          : 1.5,
                      child: Image(image: CachedNetworkImageProvider(p.url),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        loadingBuilder: (c, w, l) =>
                            l == null ? w : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
          // 链接/作品卡
          if (post.linkName != null && post.linkName!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.map_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      post.linkName!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (post.isLottery) ...[const SizedBox(height: AppSpacing.sm), _LotteryInfo()],
        ],
      ),
    );
  }
}

/// 抽奖信息块（展示型）。
class _LotteryInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.card_giftcard,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '抽奖详情（进行中）',
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

String _relative(int ts) {
  if (ts <= 0) return '';
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(ts * 1000),
  );
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
  return '${(diff.inDays / 365).floor()}年前';
}
