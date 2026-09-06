/// Mini World 文本里的表情码（#A1xx / #A3xx 等）→ 用于 MNChat 端显示的近似 Unicode。
///
/// **注意**：游戏的表情是**非标准 emoji**，由 `#A1xx` 代码指向它自己的贴图资源
/// （反编译 chatconfig.lua）。发送时必须保留 `#A1xx` 代码；这里给的是 MNChat 端
/// 没有游戏贴图时的一个**近似 Unicode 展示**。游戏客户端收到 `#A1xx` 会渲染成它
/// 自己的图标。
library;

/// 游戏表情码 → 近似 Unicode（MNChat 端展示用；未列出的码保留原文）。
const Map<String, String> kChatEmoji = {
  // 基础表情（#A1xx, 顺序对齐 chatconfig.lua）
  '#A101': '😏', // 斜眼笑
  '#A102': '🙄', // 白眼
  '#A103': '😠', // 生气
  '#A104': '😒', // 嫌弃
  '#A105': '😭', // 大哭
  '#A106': '😘', // 亲亲
  '#A107': '🥰', // 喜欢
  '#A108': '🤏', // 挖鼻孔
  '#A109': '👍', // 点赞
  '#A110': '😳', // 害羞
  '#A111': '😢', // 流泪
  '#A112': '🥺', // 可爱
  '#A113': '🥲', // 收齐报
  '#A114': '😴', // 困
  '#A115': '😲', // 惊讶
  '#A116': '😵', // 晕
  '#A117': '💀', // 烧焦
  '#A118': '👋', // 拜拜
  // 花式变体（#A3xx, hua_ 前缀，同样保留代码）
  '#A301': '😘', '#A302': '🙄', '#A303': '😠', '#A304': '😒',
  '#A305': '😭', '#A306': '😘', '#A307': '🥰', '#A308': '🤏',
  '#A309': '👍', '#A310': '😳', '#A311': '😢', '#A312': '🥺',
  '#A313': '🥲', '#A314': '😴', '#A315': '😲', '#A316': '😵',
  '#A317': '💀', '#A318': '👋',
};

/// 游戏表情选择器使用的**有序基础表情码**（#A1xx 这一组，MNChat 选择器展示）。
const List<String> kGameEmojiCodes = [
  '#A101', '#A102', '#A103', '#A104', '#A105', '#A106', '#A107', '#A108', '#A109',
  '#A110', '#A111', '#A112', '#A113', '#A114', '#A115', '#A116', '#A117', '#A118',
];

/// 表情码 → Unicode 表示（无映射时返回原文）。
String emojiRepr(String code) => kChatEmoji[code] ?? code;

/// 把文本里的表情码替换为 Unicode（逐个替换已知码，MNChat 自身气泡显示用）。
String decodeEmojiCodes(String text) {
  if (text.isEmpty || (!text.contains('#A1') && !text.contains('#A3'))) return text;
  var out = text;
  for (final e in kChatEmoji.entries) {
    if (out.contains(e.key)) out = out.replaceAll(e.key, e.value);
  }
  return out;
}
