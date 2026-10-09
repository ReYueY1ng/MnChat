import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/messages.dart';
import '../../core/services/dynamics.dart';
import '../../core/services/profile.dart' show PlayerProfile, ProfileClient;
import '../../state/providers.dart';
import '../dynamics_detail_page.dart';
import '../dynamics_topic_page.dart';
import '../theme/app_tokens.dart';
import 'avatar_view.dart';
import 'session_player_info_popup.dart';
import 'head_frame.dart';
import 'image_viewer.dart';
import 'rich_text_view.dart';
import '../../core/services/image_disk_cache.dart';

/// 批量补齐动态作者的头像展示（DIY → 角色头像本体 → 首字占位）。
///
/// 动态接口只在 `role_info_list` 里下发 DIY 自定义头像与头像框，**从不给角色
/// 头像本体** —— 没自定义头像的人到了卡片上就只剩网络头像或首字占位，而好友 /
/// 会话 / 访客列表用的是官方 `GetPlayerHeadPath`（`headinfosysmgr.lua:321-383`）
/// 那条规则。这里按同一条规则补一次。
///
/// 一次请求补整页（`fetchAvatarProfiles` 内部两个批量口，各按 50 个分片）；
/// 拉不到时原样返回（不会把已有头像清掉）。动态大厅与话题流共用。
Future<List<DynamicsPost>> enrichPostAvatars(
  WidgetRef ref,
  List<DynamicsPost> posts,
) async {
  if (posts.isEmpty) return posts;
  // 未登录 / 测试环境未注入认证时读 provider 会抛，直接不补（保持原样）。
  final ProfileClient? client;
  try {
    client = ref.read(profileClientProvider);
  } catch (_) {
    return posts;
  }
  if (client == null) return posts;
  final uins = <int>{
    for (final p in posts)
      if (p.uin > 0) p.uin,
  }.toList();
  if (uins.isEmpty) return posts;
  Map<int, PlayerProfile> profiles;
  try {
    profiles = await client.fetchAvatarProfiles(uins);
  } catch (_) {
    return posts;
  }
  return [
    for (final post in posts)
      if (profiles[post.uin] == null)
        post
      else
        _withAvatarDisplay(post, profiles[post.uin]!),
  ];
}

/// 单条动态的头像展示解析（见 [PlayerProfile.resolveAvatarDisplay]）。
DynamicsPost _withAvatarDisplay(DynamicsPost post, PlayerProfile p) {
  final display = PlayerProfile.resolveAvatarDisplay(
    profile: p,
    fallbackUrl: post.avatar,
  );
  return post.withAvatar(
    url: display.url,
    headType: display.headType,
    headId: display.headId,
    headFrameId: p.headFrameId ?? post.headFrameId,
  );
}

/// 动态卡片 —— 左上头像+徽标+昵称 / 相对时间·IP属地 / 内容(查看全文) /
/// 图片 / 视频·投票·抽奖标记 / 附加信息 / 右下操作区。
class DynamicsCard extends ConsumerStatefulWidget {
  final DynamicsPost post;

  /// 是否我的动态（我自己的不显示「关注」按钮）。
  final bool isMine;

  /// 动态服务客户端注入点（测试用）；为空时按 `chatServiceProvider.auth` 构建。
  final DynamicsClient? client;

  const DynamicsCard({
    super.key,
    required this.post,
    this.isMine = false,
    this.client,
  });

  @override
  ConsumerState<DynamicsCard> createState() => _DynamicsCardState();
}

class _DynamicsCardState extends ConsumerState<DynamicsCard> {
  /// 点赞态（服务端条目不带「我是否点过赞」标志，与详情页一样本地记）。
  bool _liked = false;
  late int _likeCount = widget.post.likeCount;
  late int _shareCount = widget.post.shareCount;
  bool _likeBusy = false;
  bool _followed = false;

  DynamicsPost get post => widget.post;
  bool get isMine => widget.isMine;

  /// 动态服务客户端（懒建并缓存；未登录 / 环境不可用（测试）时返回 null）。
  DynamicsClient? _cachedClient;

  DynamicsClient? _client() {
    final injected = widget.client;
    if (injected != null) return injected;
    final cached = _cachedClient;
    if (cached != null) return cached;
    try {
      final auth = ref.read(chatServiceProvider).auth;
      if (auth == null) return null;
      return _cachedClient = DynamicsClient(
        uin: auth.uin,
        s2: auth.s2,
        s2t: auth.s2t,
      );
    } catch (_) {
      return null;
    }
  }

  /// 点赞 / 取消点赞（act=like_posting；取消时 `unprize=1`）。
  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final client = _client();
    if (client == null) return;
    final wasLiked = _liked;
    setState(() {
      _likeBusy = true;
      _liked = !wasLiked;
      _likeCount = (_likeCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 31);
    });
    try {
      await client.likePosting(post.pid, unpraise: wasLiked);
    } catch (_) {
      // 失败回滚，并提示
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _likeCount = (_likeCount + (wasLiked ? 1 : -1)).clamp(0, 1 << 31);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  /// 关注作者（对齐游戏卡片 btn_attention）：与消息中心同一入口。
  Future<void> _follow() async {
    if (_followed) return;
    try {
      await ref.read(chatServiceProvider).followPlayer(post.uin, follow: true);
      if (mounted) {
        setState(() => _followed = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已关注')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('关注失败')));
      }
    }
  }

  /// 转发：选一个好友后上报 `share_posting`（对齐游戏卡片 `btn_share`）。
  Future<void> _share() async {
    final client = _client();
    if (client == null) return;
    final contacts = ref.read(contactsProvider).value ?? const <Contact>[];
    final friends = contacts
        .where((c) => (c.relation & 8) != 0)
        .toList()
      ..sort((a, b) => a.nickname.compareTo(b.nickname));
    final target = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: friends.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: Text('还没有好友可以分享')),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final f in friends)
                    ListTile(
                      leading: AvatarView(
                        name: f.nickname,
                        avatarUrl: f.avatar,
                        radius: 18,
                        headType: f.headType,
                        headId: f.headId,
                        frameId: f.headFrameId,
                      ),
                      title: Text(f.nickname),
                      onTap: () => Navigator.pop(ctx, f.uin),
                    ),
                ],
              ),
      ),
    );
    if (target == null || !mounted) return;
    try {
      final count = await client.sharePosting(post.pid, target: target);
      if (!mounted) return;
      setState(() => _shareCount = count ?? (_shareCount + 1));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已转发给好友')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('转发失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (post.nickname ?? '${post.uin}').isEmpty
        ? '${post.uin}'
        : (post.nickname ?? '${post.uin}');

    // 关注按钮的显示条件：非本人，且作者与我既非好友(bit3=8)也非我关注(bit4=16)。
    // 作者不在联系人列表（数据未加载 / 非好友）时保持原行为：显示。
    final contacts = ref.watch(contactsProvider).value ?? const <Contact>[];
    Contact? author;
    for (final c in contacts) {
      if (c.uin == post.uin) {
        author = c;
        break;
      }
    }
    final relation = author?.relation ?? 0;
    final showFollow = !isMine && (relation & 8) == 0 && (relation & 16) == 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Padding(
          // 左上比右下收得更紧：玩家信息（头像 + 昵称/时间/属地）更贴近卡片
          // 左上角（原来四边都是 10）。
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 6, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部：头像 + [徽标]昵称 / 相对时间·IP属地  + 右上角关注按钮
              // 头像槽位（headFrameSlotSize）比昵称/时间文字块高，用 center 让
              // 文字块与槽位内居中的头像垂直对齐（start 会让文字块贴住槽位顶部）。
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    // 点头像 → 玩家卡片；点别处仍是进动态详情。
                    onTapUp: (d) => _showPlayerCard(context, ref, d.globalPosition),
                    child: AvatarView(
                      name: name,
                      avatarUrl: post.avatar,
                      radius: 20,
                      headType: post.headType,
                      headId: post.headId,
                      frameId: post.headFrameId,
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_meta().isNotEmpty)
                          Text(
                            _meta(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (showFollow)
                    // 「关注」钉在行右上角：外层 SizedBox 取头像槽位高度
                    // （行内最高子项），Align 因此获得有界高度、铺满行高，
                    // 把按钮顶到行顶部；行本身仍是 center，文字块不受影响。
                    // （行高无界时 Align 会收缩成按钮自身大小而回到居中。）
                    SizedBox(
                      height: headFrameSlotSize(20),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _FollowButton(
                          followed: _followed,
                          onTap: () => unawaited(_follow()),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // 中间：内容（截断 3 行；超长才显示「查看全文」，点击/整卡进详情页）
              _PostContent(
                content: post.content,
                style: const TextStyle(fontSize: 14, height: 1.4),
                onViewFull: () => _openDetail(context),
                onTopicTap: (id, label) => _openTopic(context, id, label),
              ),
              // 话题不单独成行：服务端把话题写在正文里（`#{名称&topicid}`），
              // 由 [buildRichSpans] 就地渲染成 `#名称`（对齐 dynamicsdatamanager.lua
              // :3176-3260 的 callBack1，内容里没标记就不显示）。
              // 图片（按宽高比）
              if (post.pics.isNotEmpty) _Images(pics: post.pics),
              // 视频动态标记（`video_res_id` 非空即视频）。游戏 contentType.video=4，
              // 见 dynamicsinfocard.lua:33-48 类型枚举 / :671-725 卡片布局。
              if (post.videoResId != null)
                const _ChipLabel(
                  icon: Icons.play_circle_outline,
                  text: '视频',
                ),
              // 投票动态：拉取投票详情就地展示（游戏 contentType.vote=5，内容由
              // `DynamicsDataManager:FindCacheVoteInfo` 提供，dynamicsinfocard.lua:507-556）。
              if (post.voteId != null)
                _VotePreview(
                  voteId: post.voteId!,
                  client: _client(),
                  isMine: isMine,
                ),
              // 附加信息：链接/作品卡
              if (post.linkName != null && post.linkName!.isNotEmpty)
                _LinkCard(post: post),
              // 抽奖动态：拉取抽奖详情就地展示（游戏 contentType.lottery=3，内容由
              // `DynamicsDataManager:FindCacheLotteryInfo` 提供）。
              if (post.lotteryId != null)
                _LotteryPreview(lotteryId: post.lotteryId!, client: _client())
              else if (post.isLottery)
                const _ChipLabel(icon: Icons.card_giftcard, text: '抽奖'),
              const SizedBox(height: 6),
              // 右下角：操作区（点赞/评论/转发 + ···）
              _Actions(
                post: post,
                liked: _liked,
                likeCount: _likeCount,
                shareCount: _shareCount,
                onLike: () => unawaited(_toggleLike()),
                onComment: () => _openDetail(context),
                onShare: () => unawaited(_share()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 相对时间 + IP 属地，如「3天前  IP 广东」。
  String _meta() {
    final parts = <String>[
      if (post.createTime > 0) _relativeTime(post.createTime),
      'IP ${post.location.isNotEmpty ? post.location : post.city}',
    ];
    return parts.join('  ');
  }

  /// 打开动态详情页。
  /// 点头像弹玩家卡片（锚在指针处；自己则显示不带好友操作的本人卡）。
  void _showPlayerCard(BuildContext context, WidgetRef ref, Offset position) {
    unawaited(
      showSessionPlayerInfoPopup(
        context,
        ref,
        uin: post.uin,
        name: post.nickname ?? '${post.uin}',
        anchor: Rect.fromLTWH(position.dx, position.dy, 1, 1),
        avatarUrl: post.avatar,
        headType: post.headType,
        headId: post.headId,
        headFrameId: post.headFrameId,
        // 别人：带好友操作；自己：只有「个人主页」入口。
        showActions: !isMine,
        // 动态来源的按钮组（个人中心 / 加好友 / 赠送 / 关注）。
        origin: PlayerCardOrigin.dynamics,
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DynamicsDetailPage(post: post)));
  }

  /// 点正文里的 `#话题` → 该话题下的动态列表（对齐游戏 callBack1 的 href='#id'）。
  void _openTopic(BuildContext context, String topicId, String label) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DynamicsTopicPage(
          topicId: topicId,
          topicTitle: label,
        ),
      ),
    );
  }
}

/// 截断内容：默认 3 行；仅当超长时显示「查看全文」，点击进详情页。
class _PostContent extends StatelessWidget {
  final String content;
  final TextStyle style;
  final VoidCallback onViewFull;

  /// 点话题 `#名称` 的回调（话题 id, 展示名）。
  final void Function(String topicId, String label)? onTopicTap;

  const _PostContent({
    required this.content,
    required this.style,
    required this.onViewFull,
    this.onTopicTap,
  });

  bool _overflows(double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: content, style: style),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return tp.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final over = _overflows(constraints.maxWidth);
        return InkWell(
          onTap: onViewFull,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: buildRichSpans(
                    content,
                    context: context,
                    onTopicTap: onTopicTap,
                  ),
                ),
                style: style,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (over)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '查看全文',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Images extends StatelessWidget {
  final List<PostImage> pics;

  const _Images({required this.pics});

  @override
  Widget build(BuildContext context) {
    // 最多显示 4 张，超出的隐藏。
    final show = pics.take(4).toList();
    final single = show.length == 1;
    final urls = show.map((p) => p.url).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          return single
              ? _SingleImage(
                  url: show.first.url,
                  maxWidth: maxWidth,
                  onTap: () => openImageViewer(context, urls, 0),
                )
              : _row(context, show, maxWidth, urls);
        },
      ),
    );
  }

  /// 多图（2-4）：排成一排，正方形，高度随单元格。
  Widget _row(
    BuildContext context,
    List<PostImage> pics,
    double maxWidth,
    List<String> urls,
  ) {
    return Row(
      children: [
        for (var i = 0; i < pics.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: GestureDetector(
              onTap: () => openImageViewer(context, urls, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image(image: CachedNetworkImageProvider(pics[i].url),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    loadingBuilder: (c, w, p) =>
                        p == null ? w : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单图：高度固定为"多图单元格"高度，宽度按图片真实比例（宽图变宽、竖图变窄，不裁剪）。
/// 需运行时解析图片内在宽高比。
class _SingleImage extends StatefulWidget {
  final String url;
  final double maxWidth;
  final VoidCallback onTap;

  const _SingleImage({
    required this.url,
    required this.maxWidth,
    required this.onTap,
  });

  @override
  State<_SingleImage> createState() => _SingleImageState();
}

class _SingleImageState extends State<_SingleImage> {
  double? _ratio;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final provider = CachedNetworkImageProvider(widget.url);
      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info);
          stream.removeListener(listener);
        },
        onError: (e, st) {
          if (!completer.isCompleted) completer.completeError(e);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final info = await completer.future;
      if (!mounted) return;
      final w = info.image.width;
      final h = info.image.height;
      if (w > 0 && h > 0) setState(() => _ratio = w / h);
    } catch (_) {
      // 解析失败用默认比例，不阻断。
    }
  }

  @override
  Widget build(BuildContext context) {
    final tileH = (widget.maxWidth / 3).clamp(60.0, 120.0);
    final ratio = _ratio ?? kDefaultAspect;
    // 宽度 = 高度 × 比例，夹在合理区间，避免过窄/过宽。
    final width = (tileH * ratio).clamp(tileH * 0.4, widget.maxWidth);
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: width,
          height: tileH,
          child: Image(image: CachedNetworkImageProvider(widget.url),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
            loadingBuilder: (c, w, p) =>
                p == null ? w : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final DynamicsPost post;

  const _LinkCard({required this.post});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开作品/地图：${post.linkName}')));
      },
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              Icons.map_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.linkName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (post.linkAuthor != null)
                    Text(
                      '作者 ${post.linkAuthor}',
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 投票预览：拉 `get_vote_info` 就地展示标题与选项。
///
/// 对齐游戏卡片 contentType.vote=5（dynamicsinfocard.lua:507-556 用
/// `DynamicsDataManager:FindCacheVoteInfo` 的内容）；拉不到时退回「投票」标记，
/// 不假装有数据。
class _VotePreview extends StatefulWidget {
  final String voteId;
  final DynamicsClient? client;

  /// 动态作者是不是我（决定失败提示是否弹出，对齐游戏 `bolMine`）。
  final bool isMine;

  const _VotePreview({
    required this.voteId,
    this.client,
    this.isMine = false,
  });

  @override
  State<_VotePreview> createState() => _VotePreviewState();
}

class _VotePreviewState extends State<_VotePreview> {
  DynamicsVoteInfo? _info;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final info = await client.getVoteInfo(
        widget.voteId,
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
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    if (info == null) {
      return _ChipLabel(
        icon: Icons.how_to_vote_outlined,
        text: _loading ? '投票（加载中）' : '投票',
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.how_to_vote_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  info.title.isEmpty ? '投票' : info.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          for (final o in info.options.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      o.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '${o.count}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 抽奖预览：拉 `posting_lottery_query_lottery` 就地展示奖品 / 人数 / 状态。
///
/// 对齐游戏卡片 contentType.lottery=3（`FindCacheLotteryInfo`，
/// dynamicsinfocardlottery.lua:34 的 status 2=进行中 / 3=已结束）。
class _LotteryPreview extends StatefulWidget {
  final String lotteryId;
  final DynamicsClient? client;

  const _LotteryPreview({required this.lotteryId, this.client});

  @override
  State<_LotteryPreview> createState() => _LotteryPreviewState();
}

class _LotteryPreviewState extends State<_LotteryPreview> {
  DynamicsLottery? _lottery;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final list = await client.queryLotteries([widget.lotteryId]);
      if (!mounted) return;
      DynamicsLottery? found;
      for (final l in list) {
        if (l.lotteryId == widget.lotteryId) {
          found = l;
          break;
        }
      }
      found ??= list.isEmpty ? null : list.first;
      setState(() {
        _lottery = found;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = _lottery;
    if (l == null) {
      return _ChipLabel(
        icon: Icons.card_giftcard,
        text: _loading ? '抽奖（加载中）' : '抽奖',
      );
    }
    final status = switch (l.status) {
      2 => '进行中',
      3 => '已结束',
      _ => '',
    };
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.card_giftcard,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              [
                '抽奖',
                if (l.itemNum > 0) '奖品 ×${l.itemNum}',
                if (l.selectNum > 0) '开奖 ${l.selectNum} 人',
                if (l.joinCount > 0) '参与 ${l.joinCount} 人',
                if (status.isNotEmpty) status,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ChipLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 右下「关注」按钮（pill）；已关注后文案变「已关注」（对齐游戏
/// `btn_attention` / `btn_attentioned`，dynamicsinfocard.lua:2137/2183）。
class _FollowButton extends StatelessWidget {
  final bool followed;
  final VoidCallback onTap;

  const _FollowButton({required this.followed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: followed
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          followed ? '已关注' : '关注',
          style: TextStyle(
            fontSize: 12,
            color: followed
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final DynamicsPost post;
  final bool liked;
  final int likeCount;
  final int shareCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  const _Actions({
    required this.post,
    required this.liked,
    required this.likeCount,
    required this.shareCount,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 点赞（对齐游戏卡片 `btn_like`，dynamicsinfocard.lua:1878）
        _ActionIcon(
          icon: liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
          count: likeCount,
          color: liked ? theme.colorScheme.primary : null,
          onTap: onLike,
        ),
        // 评论（对齐 `btn_comment`, :1908）→ 动态详情
        _ActionIcon(
          icon: Icons.mode_comment_outlined,
          count: post.commentCount,
          onTap: onComment,
        ),
        // 转发（对齐 `btn_share`, :2027）
        _ActionIcon(
          icon: Icons.reply_outlined,
          count: shareCount,
          onTap: onShare,
        ),
        // 更多（对齐 `btn_ellipsis`, :2037）：外部客户端暂无举报/不感兴趣等
        // 写接口，统一进动态详情（作者本人在那里有删除/置顶/可见范围）。
        IconButton(
          visualDensity: adaptiveDensity(context),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, size: 18),
          onPressed: onComment,
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback? onTap;

  /// 高亮色（已点赞等）；为空时用 outline。
  final Color? color;

  const _ActionIcon({
    required this.icon,
    required this.count,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: tint),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(color: tint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 相对时间：刚刚 / X分钟前 / X小时前 / X天前 / X月前 / X年前。
String _relativeTime(int ts) {
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
