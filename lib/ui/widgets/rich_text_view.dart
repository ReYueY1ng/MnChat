import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chat_emoji.dart' show kChatEmoji;
import '../../core/emoticon.dart' show EmoticonImage;
import '../../core/models/nickname.dart';
import '../../state/providers.dart';

/// 迷你世界富文本 → [InlineSpan] 的统一解析。
///
/// 支持：
/// - `[color=#RRGGBB]` / `[/color]`：着色（无值则用主题色）
/// - `[b]` `[i]` `[u]` 及对应 `[/x]`：加粗 / 斜体 / 下划线
/// - `[size=..]` `<a>` `</a>`：忽略标记（不显示为文字）
/// - `#A1xx`：渲染为游戏表情贴图（[EmoticonImage]）
/// - `#{标签&...}#`：渲染为内联话题文本 `#标签`
/// - `@昵称`：主题色高亮
///
/// 供动态卡片 / 详情 / 评论 / 昵称等复用，避免每个页面各写一套正则。
List<InlineSpan> buildRichSpans(
  String content, {
  required BuildContext context,
  double emojiSize = 16,
}) {
  final spans = <InlineSpan>[];
  if (content.isEmpty) return spans;
  final scheme = Theme.of(context).colorScheme;
  final re = RegExp(
    // `@` 提及：排除空白、`[`/`<`（标记起始）与中文标点，避免把
    // `@[color]名字，后续正文` 整段吞成一个 mention。
    // `#[cC]RRGGBB` 为游戏颜色码；`#n` 为换行（见 ubbcodeparser / stringdef.csv）。
    r'(\[[/]?[a-zA-Z=#0-9]*[^\]]*\]|<[/]?[a-zA-Z][^>]{0,24}>|#[cC][0-9a-fA-F]{6}|#n|#A\d{3}|#\{[^}]*\}|@[^\s@\[\]<>#，。！？、：；]{1,24})',
  );

  var pos = 0;
  var color = Colors.transparent;
  var bold = false;
  var italic = false;
  var underline = false;

  void addPlain(String text) {
    if (text.isEmpty) return;
    spans.add(
      TextSpan(
        text: text,
        style: TextStyle(
          color: color == Colors.transparent ? null : color,
          fontWeight: bold ? FontWeight.bold : null,
          fontStyle: italic ? FontStyle.italic : null,
          decoration: underline ? TextDecoration.underline : null,
        ),
      ),
    );
  }

  for (final match in re.allMatches(content)) {
    if (match.start > pos) addPlain(content.substring(pos, match.start));
    final tag = match.group(0)!;
    final lower = tag.toLowerCase();
    if (lower.startsWith('[color')) {
      if (tag.startsWith('[/')) {
        color = Colors.transparent;
      } else {
        final inner = tag.replaceAll('[', '').replaceAll(']', '');
        final eq = inner.indexOf('=');
        color = eq >= 0 ? _parseColor(inner.substring(eq + 1)) : scheme.primary;
      }
    } else if (lower.startsWith('[b')) {
      bold = !lower.startsWith('[/');
    } else if (lower.startsWith('[i')) {
      italic = !lower.startsWith('[/');
    } else if (lower.startsWith('[u')) {
      underline = !lower.startsWith('[/');
    } else if (lower.startsWith('[size') || tag.startsWith('<')) {
      // 富文本标签（[size=..] / <a> / <s> / [sup] / [sub] /
      // [font=..] / [align=..] / [url=..] / [img] 等）：忽略标记本身
    } else if (tag.length == 8 &&
        (tag.startsWith('#c') || tag.startsWith('#C'))) {
      // 游戏颜色码 `#cRRGGBB`（stringdef.csv 里安全提示即用 `#cFF0000`）
      color = _parseColor(tag.substring(2));
    } else if (tag == '#n') {
      // 游戏换行码 `#n`
      spans.add(const TextSpan(text: '\n'));
    } else if (tag.startsWith('#{')) {
      final label = topicLabels(tag).firstOrNull;
      if (label != null && label.isNotEmpty) {
        spans.add(
          TextSpan(
            text: ' #$label ',
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              backgroundColor: scheme.primaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
    } else if (kChatEmoji.containsKey(tag)) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: EmoticonImage(code: tag, size: emojiSize),
        ),
      );
    } else if (tag.startsWith('@{')) {
      // 游戏 @提及格式 `@{昵称:uin}` → 只显示 `@昵称`
      final inner = tag.substring(2).split('}').first;
      final name = inner.split(':').first;
      spans.add(
        TextSpan(
          text: '@$name',
          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
        ),
      );
    } else if (tag.startsWith('@')) {
      // 兜底：`@` 后若仍夹带标记，清洗后再着色。
      final shown = plainNickname(tag.substring(1));
      spans.add(
        TextSpan(
          text: '@${shown.isEmpty ? '' : shown}',
          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
        ),
      );
    } else if (tag.startsWith('[')) {
      // 未识别的 `[xxx]` 标记：忽略，不把标记本身显示给用户。
    } else {
      spans.add(TextSpan(text: tag));
    }
    pos = match.end;
  }
  if (pos < content.length) addPlain(content.substring(pos));
  return spans;
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

/// 富文本展示组件：自动清洗标记并按需渲染表情 / 话题 / 颜色。
///
/// 无标记时退化为普通 [Text]，避免不必要的 span 开销（列表滚动友好）。
/// 「富文本显示原文本」开启时跳过全部解析，原样显示源字符串（含标签）。
class RichTextView extends ConsumerWidget {
  final String? text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final double emojiSize;

  const RichTextView(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.emojiSize = 16,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = text ?? '';
    if (raw.isEmpty) {
      return Text('', style: style, maxLines: maxLines, overflow: overflow);
    }
    // 「富文本显示原文本」开启：不解析标记，原样显示。
    if (ref.watch(richTextRawProvider)) {
      return Text(
        raw,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }
    if (!hasRichMarkup(raw)) {
      return Text(
        raw,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: buildRichSpans(raw, context: context, emojiSize: emojiSize),
      ),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
