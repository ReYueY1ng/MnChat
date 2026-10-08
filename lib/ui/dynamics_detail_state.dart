part of 'dynamics_detail_page.dart';

/// 单条评论的更多操作（对齐 dynamics_detailsview.lua:699-780 Render_hnit 的
/// 菜单项，并按需求把「点赞」也收进菜单）。
enum _CommentAction { like, unlike, top, untop, reply, delete }

/// 单条回复的更多操作（对齐 dynamics_frame_replyview.lua:496-530
/// Render_CommentReqhnit）。
enum _ReplyAction { like, unlike, delete }

/// 本人动态的 AppBar 管理菜单项。
enum _PostAction { delete, top, auth }

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
        // 动态来源的按钮组（个人中心 / 加好友 / 赠送 / 关注）。
        origin: PlayerCardOrigin.dynamics,
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

  // ── 评论 / 回复互动的本地乐观态 ─────────────────────────────────────
  // 服务端评论条目不带「我是否点过赞」标志（cai 是总数），故本地按条目键
  // 记一份点击态与增量，失败回滚；重载评论后归零。
  /// 我已点赞的评论条目键（[_commentKey]）。
  final Set<String> _likedCommentKeys = {};
  /// 我已点赞的回复 rep_id。
  final Set<String> _likedReplyIds = {};
  /// 评论点赞数增量（乐观更新，失败回滚）。
  final Map<String, int> _commentLikeDelta = {};
  /// 回复点赞数增量（乐观更新，失败回滚）。
  final Map<String, int> _replyLikeDelta = {};
  /// 当前置顶评论的条目键；null = 无置顶。
  /// 对齐 detailsctrl.lua:1029-1035 `details.top_comment`。
  String? _topCommentKey;
  /// 本人动态是否已置顶（详情接口不下发该标志，先按本地态翻转）。
  bool _postTop = false;

  /// 作者资料兜底（消息中心 / 通知页进来的动态往往只有 uin）。
  String? _authorName;
  String? _authorAvatar;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final injected = widget.client;
    if (injected != null) {
      _client = injected;
    } else {
      final auth = ref.read(chatServiceProvider).auth;
      if (auth == null) return;
      _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    }
    _likeCount = widget.post.likeCount;
    unawaited(_loadAuthorIfMissing());
    _loadComments(reset: true);
  }

  /// 按 uin 补齐作者昵称/头像（服务端对消息中心 / 通知页进入的动态常常只下发
  /// uin，卡片就会只剩一串数字且没有头像）。失败保持原样，绝不抛。
  Future<void> _loadAuthorIfMissing() async {
    final post = widget.post;
    final hasName = post.nickname?.isNotEmpty ?? false;
    final hasAvatar = post.avatar?.isNotEmpty ?? false;
    if (hasName && hasAvatar) return;
    try {
      final auth = ref.read(chatServiceProvider).auth;
      if (auth == null) return;
      final profile = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
      final list = await profile.getProfileBatch3([post.uin]);
      final heads = await profile.getPersonCenterHeadInfos([post.uin]);
      if (!mounted) return;
      final p = list.isNotEmpty ? list.first : null;
      final head = heads[post.uin];
      setState(() {
        if (!hasName && (p?.nickname.isNotEmpty ?? false)) {
          _authorName = p!.nickname;
        }
        if (!hasAvatar) {
          // 与好友资料同规则：DIY 自定义头像优先，其次资料网络头像。
          final fallback = PlayerProfile.resolveRoleHeadFallback(
            headType: head?.type,
            headId: head?.id,
            skinId: p?.headSkinId,
            model: p?.headModel,
          );
          _authorAvatar = head?.diyUrl ??
              (PlayerProfile.roleHeadHasLocalIcon(fallback)
                  ? null
                  : p?.avatarUrl);
        }
      });
    } catch (_) {
      // 补齐失败：保持原样（昵称回退 uin、头像首字）
    }
  }

  /// 本人 uin（评论置顶/删除与 AppBar 管理菜单按它判定）。
  int get _myUin => ref.read(myUinProvider);

  /// 是否本人动态（对齐 detailsview.lua:706-707 `uin == myUin`）。
  bool get _isMinePost => widget.post.uin == _myUin;

  /// 评论条目键：用定位参数组合（uin 会重复，不能单用 uin）。
  String _commentKey(DynamicsComment c) =>
      '${c.pidUin}_${c.pidCt}_${c.uin}_${c.opUin}_${c.lastTime}';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 确认弹窗（删除类操作的二次确认）。
  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// 写内容的通用输入弹窗：返回 trim 后的文本，取消/空 → null。
  Future<String?> _promptText({required String title, String? hint}) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint ?? '说点什么…'),
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
    if (content == null || content.isEmpty) return null;
    return content;
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

  /// 点赞/取消动态（`like_posting`；取消时带 `unprize=1`，对齐
  /// dynamicsdatamanager.lua:1531-1557 ReqPrise）。
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
      await client.likePosting(widget.post.pid, unpraise: !like);
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

  // ── 评论（一级）────────────────────────────────────────────────────

  /// 写评论：弹对话框 → addComment（act=add_comment，对齐
  /// dynamicsdatamanager.lua:1287-1330 AddComment）→ 刷新。
  Future<void> _writeComment() async {
    final client = _client;
    if (client == null) return;
    final content = await _promptText(title: '写评论');
    if (content == null) return;
    try {
      final ack = await client.addComment(widget.post.pid, content);
      if (!mounted) return;
      if (ack.ok) {
        _toast('评论已发布');
        _loadComments(reset: true);
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '发布失败');
      }
    } catch (e) {
      _toast('发布失败: $e');
    }
  }

  /// 评论更多操作菜单项（可见性对齐 dynamics_detailsview.lua:731-768：
  /// 置顶仅动态作者；删除在「未被置顶」且（评论是我发的 或 动态是我发的）时出现）。
  List<PopupMenuEntry<_CommentAction>> _commentMenuItems(DynamicsComment c) {
    final key = _commentKey(c);
    final pinned = _topCommentKey == key;
    final liked = _likedCommentKeys.contains(key);
    final canDelete = !pinned && (c.uin == _myUin || _isMinePost);
    return <PopupMenuEntry<_CommentAction>>[
      PopupMenuItem<_CommentAction>(
        value: liked ? _CommentAction.unlike : _CommentAction.like,
        child: Text(liked ? '取消点赞' : '点赞'),
      ),
      if (_isMinePost)
        PopupMenuItem<_CommentAction>(
          value: pinned ? _CommentAction.untop : _CommentAction.top,
          child: Text(pinned ? '取消置顶' : '置顶'),
        ),
      const PopupMenuItem<_CommentAction>(
        value: _CommentAction.reply,
        child: Text('回复'),
      ),
      if (canDelete)
        const PopupMenuItem<_CommentAction>(
          value: _CommentAction.delete,
          child: Text('删除评论'),
        ),
    ];
  }

  /// 长按评论 → 在指针处弹同一个菜单。
  Future<void> _showCommentMenu(int index, Offset globalPosition) async {
    if (index >= _comments.length) return;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final picked = await showMenu<_CommentAction>(
      context: context,
      position: position,
      items: _commentMenuItems(_comments[index]),
    );
    if (picked != null && mounted) {
      await _handleCommentAction(index, picked);
    }
  }

  Future<void> _handleCommentAction(int index, _CommentAction action) async {
    if (index >= _comments.length) return;
    switch (action) {
      case _CommentAction.like:
        await _toggleCommentLike(index, true);
      case _CommentAction.unlike:
        await _toggleCommentLike(index, false);
      case _CommentAction.top:
        await _setCommentTop(index, true);
      case _CommentAction.untop:
        await _setCommentTop(index, false);
      case _CommentAction.reply:
        await _writeReply(_comments[index]);
      case _CommentAction.delete:
        await _deleteComment(index);
    }
  }

  /// 评论点赞 / 取消（act=prize_comment；对齐
  /// dynamicsdatamanager.lua:3453-3476 ReqCommentPrise）。
  Future<void> _toggleCommentLike(int index, bool prize) async {
    final client = _client;
    if (client == null || index >= _comments.length) return;
    final c = _comments[index];
    final key = _commentKey(c);
    if (prize == _likedCommentKeys.contains(key)) return;
    _applyCommentLike(key, prize);
    try {
      final ack = await client.prizeComment(c, prize: prize);
      if (!ack.ok) {
        _applyCommentLike(key, !prize);
        _toast(ack.message.isNotEmpty ? ack.message : '操作失败');
      }
    } catch (e) {
      _applyCommentLike(key, !prize);
      _toast('操作失败: $e');
    }
  }

  /// 本地应用一次评论点赞态（[on]=true 点赞）。
  void _applyCommentLike(String key, bool on) {
    if (!mounted) return;
    setState(() {
      if (on) {
        _likedCommentKeys.add(key);
        _commentLikeDelta[key] = (_commentLikeDelta[key] ?? 0) + 1;
      } else {
        _likedCommentKeys.remove(key);
        _commentLikeDelta[key] = (_commentLikeDelta[key] ?? 0) - 1;
      }
    });
  }

  /// 评论置顶 / 取消置顶（act=set_top_comment / delete_top_comment；
  /// 对齐 dynamicsdatamanager.lua:3477-3510 ReqCommentSetTop / ReqCommentDelTop）。
  Future<void> _setCommentTop(int index, bool top) async {
    final client = _client;
    if (client == null || index >= _comments.length) return;
    final c = _comments[index];
    final key = _commentKey(c);
    try {
      final ack = top
          ? await client.setTopComment(c)
          : await client.deleteTopComment(widget.post.pid);
      if (!mounted) return;
      if (ack.ok) {
        setState(() => _topCommentKey = top ? key : null);
        _toast(top ? '已置顶' : '已取消置顶');
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '操作失败');
      }
    } catch (e) {
      _toast('操作失败: $e');
    }
  }

  /// 删除评论（act=delete_single_comment；对齐
  /// dynamicsdatamanager.lua:1335-1362 DeleteComment 的 type==0 分支）。
  Future<void> _deleteComment(int index) async {
    final client = _client;
    if (client == null || index >= _comments.length) return;
    final c = _comments[index];
    if (!await _confirm('删除评论', '确定删除这条评论吗？')) return;
    try {
      final ack = await client.deleteComment(widget.post.pid, c);
      if (!mounted) return;
      if (ack.ok) {
        _toast('已删除');
        _loadComments(reset: true);
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '删除失败');
      }
    } catch (e) {
      _toast('删除失败: $e');
    }
  }

  // ── 回复（二级评论）────────────────────────────────────────────────

  /// 发表回复（act=add_comment_rep；对齐
  /// dynamicsdatamanager.lua:4935-4985 AddCommentReply）。
  ///
  /// [opUin] 为被回复者；缺省回落到父评论的 [DynamicsComment.replyTargetUin]。
  Future<void> _writeReply(DynamicsComment parent, {int? opUin}) async {
    final client = _client;
    if (client == null) return;
    final target = opUin ?? parent.replyTargetUin;
    final rawName = parent.nickname ?? '';
    final name = plainNickname(rawName).isNotEmpty
        ? plainNickname(rawName)
        : '${parent.uin}';
    final content = await _promptText(title: '回复 $name', hint: '回复 @$name');
    if (content == null) return;
    try {
      final ack = await client.addCommentReply(
        parent,
        opUin: target,
        content: content,
      );
      if (!mounted) return;
      if (ack.ok) {
        _toast('回复已发布');
        await _reloadReplies(parent);
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '发布失败');
      }
    } catch (e) {
      _toast('发布失败: $e');
    }
  }

  /// 重新拉取某条父评论的回复并展开（发/删回复后刷新）。
  Future<void> _reloadReplies(DynamicsComment parent) async {
    final client = _client;
    if (client == null) return;
    final key = _commentKey(parent);
    final index = _comments.indexWhere((c) => _commentKey(c) == key);
    if (index < 0) return;
    if (mounted) {
      setState(() {
        _replyLoading.add(index);
        _expandedReplies.add(index);
      });
    }
    try {
      final reps = await client.fetchCommentReplies(parent);
      if (!mounted) return;
      setState(() {
        _replies[index] = reps;
        _replyLoading.remove(index);
      });
    } catch (e) {
      if (mounted) setState(() => _replyLoading.remove(index));
    }
  }

  /// 回复更多操作菜单项（可见性对齐 dynamics_frame_replyview.lua:496-522：
  /// 删除在「回复是我发的 或 动态是我发的」时出现）。
  List<PopupMenuEntry<_ReplyAction>> _replyMenuItems(DynamicsComment reply) {
    final liked = _likedReplyIds.contains(reply.repId);
    final canDelete = reply.uin == _myUin || _isMinePost;
    return <PopupMenuEntry<_ReplyAction>>[
      PopupMenuItem<_ReplyAction>(
        value: liked ? _ReplyAction.unlike : _ReplyAction.like,
        child: Text(liked ? '取消点赞' : '点赞'),
      ),
      if (canDelete)
        const PopupMenuItem<_ReplyAction>(
          value: _ReplyAction.delete,
          child: Text('删除回复'),
        ),
    ];
  }

  /// 长按回复 → 在指针处弹同一个菜单。
  Future<void> _showReplyMenu(
    DynamicsComment reply,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final picked = await showMenu<_ReplyAction>(
      context: context,
      position: position,
      items: _replyMenuItems(reply),
    );
    if (picked != null && mounted) {
      await _handleReplyAction(reply, picked);
    }
  }

  Future<void> _handleReplyAction(
    DynamicsComment reply,
    _ReplyAction action,
  ) async {
    switch (action) {
      case _ReplyAction.like:
        await _toggleReplyLike(reply, true);
      case _ReplyAction.unlike:
        await _toggleReplyLike(reply, false);
      case _ReplyAction.delete:
        await _deleteReply(reply);
    }
  }

  /// 回复点赞 / 取消（act=prize_comment_rep；对齐
  /// dynamicsdatamanager.lua:5086-5100 / 5215 Req_Prize_Comment_Reply）。
  Future<void> _toggleReplyLike(DynamicsComment reply, bool prize) async {
    final client = _client;
    if (client == null || reply.repId.isEmpty) return;
    if (prize == _likedReplyIds.contains(reply.repId)) return;
    _applyReplyLike(reply.repId, prize);
    try {
      final ack = await client.prizeCommentReply(reply.repId, prize: prize);
      if (!ack.ok) {
        _applyReplyLike(reply.repId, !prize);
        _toast(ack.message.isNotEmpty ? ack.message : '操作失败');
      }
    } catch (e) {
      _applyReplyLike(reply.repId, !prize);
      _toast('操作失败: $e');
    }
  }

  /// 本地应用一次回复点赞态（[on]=true 点赞）。
  void _applyReplyLike(String repId, bool on) {
    if (!mounted) return;
    setState(() {
      if (on) {
        _likedReplyIds.add(repId);
        _replyLikeDelta[repId] = (_replyLikeDelta[repId] ?? 0) + 1;
      } else {
        _likedReplyIds.remove(repId);
        _replyLikeDelta[repId] = (_replyLikeDelta[repId] ?? 0) - 1;
      }
    });
  }

  /// 删除回复：自己发的 → delete_player_comment_rep；否则（动态作者视角）
  /// → delete_comment_rep。对齐 dynamics_frame_deletecommentctrl.lua:155-180。
  Future<void> _deleteReply(DynamicsComment reply) async {
    final client = _client;
    if (client == null || reply.repId.isEmpty) return;
    if (!await _confirm('删除回复', '确定删除这条回复吗？')) return;
    try {
      final ack = reply.uin == _myUin
          ? await client.deletePlayerCommentReply(reply.repId)
          : await client.deleteCommentReply(reply.repId);
      if (!mounted) return;
      if (ack.ok) {
        _toast('已删除');
        await _reloadRepliesFor(reply);
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '删除失败');
      }
    } catch (e) {
      _toast('删除失败: $e');
    }
  }

  /// 按 rep_id 找到其父评论并刷新回复列表。
  Future<void> _reloadRepliesFor(DynamicsComment reply) async {
    for (final entry in _replies.entries) {
      if (entry.value.any((r) => r.repId == reply.repId) &&
          entry.key < _comments.length) {
        await _reloadReplies(_comments[entry.key]);
        return;
      }
    }
  }

  // ── 本人动态管理（AppBar overflow）─────────────────────────────────

  List<PopupMenuEntry<_PostAction>> _postMenuItems() =>
      <PopupMenuEntry<_PostAction>>[
        const PopupMenuItem<_PostAction>(
          value: _PostAction.delete,
          child: Text('删除动态'),
        ),
        PopupMenuItem<_PostAction>(
          value: _PostAction.top,
          child: Text(_postTop ? '取消置顶' : '置顶'),
        ),
        const PopupMenuItem<_PostAction>(
          value: _PostAction.auth,
          child: Text('改可见范围'),
        ),
      ];

  Future<void> _handlePostAction(_PostAction action) async {
    switch (action) {
      case _PostAction.delete:
        await _deletePost();
      case _PostAction.top:
        await _togglePostTop();
      case _PostAction.auth:
        await _changePostAuth();
    }
  }

  /// 删除动态（act=delete_posting；对齐 dynamicsdatamanager.lua:1470-1489）。
  Future<void> _deletePost() async {
    final client = _client;
    if (client == null) return;
    if (!await _confirm('删除动态', '删除后不可恢复，确定删除这条动态吗？')) return;
    try {
      final ack = await client.deletePosting(widget.post.pid);
      if (!mounted) return;
      if (ack.ok) {
        _toast('动态已删除');
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop(true);
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '删除失败');
      }
    } catch (e) {
      _toast('删除失败: $e');
    }
  }

  /// 置顶 / 取消置顶动态（act=set_top；对齐
  /// dynamicsdatamanager.lua:1491-1507 SetTop）。
  Future<void> _togglePostTop() async {
    final client = _client;
    if (client == null) return;
    final top = !_postTop;
    try {
      final ack = await client.setTop(widget.post.pid, top: top);
      if (!mounted) return;
      if (ack.ok) {
        setState(() => _postTop = top);
        _toast(top ? '已置顶' : '已取消置顶');
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '操作失败');
      }
    } catch (e) {
      _toast('操作失败: $e');
    }
  }

  /// 改可见范围（act=setPostingAuth&ptype=see；对齐
  /// dynamicsdatamanager.lua:1509-1529 SetPostingAuth 与 DynamicConstant.AUTH）。
  Future<void> _changePostAuth() async {
    final client = _client;
    if (client == null) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('改可见范围'),
        children: DynamicsAuth.labels.entries
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e.key),
                child: Text(e.value),
              ),
            )
            .toList(),
      ),
    );
    if (picked == null) return;
    try {
      final ack = await client.setPostingAuth(
        widget.post.pid,
        ptype: DynamicsAuth.ptypeSee,
        pauth: picked,
      );
      if (!mounted) return;
      if (ack.ok) {
        _toast('已改为「${DynamicsAuth.label(picked)}」');
      } else {
        _toast(ack.message.isNotEmpty ? ack.message : '操作失败');
      }
    } catch (e) {
      _toast('操作失败: $e');
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
          // 本人动态管理：仅 `post.uin == myUin` 时出现。
          if (_isMinePost)
            PopupMenuButton<_PostAction>(
              key: dynamicsPostMenuKey,
              tooltip: dynamicsPostMenuTooltip,
              icon: const Icon(Icons.more_vert),
              onSelected: (a) => unawaited(_handlePostAction(a)),
              itemBuilder: (_) => _postMenuItems(),
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
                    authorName: _authorName,
                    authorAvatar: _authorAvatar,
                    onAvatarTap: _showPlayerCard,
                    client: _client,
                    isMine: _isMinePost,
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
                    commentKey: _commentKey,
                    likedCommentKeys: _likedCommentKeys,
                    commentLikeDelta: _commentLikeDelta,
                    topCommentKey: _topCommentKey,
                    commentMenuItems: _commentMenuItems,
                    onCommentAction: _handleCommentAction,
                    onCommentMenu: _showCommentMenu,
                    replyMenuItems: _replyMenuItems,
                    onReplyAction: _handleReplyAction,
                    onReplyMenu: _showReplyMenu,
                    myUin: _myUin,
                    likedReplyIds: _likedReplyIds,
                    replyLikeDelta: _replyLikeDelta,
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
                        authorName: _authorName,
                        authorAvatar: _authorAvatar,
                        onAvatarTap: _showPlayerCard,
                        client: _client,
                        isMine: _isMinePost,
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
                        commentKey: _commentKey,
                        likedCommentKeys: _likedCommentKeys,
                        commentLikeDelta: _commentLikeDelta,
                        topCommentKey: _topCommentKey,
                        commentMenuItems: _commentMenuItems,
                        onCommentAction: _handleCommentAction,
                        onCommentMenu: _showCommentMenu,
                        replyMenuItems: _replyMenuItems,
                        onReplyAction: _handleReplyAction,
                        onReplyMenu: _showReplyMenu,
                        myUin: _myUin,
                        likedReplyIds: _likedReplyIds,
                        replyLikeDelta: _replyLikeDelta,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
