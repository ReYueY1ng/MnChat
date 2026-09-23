import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart' show buildRichSpans, RichTextView;
import 'widgets/image_viewer.dart' show openImageViewer;
import '../core/services/image_disk_cache.dart';

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

  /// 分页状态：默认排序按 offset（page*20）；最新排序按 ct 游标。
  bool _hasMore = false;
  bool _loadingMore = false;
  int _nextOffset = 0;
  int _nextCt = 0;

  /// 请求序号：防重复切换/重复分页的旧响应覆盖。
  int _reqSeq = 0;

  bool _liked = false;
  int _likeCount = 0;
  // 评论回复展开：按评论在 _comments 中的下标（uin 会重复，不能用 uin 作 key）。
  final Map<int, List<DynamicsComment>> _replies = {};
  final Set<int> _expandedReplies = {};
  final Set<int> _replyLoading = {};

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
    _loadComments(reset: true);
  }

  /// 加载评论。默认排序 offset 翻页（每页 20）；最新排序 ct 游标。
  Future<void> _loadComments({bool reset = false}) async {
    final client = _client;
    if (client == null) return;
    final seq = ++_reqSeq;
    if (reset) {
      setState(() {
        _loadingComments = true;
        _comments = [];
        _nextOffset = 0;
        _nextCt = 0;
        _hasMore = false;
        _replies.clear();
        _expandedReplies.clear();
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = await client.fetchComments(
        widget.post.pid,
        latest: _latest,
        offset: _nextOffset,
        ct: _nextCt,
      );
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _comments = reset ? page : [..._comments, ...page];
        // 默认排序：offset 累加；最新排序：ct 用本页最后一条 last_time
        _nextOffset = _comments.length;
        _hasMore = page.isNotEmpty;
        if (page.isNotEmpty) {
          _nextCt = page.last.lastTime;
        }
      });
    } catch (e) {
      // 忽略：显示已加载部分
    } finally {
      if (mounted && seq == _reqSeq) {
        setState(() {
          _loadingComments = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// 切换 默认/最新 → 从头重载。
  void _switchSort(bool latest) {
    if (latest == _latest) return;
    setState(() => _latest = latest);
    _loadComments(reset: true);
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

  /// 分享到聊天：好友选择器 → sendDynamicsShare（DYNAMIC_NOTICE 卡片）。
  Future<void> _shareToChat() async {
    final service = ref.read(chatServiceProvider);
    final contacts =
        service.contacts.where((c) => (c.relation & 8) != 0).toList()..sort(
          (a, b) =>
              a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase()),
        );
    if (contacts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂无好友可分享')));
      }
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                '分享动态到…',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ...contacts.map(
              (c) => ListTile(
                leading: const Icon(Icons.person),
                title: Text(c.nickname.isNotEmpty ? c.nickname : '${c.uin}'),
                subtitle: Text('迷你号 ${c.uin}'),
                onTap: () => Navigator.pop(ctx, c.uin),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final pics = widget.post.pics.map((p) => p.url).toList();
      await service.sendDynamicsShare(
        picked,
        pid: widget.post.pid,
        content: widget.post.content,
        picList: pics,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已分享给 $picked')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享失败: $e')));
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('评论已发布')));
        _loadComments(reset: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发布失败: $e')));
      }
    }
  }

  /// 展开/收起一条评论的回复（按评论下标）。
  Future<void> _toggleReplies(int index) async {
    final client = _client;
    if (client == null || index >= _comments.length) return;
    if (_expandedReplies.contains(index)) {
      setState(() => _expandedReplies.remove(index));
      return;
    }
    final comment = _comments[index];
    setState(() {
      _expandedReplies.add(index);
      _replyLoading.add(index);
    });
    if (!_replies.containsKey(index)) {
      try {
        final reps = await client.fetchCommentReplies(comment);
        if (mounted) setState(() => _replies[index] = reps);
      } catch (_) {
        if (mounted) setState(() => _replies[index] = []);
      } finally {
        if (mounted) setState(() => _replyLoading.remove(index));
      }
    } else {
      setState(() => _replyLoading.remove(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 竖屏（手机/平板立放）一律单列堆叠；仅横屏且宽度足够才左右双栏。
    final isLandscapeWide =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        actions: [
          IconButton(
            onPressed: _toggleLike,
            icon: Icon(
              _liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
              color: _liked ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          if (_likeCount > 0)
            Center(
              child: Text('$_likeCount', style: const TextStyle(fontSize: 13)),
            ),
          IconButton(
            icon: const Icon(Icons.mode_comment_outlined),
            onPressed: _writeComment,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: '分享到聊天',
            onPressed: _shareToChat,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: isLandscapeWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PostPanel(post: widget.post)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _CommentPanel(
                    fill: true, // 双栏：占满高度，评论区内滚
                    comments: _comments,
                    loading: _loadingComments,
                    loadingMore: _loadingMore,
                    hasMore: _hasMore,
                    latest: _latest,
                    onToggle: _switchSort,
                    onLoadMore: () => _loadComments(reset: false),
                    onWrite: _writeComment,
                    replies: _replies,
                    replyLoading: _replyLoading,
                    expandedReplies: _expandedReplies,
                    onToggleReplies: _toggleReplies,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                // 竖屏单列：正文 + 评论区整页滚动（不嵌套有界滚动区）
                Expanded(
                  child: ListView(
                    children: [
                      _PostPanel(post: widget.post),
                      const Divider(),
                      _CommentPanel(
                        fill: false, // 内联：随页面滚动
                        comments: _comments,
                        loading: _loadingComments,
                        loadingMore: _loadingMore,
                        hasMore: _hasMore,
                        latest: _latest,
                        onToggle: _switchSort,
                        onLoadMore: () => _loadComments(reset: false),
                        onWrite: _writeComment,
                        replies: _replies,
                        replyLoading: _replyLoading,
                        expandedReplies: _expandedReplies,
                        onToggleReplies: _toggleReplies,
                      ),
                    ],
                  ),
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
    final name = (post.nickname ?? '${post.uin}').isEmpty
        ? '${post.uin}'
        : (post.nickname ?? '${post.uin}');
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
              AvatarView(
            name: name,
            avatarUrl: post.avatar,
            radius: 22,
            frameId: post.headFrameId,
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
                padding: const EdgeInsets.only(top: 4),
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
                  const SizedBox(width: 8),
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
          if (post.isLottery) ...[const SizedBox(height: 8), _LotteryInfo()],
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
          const SizedBox(width: 8),
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = loading
        ? const Center(child: CircularProgressIndicator())
        : comments.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(32),
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
              );
            },
          );
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        // tab：共N条评论 | 默认/最新
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              const SizedBox(width: 16),
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
            padding: const EdgeInsets.all(8),
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

  const _CommentTile({
    required this.comment,
    required this.replies,
    required this.expanded,
    required this.replyLoading,
    required this.onToggleReplies,
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
          AvatarView(
            name: name,
            avatarUrl: comment.avatar,
            radius: 18,
            frameId: comment.headFrameId,
          ),
          const SizedBox(width: 8),
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
                const SizedBox(height: 4),
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
                  const SizedBox(height: 4),
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
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.reply, size: 12),
                            const SizedBox(width: 4),
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
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
          Text(
            '点击写评论',
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
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
