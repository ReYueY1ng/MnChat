import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/chat_emoji.dart' show kChatEmoji;
import '../../core/services/dynamics.dart';
import '../dynamics_detail_page.dart';
import 'avatar_view.dart';
import 'image_viewer.dart';

/// 把 Mini World 富文本（[color]/[b]/[i]/[u]/表情码）解析为 [TextSpan] 列表。
/// 供动态卡片与详情页复用。
List<TextSpan> dynamicsContentSpans(String content, BuildContext context) {
  final spans = <TextSpan>[];
  final re = RegExp(r'(\[[/]?[a-zA-Z=#0-9]*[^\]]*\]|<a>|</a>|#A\d{3})');
  var pos = 0;
  var color = Colors.transparent;
  var bold = false;
  var italic = false;
  var underline = false;
  for (final match in re.allMatches(content)) {
    if (match.start > pos) {
      spans.add(_plainSpan(content.substring(pos, match.start), color, bold, italic, underline));
    }
    final tag = match.group(0)!;
    final lower = tag.toLowerCase();
    if (lower.startsWith('[color')) {
      if (tag.startsWith('[/')) {
        color = Colors.transparent;
      } else {
        final inner = tag.replaceAll('[', '').replaceAll(']', '');
        final eq = inner.indexOf('=');
        if (eq >= 0) {
          color = _parseColor(inner.substring(eq + 1));
        } else {
          color = Theme.of(context).colorScheme.primary;
        }
      }
    } else if (lower.startsWith('[b')) {
      bold = !lower.startsWith('[/');
    } else if (lower.startsWith('[i')) {
      italic = !lower.startsWith('[/');
    } else if (lower.startsWith('[u')) {
      underline = !lower.startsWith('[/');
    } else if (lower.startsWith('[size') || lower.startsWith('<a') || lower.startsWith('</a')) {
      // size/超链接 —— 忽略
    } else if (kChatEmoji.containsKey(tag)) {
      spans.add(TextSpan(text: kChatEmoji[tag]));
    } else {
      spans.add(TextSpan(text: tag));
    }
    pos = match.end;
  }
  if (pos < content.length) {
    spans.add(_plainSpan(content.substring(pos), color, bold, italic, underline));
  }
  return spans;
}

TextSpan _plainSpan(String text, Color color, bool bold, bool italic, bool underline) {
  return TextSpan(
    text: text,
    style: TextStyle(
      color: color == Colors.transparent ? null : color,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: underline ? TextDecoration.underline : null,
    ),
  );
}

Color _parseColor(String raw) {
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  try {
    return Color(int.parse('FF$s', radix: 16));
  } catch (_) {
    return Colors.transparent;
  }
}

/// 动态卡片 —— 左上头像+徽标+昵称 / 相对时间·IP属地 / 内容(查看全文) / 图片 / 附加信息 / 右下操作区。
class DynamicsCard extends StatelessWidget {
  final DynamicsPost post;

  /// 是否我的动态（我自己的不显示「关注」按钮）。
  final bool isMine;

  const DynamicsCard({super.key, required this.post, this.isMine = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (post.nickname ?? '${post.uin}').isEmpty ? '${post.uin}' : (post.nickname ?? '${post.uin}');

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部：头像 + [徽标]昵称 / 相对时间·IP属地  + 关注按钮
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarView(name: name, avatarUrl: post.avatar, radius: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        if (_meta().isNotEmpty)
                          Text(
                            _meta(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                      ],
                    ),
                  ),
                  if (!isMine) const _FollowButton(),
                ],
              ),
              const SizedBox(height: 8),
              // 中间：内容（截断 3 行；超长才显示「查看全文」，点击/整卡进详情页）
              _PostContent(
                content: post.content,
                style: const TextStyle(fontSize: 14, height: 1.4),
                onViewFull: () => _openDetail(context),
              ),
              // 图片（按宽高比）
              if (post.pics.isNotEmpty) _Images(pics: post.pics),
              // 附加信息：链接/作品卡
              if (post.linkName != null && post.linkName!.isNotEmpty) _LinkCard(post: post),
              if (post.isLottery) const _ChipLabel(icon: Icons.card_giftcard, text: '抽奖'),
              const SizedBox(height: 6),
              // 右下角：操作区（点赞/评论/转发 + ···）
              _Actions(post: post),
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
  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DynamicsDetailPage(post: post)),
    );
  }
}

/// 截断内容：默认 3 行；仅当超长时显示「查看全文」，点击进详情页。
class _PostContent extends StatelessWidget {
  final String content;
  final TextStyle style;
  final VoidCallback onViewFull;

  const _PostContent({required this.content, required this.style, required this.onViewFull});

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
                TextSpan(children: dynamicsContentSpans(content, context)),
                style: style,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (over)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('查看全文', style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
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
              ? _SingleImage(url: show.first.url, maxWidth: maxWidth, onTap: () => openImageViewer(context, urls, 0))
              : _row(context, show, maxWidth, urls);
        },
      ),
    );
  }

  /// 多图（2-4）：排成一排，正方形，高度随单元格。
  Widget _row(BuildContext context, List<PostImage> pics, double maxWidth, List<String> urls) {
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
                  child: Image.network(pics[i].url, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      loadingBuilder: (c, w, p) => p == null ? w : const SizedBox.shrink()),
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

  const _SingleImage({required this.url, required this.maxWidth, required this.onTap});

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
      final provider = NetworkImage(widget.url);
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
          child: Image.network(widget.url, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              loadingBuilder: (c, w, p) => p == null ? w : const SizedBox.shrink()),
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final DynamicsPost post;

  const _LinkCard({required this.post});  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开作品/地图：${post.linkName}')),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.map_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.linkName!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (post.linkAuthor != null)
                    Text('作者 ${post.linkAuthor}', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: theme.colorScheme.onTertiaryContainer)),
        ],
      ),
    );
  }
}

/// 右下「关注」按钮（pill）。
class _FollowButton extends StatelessWidget {
  const _FollowButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text('关注',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final DynamicsPost post;

  const _Actions({required this.post});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ActionIcon(icon: Icons.thumb_up_alt_outlined, count: post.likeCount),
        _ActionIcon(icon: Icons.mode_comment_outlined, count: post.commentCount),
        _ActionIcon(icon: Icons.reply_outlined, count: post.shareCount),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, size: 18),
          onPressed: () {},
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const _ActionIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.outline),
          if (count > 0) ...[
            const SizedBox(width: 3),
            Text('$count', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ],
      ),
    );
  }
}

/// 相对时间：刚刚 / X分钟前 / X小时前 / X天前 / X月前 / X年前。
String _relativeTime(int ts) {
  if (ts <= 0) return '';
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
  return '${(diff.inDays / 365).floor()}年前';
}
