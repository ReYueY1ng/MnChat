/// 群聊 @ 提及判定。
///
/// 迷你世界的 @ 是**纯文本**：服务端推送里没有独立的「提及了谁」字段，
/// 正文就是 `@昵称 内容`。因此「仅 @我时提醒」只能按文本匹配，规则与
/// `ui/widgets/rich_text_view.dart` 渲染 @ 的口径保持一致（`@` + 昵称）。
///
/// 匹配刻意保守：昵称为空时一律返回 false（不知道自己的昵称就没法判断，
/// 这种时候宁可不提醒也不误报）。
///
/// 已知局限（有意为之）：只要 `@` 后面以本人昵称开头就算命中，
/// 所以 `@顾念之` 也会当成提及了「顾念」。中文没有词边界，做不了干净的前缀
/// 切分；相比漏掉真正 @我 的消息，多提醒一次是更可接受的错。
library;

/// [text] 是否提到了 [nickname]。
///
/// 允许 `@` 与昵称之间有空白（手输 @ 时常带一个空格），也允许昵称被
/// 服务端的富文本标记包裹的常见形态（如 `[b]昵称`）。
bool textMentions(String text, String nickname) {
  final name = nickname.trim();
  if (text.isEmpty || name.isEmpty) return false;

  var from = 0;
  while (true) {
    final at = text.indexOf('@', from);
    if (at < 0) return false;
    from = at + 1;
    // 跳过 @ 与昵称之间的空白
    var i = at + 1;
    while (i < text.length && _isSpace(text.codeUnitAt(i))) {
      i++;
    }
    if (text.startsWith(name, i)) return true;
  }
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
