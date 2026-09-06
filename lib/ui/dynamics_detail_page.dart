import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'widgets/avatar_view.dart';
import 'widgets/dynamics_card.dart' show dynamicsContentSpans;
import 'widgets/image_viewer.dart' show openImageViewer;

/// 动态详情页 —— 左侧动态全文，右侧评论区；窄屏上下堆叠。
class DynamicsDetailPage extends ConsumerStatefulWidget {
  final DynamicsPost post;

  const DynamicsDetailPage({super.key, required this.post});

  @override
  ConsumerState<DynamicsDetailPage> createState() => _DynamicsDetailPageState();
}

class _DynamicsDetailPageState extends ConsumerState<DynamicsDetailPage> {
  DynamicsClient? _client;
  List<DynamicsComment> _comments = [];
  bool _loadingComments = true;
  bool _latest = false;
  bool _liked = false;
  int _likeCount = 0;
  // 评论回复展开：commentUin → replies。
  final Map<int, List<DynamicsComment>> _replies = {};
  final Set<int> _expandedReplies = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) return;
    _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    _likeCount = widget.post.likeCount;
    _loadComments();
  }

  Future<void> _loadComments() async {
    final client = _client;
    if (client == null) return;
    setState(() => _loadingComments = true);
    try {
      _comments = await client.fetchComments(widget.post.pid);
    } catch (e) {
      // 忽略：显示空态
    } finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  /// 点赞/取消。
  Future<void> _toggleLike() async {
    final client = _client;
    if (client == null) return;
    final like = !_liked;
    setState(() {
      _liked = like;
      _likeCount += like ? 1 : -1;
      if (_likeCount < 0) _likeCount = 0;
    });
    try {
      await client.likePosting(widget.post.pid);
    } catch (e) {
      // 失败回滚
      if (mounted) {
        setState(() {
          _liked = !like;
          _likeCount += like ? -1 : 1;
          if (_likeCount < 0) _likeCount = 0;
        });
      }
    }
  }

  /// 写评论：弹对话框 → addComment → 刷新。
  Future<void> _writeComment() async {
    final client = _client;
    if (client == null) return;
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写评论'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '说点什么…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('发布'),
          ),
        ],
      ),
    );
    if (content == null || content.isEmpty) return;
    try {
      await client.addComment(widget.post.pid, content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('评论已发布')));
        _loadComments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发布失败: $e')));
      }
    }
  }

  /// 展开/收起一条评论的回复。
  Future<void> _toggleReplies(int commentUin) async {
    final client = _client;
    if (client == null) return;
    if (_expandedReplies.contains(commentUin)) {
      setState(() => _expandedReplies.remove(commentUin));
      return;
    }
    setState(() => _expandedReplies.add(commentUin));
    if (!_replies.containsKey(commentUin)) {
      try {
        final reps = await client.fetchCommentReplies(widget.post.pid, commentUin);
        if (mounted) setState(() => _replies[commentUin] = reps);
      } catch (_) {
        if (mounted) setState(() => _replies[commentUin] = []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        actions: [
          IconButton(
            onPressed: _toggleLike,
            icon: Icon(_liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                color: _liked ? Theme.of(context).colorScheme.primary : null),
          ),
          if (_likeCount > 0)
            Center(child: Text('$_likeCount', style: const TextStyle(fontSize: 13))),
          IconButton(icon: const Icon(Icons.mode_comment_outlined), onPressed: _writeComment),
          IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
          const SizedBox(width: 4),
        ],
      ),
      body: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _PostPanel(post: widget.post)),
                const VerticalDivider(width: 1),
                Expanded(child: _CommentPanel(
                  comments: _comments,
                  loading: _loadingComments,
                  latest: _latest,
                  onToggle: (v) => setState(() => _latest = v),
                  onWrite: _writeComment,
                  replies: _replies,
                  expandedReplies: _expandedReplies,
                  onToggleReplies: _toggleReplies,
                )),
              ],
            )
          : ListView(
              children: [
                _PostPanel(post: widget.post),
                const Divider(),
                _CommentPanel(
                  comments: _comments,
                  loading: _loadingComments,
                  latest: _latest,
                  onToggle: (v) => setState(() => _latest = v),
                  onWrite: _writeComment,
                  replies: _replies,
                  expandedReplies: _expandedReplies,
                  onToggleReplies: _toggleReplies,
                ),
              ],
            ),
    );
  }
}

/// 左侧/顶部：动态全文。
class _PostPanel extends StatelessWidget {
  final DynamicsPost post;

  const _PostPanel({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (post.nickname ?? '${post.uin}').isEmpty ? '${post.uin}' : (post.nickname ?? '${post.uin}');
    final meta = [
      if (post.createTime > 0) _relative(post.createTime),
      'IP ${post.location.isNotEmpty ? post.location : post.city}',
    ].join('  ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者
          Row(
            children: [
              AvatarView(name: name, avatarUrl: post.avatar, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 3),
                      _VBadge(),
                    ]),
                    Text(meta, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 全文
          Text.rich(
            TextSpan(children: dynamicsContentSpans(post.content, context)),
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          // 图片（整列自然比例）
          if (post.pics.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...post.pics.asMap().entries.map((e) {
              final idx = e.key;
              final p = e.value;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: () => openImageViewer(context, post.pics.map((x) => x.url).toList(), idx),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: p.aspect > 0 ? p.aspect.clamp(0.5, 2.5) : 1.5,
                      child: Image.network(p.url, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          loadingBuilder: (c, w, l) => l == null ? w : const SizedBox.shrink()),
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
              child: Row(children: [
                Icon(Icons.map_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(post.linkName!, style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          if (post.isLottery) ...[
            const SizedBox(height: 8),
            _LotteryInfo(),
          ],
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
      child: Row(children: [
        Icon(Icons.card_giftcard, color: theme.colorScheme.onTertiaryContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text('抽奖详情（进行中）', style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
        ),
      ]),
    );
  }
}

/// 右侧/底部：评论区。
class _CommentPanel extends StatelessWidget {
  final List<DynamicsComment> comments;
  final bool loading;
  final bool latest;
  final ValueChanged<bool> onToggle;
  final VoidCallback onWrite;
  final Map<int, List<DynamicsComment>> replies;
  final Set<int> expandedReplies;
  final void Function(int) onToggleReplies;

  const _CommentPanel({
    required this.comments,
    required this.loading,
    required this.latest,
    required this.onToggle,
    required this.onWrite,
    required this.replies,
    required this.expandedReplies,
    required this.onToggleReplies,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // tab：共N条评论 | 默认/最新
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Text('共${comments.length}条评论', style: theme.textTheme.bodySmall),
            const Spacer(),
            InkWell(
              onTap: () => onToggle(false),
              child: Text('默认', style: TextStyle(color: latest ? theme.colorScheme.outline : theme.colorScheme.primary)),
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: () => onToggle(true),
              child: Text('最新', style: TextStyle(color: latest ? theme.colorScheme.primary : theme.colorScheme.outline)),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : comments.isEmpty
                  ? const Center(child: Text('暂无评论'))
                  : ListView.separated(
                      itemCount: comments.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _CommentTile(
                        comment: comments[i],
                        replies: replies[comments[i].uin],
                        expanded: expandedReplies.contains(comments[i].uin),
                        onToggleReplies: () => onToggleReplies(comments[i].uin),
                      ),
                    ),
        ),
        // 写评论
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GestureDetector(onTap: onWrite, child: const _WriteCommentBar()),
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
  final VoidCallback onToggleReplies;

  const _CommentTile({required this.comment, this.replies, required this.expanded, required this.onToggleReplies});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (comment.nickname ?? '${comment.uin}').isEmpty ? '${comment.uin}' : (comment.nickname ?? '${comment.uin}');
    final meta = [
      if (comment.createTime > 0) _relative(comment.createTime),
      'IP ${comment.location.isNotEmpty ? comment.location : comment.uin}',
    ].join('  ');
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarView(name: name, avatarUrl: comment.avatar, radius: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
                Text(meta, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: dynamicsContentSpans(comment.content, context)),
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
                if (comment.replyCount > 0)
                  InkWell(
                    onTap: onToggleReplies,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(expanded ? '收起回复' : '共${comment.replyCount}条回复',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                    ),
                  ),
                if (expanded && replies != null) ...[
                  const SizedBox(height: 4),
                  ...replies!.map((r) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.reply, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: dynamicsContentSpans(
                                    '${r.nickname ?? r.uin}: ${r.content}', context)),
                                style: const TextStyle(fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(children: [
            Icon(Icons.thumb_up_alt_outlined, size: 14, color: theme.colorScheme.outline),
            if (comment.likeCount > 0) ...[
              const SizedBox(width: 3),
              Text('${comment.likeCount}', style: theme.textTheme.labelSmall),
            ],
          ]),
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
      child: Row(children: [
        Icon(Icons.edit_outlined, size: 18, color: theme.colorScheme.onSecondaryContainer),
        const SizedBox(width: 8),
        Text('点击写评论', style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
      ]),
    );
  }
}

class _VBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.tertiary]),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text('V3', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}

String _relative(int ts) {
  if (ts <= 0) return '';
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
  return '${(diff.inDays / 365).floor()}年前';
}
