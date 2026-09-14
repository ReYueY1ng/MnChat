/// 迷你世界（Mini World）昵称 / 正文富文本标记的纯文本解析。
///
/// 游戏协议里昵称与动态正文夹杂控制标记，例如：
///   `[i][color][b]顾念`、`<a>_谢俞<a>`、`[u]斩玉京`、`[size=14]...`
/// 这些标记若原样渲染，会显示成 `[i][color][b]顾念`，头像首字母还会取到
/// `<` / `[`。此文件提供不依赖 Flutter 的纯字符串清洗，供头像、标题、
/// 列表等无需富文本的地方复用。
///
/// 表情码 `#A1xx` 与话题 `#{标签&...}#` 会被保留 / 抽出，交由 UI 层决定
/// 如何渲染（贴图或 chip）。
library;

/// 标记正则：
/// - `[...]`（含 `[/...]`）：`[i]` `[color=..]` `[size=14]` 等
/// - `<...>`（含 `</...>`）：`<a>` `<s>` `</s>` 等（游戏不止 `<a>`）
final RegExp _markupRe = RegExp(
  r'\[[/]?[a-zA-Z=#0-9]*[^\]]*\]|<[/]?[a-zA-Z][^>]{0,24}>',
);

/// 话题 / @提及标记：`#{标签&u:123:456}` → 标签。
///
/// 注意：标记末尾**没有** `#`（`#{..}#{..}` 中第二个 `#` 属于下一个话题），
/// 若把结尾 `#` 写进正则会吞掉相邻话题。
final RegExp _topicRe = RegExp(r'#\{([^}&]*)(?:&[^}]*)?\}');

/// 游戏颜色码 `#cRRGGBB`（stringdef.csv 中安全提示用 `#cFF0000`）。
final RegExp _colorCodeRe = RegExp(r'#[cC][0-9a-fA-F]{6}');

/// 去掉富文本标记，返回可直接显示的纯文本。
///
/// 若清洗后为空（例如昵称只由标记组成），返回空字符串 —— 调用方应回退到
/// 迷你号，而不是把 `[i]` 之类的标记显示出来。
String plainNickname(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed
      .replaceAll(_markupRe, '')
      .replaceAll(_colorCodeRe, '')
      .replaceAll('#n', '')
      .trim();
}

/// 是否包含富文本标记（用于判断是否需要走富文本渲染）。
bool hasRichMarkup(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  return _markupRe.hasMatch(raw) ||
      _topicRe.hasMatch(raw) ||
      _colorCodeRe.hasMatch(raw) ||
      raw.contains('#n');
}

/// 抽取正文里所有话题标签（`#{福利&...}#` → `福利`），保持出现顺序、去重。
List<String> topicLabels(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final m in _topicRe.allMatches(raw)) {
    final label = m.group(1)?.trim() ?? '';
    if (label.isNotEmpty && seen.add(label)) out.add(label);
  }
  return out;
}

/// 把话题标记替换成可读的 `#标签` 文本（无 UI 依赖的降级形态）。
String plainContent(String? raw) {
  if (raw == null) return '';
  final withTopics = raw.replaceAllMapped(
    _topicRe,
    (m) => '#${m.group(1)?.trim() ?? ''}',
  );
  return withTopics
      .replaceAll(_markupRe, '')
      .replaceAll(_colorCodeRe, '')
      .replaceAll('#n', '\n');
}
