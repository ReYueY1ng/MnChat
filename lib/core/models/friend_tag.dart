/// 好友标签（分组）—— 对齐反编译 `newfriendservice.lua:597-747`。
///
/// 标签文案在协议里是 **base64**（`EncodeFriendLabel` / `DecodeFriendLabel`）；
/// 标签池 `query_friend_label_pool` 返回
/// `{result:0, label_list:[{tag_id, label, uin_list}]}`，
/// 其中 `uin_list` 是"打了这个标签的好友"，所以按 uin 过滤要反查。
library;

import 'dart:convert';

/// 一个好友标签。
class FriendTag {
  final int tagId;

  /// 解码后的文案。
  final String label;

  /// 打了此标签的好友 uin。
  final List<int> uins;

  const FriendTag({
    required this.tagId,
    required this.label,
    this.uins = const <int>[],
  });

  bool get isValid => tagId > 0 && label.isNotEmpty;
}

/// 标签文案上限：游戏 `FormatFriendTagInputText` 限 5 个字
/// （`main_newfriendsmgrctrl.lua:1064-1117`）。
const int kFriendTagMaxLength = 5;

/// 编码标签文案（写接口要 base64，且**不能带 `=` 补位**）。
///
/// 实测（2026-10-02 真实账号，自己的标签池）：`base64` 带补位建标签，服务端
/// 回 `{"result":2}`；去掉补位才回 `{"result":0,"tag_id":…}`。服务端回给
/// 客户端的 `label` 同样是无补位形式，所以两头都不带 `=`。
String encodeFriendLabel(String label) =>
    base64Encode(utf8.encode(label)).replaceAll('=', '');

/// 解码标签文案；失败原样返回（游戏里也是 pcall 兜底）。
///
/// 服务端下发的是**无 `=` 补位**的 base64，而 Dart 的 [base64.decode] 要求长度是
/// 4 的倍数：标签的 UTF-8 字节数不是 3 的倍数时会直接抛 FormatException，被下面的
/// catch 吞掉，于是列表里显示成 `cHJvYmU` 这种原始 base64（`probe` 的实际遭遇）。
/// 中文标签每字 3 字节，编码后正好总是 4 的倍数，所以这个坑一直没暴露。
String decodeFriendLabel(Object? raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(_padBase64(s)));
  } catch (_) {
    return s;
  }
}

/// 把无补位的 base64 补成 Dart 能解码的形式（已是补位形式就原样返回）。
String _padBase64(String s) {
  if (s.endsWith('=')) return s;
  final rest = s.length % 4;
  return rest == 0 ? s : s.padRight(s.length + (4 - rest), '=');
}

/// 解析标签池响应 → 标签列表（丢掉没有 tag_id / 文案为空的项）。
List<FriendTag> parseFriendTagPool(Object? resp) {
  final out = <FriendTag>[];
  if (resp is! Map) return out;
  final list = resp['label_list'] ?? resp['labelList'];
  if (list is! List) return out;
  for (final e in list) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final id = _toInt(m['tag_id'] ?? m['tagId'] ?? m['id']);
    if (id <= 0) continue;
    final label = decodeFriendLabel(m['label']);
    if (label.isEmpty) continue;
    final uins = <int>[];
    final raw = m['uin_list'] ?? m['uinList'];
    if (raw is List) {
      for (final u in raw) {
        final n = _toInt(u);
        if (n > 0) uins.add(n);
      }
    }
    out.add(FriendTag(tagId: id, label: label, uins: uins));
  }
  return out;
}

/// 反查：好友 uin → 它的标签 id 集合。
Map<int, Set<int>> friendTagIndex(List<FriendTag> tags) {
  final out = <int, Set<int>>{};
  for (final t in tags) {
    for (final uin in t.uins) {
      (out[uin] ??= <int>{}).add(t.tagId);
    }
  }
  return out;
}

int _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}
