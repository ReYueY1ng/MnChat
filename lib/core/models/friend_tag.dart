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

/// 编码标签文案（写接口要 base64）。
String encodeFriendLabel(String label) => base64Encode(utf8.encode(label));

/// 解码标签文案；失败原样返回（游戏里也是 pcall 兜底）。
String decodeFriendLabel(Object? raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(s));
  } catch (_) {
    return s;
  }
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
