part of 'dynamics_detail_page.dart';

/// 左侧/顶部：动态全文。
class _PostPanel extends StatelessWidget {
  /// 要展示的动态；页面会先把作者资料（昵称 / 头像本体 / 头像框）补进去再传过来
  /// （消息中心 / 通知页进来的动态常常只有 uin）。
  final DynamicsPost post;

  /// 点头像 → 玩家卡片。
  final PlayerCardTap? onAvatarTap;

  /// 动态服务客户端；投票卡用它拉取投票信息 / 提交投票。
  final DynamicsClient? client;

  /// 动态作者是不是我（投票拉取失败时是否提示，对齐游戏 `bolMine`）。
  final bool isMine;

  const _PostPanel({required this.post, this.onAvatarTap, this.client,
    this.isMine = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 昵称 / 头像 / 头像本体 / 头像框都已由页面写进 [post]；这里只做最后降级：
    // 昵称空 → 迷你号。
    final name = (post.nickname?.isNotEmpty ?? false)
        ? post.nickname!
        : '${post.uin}';
    final avatar = post.avatar;
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
                        avatar,
                        post.headType,
                        post.headId,
                        post.headFrameId,
                        d.globalPosition,
                      ),
                child: AvatarView(
                  name: name,
                  avatarUrl: avatar,
                  radius: 22,
                  headType: post.headType,
                  headId: post.headId,
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
          // 全文（话题 `#名称` 可点，进该话题下的动态列表）
          Text.rich(
            TextSpan(
              children: buildRichSpans(
                post.content,
                context: context,
                onTopicTap: (id, label) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        DynamicsTopicPage(topicId: id, topicTitle: label),
                  ),
                ),
              ),
            ),
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
          // 投票卡（vote_id 非空即投票动态）
          if (post.voteId != null && post.voteId!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _VoteCard(post: post, client: client, isMine: isMine),
          ],
          if (post.isLottery) ...[const SizedBox(height: AppSpacing.sm), _LotteryInfo()],
        ],
      ),
    );
  }
}

/// 动态投票卡 —— 拉 `get_vote_info` 渲染标题 + 选项，选好后 `vote` 提交再刷新。
///
/// 对齐反编译 `dynamicsviewmanager.lua:221-380 UpdateVoteView`：
/// `mode`=0 单选 / 1 多选（`multi_mode`=1 才允许多选），选项来自
/// `vote_info.opt_static`，票数来自 `vote_info.opts[].vote_cnt`；提交走
/// `dynamicsdatamanager.lua:4617-4655 ReqGetVoteInfo` 同族接口 `vote`。
class _VoteCard extends StatefulWidget {
  final DynamicsPost post;
  final DynamicsClient? client;

  /// 动态作者是不是我（与游戏 `bolMine` 同义）。
  final bool isMine;

  const _VoteCard({required this.post, this.client, this.isMine = false});

  @override
  State<_VoteCard> createState() => _VoteCardState();
}

class _VoteCardState extends State<_VoteCard> {
  DynamicsVoteInfo? _info;
  bool _loading = true;
  bool _failed = false;
  bool _submitting = false;
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 是否多选（mode=1 且 multi_mode=1；其余按单选）。
  bool get _multi =>
      (_info?.mode ?? 0) == 1 && (_info?.multiMode ?? 0) == 1;

  Future<void> _load() async {
    final client = widget.client;
    final voteId = widget.post.voteId;
    if (client == null || voteId == null || voteId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = client != null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final info = await client.getVoteInfo(
        voteId,
        onMessage: widget.isMine && mounted
            ? (msg) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(msg)))
            : null,
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
        _failed = info == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// 点选项：单选替换、多选增删；不可选时不动。
  void _pickOption(int index) {
    setState(() {
      if (_multi) {
        if (!_picked.remove(index)) _picked.add(index);
      } else {
        _picked
          ..clear()
          ..add(index);
      }
    });
  }

  Future<void> _submit() async {
    final client = widget.client;
    final info = _info;
    if (client == null || info == null || _picked.isEmpty || _submitting) {
      return;
    }
    final opts = (_picked.toList()..sort()).join(',');
    setState(() => _submitting = true);
    try {
      final ack = await client.vote(
        voteId: info.voteId.isNotEmpty
            ? info.voteId
            : (widget.post.voteId ?? ''),
        opts: opts,
        pid: widget.post.pid,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (ack.ok) {
        _picked.clear();
        await _load(); // 刷新票数
      } else {
        _showTip(ack.message.isNotEmpty ? ack.message : '投票失败');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showTip('投票失败: $e');
    }
  }

  void _showTip(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: AppRadius.cardR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.how_to_vote_outlined,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  info == null || info.title.isEmpty ? '投票' : info.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (widget.client == null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '登录后可参与投票',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ] else if (_failed || info == null || info.options.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '投票信息加载失败',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _multi ? '可多选，选好后提交' : '单选，点选后提交',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...info.options.map((o) {
              final selected = _picked.contains(o.index);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: InkWell(
                  borderRadius: AppRadius.chipR,
                  onTap: () => _pickOption(o.index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.surface,
                      borderRadius: AppRadius.chipR,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.check_circle
                              : (_multi
                                    ? Icons.check_box_outline_blank
                                    : Icons.radio_button_unchecked),
                          size: 18,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            o.text.isEmpty ? '选项 ${o.index}' : o.text,
                          ),
                        ),
                        if (o.count > 0)
                          Text(
                            '${o.count}票',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed:
                    (_picked.isEmpty || _submitting) ? null : _submit,
                child: Text(_submitting ? '提交中…' : '投票'),
              ),
            ),
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
