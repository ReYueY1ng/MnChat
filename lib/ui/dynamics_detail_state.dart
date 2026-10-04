part of 'dynamics_detail_page.dart';

class _DynamicsDetailPageState extends ConsumerState<DynamicsDetailPage> {
  /// 点头像 → 玩家卡片（与会话页同一个浮窗）。
  void _showPlayerCard(
    int uin,
    String name,
    String? avatar,
    int? headFrameId,
    Offset position,
  ) {
    unawaited(
      showSessionPlayerInfoPopup(
        context,
        ref,
        uin: uin,
        name: name,
        anchor: Rect.fromLTWH(position.dx, position.dy, 1, 1),
        avatarUrl: avatar,
        headFrameId: headFrameId,
        showActions: uin != ref.read(myUinProvider),
      ),
    );
  }

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
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: isLandscapeWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _PostPanel(
                    post: widget.post,
                    onAvatarTap: _showPlayerCard,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _CommentPanel(
                    onAvatarTap: _showPlayerCard,
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
                      _PostPanel(
                        post: widget.post,
                        onAvatarTap: _showPlayerCard,
                      ),
                      const Divider(),
                      _CommentPanel(
                        onAvatarTap: _showPlayerCard,
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
