/// 玩家主页（`get_user_homepage`）模块的纯解析函数。
///
/// 主页响应是 `{模块名: {data: {...}}}` 的松散结构，且同一字段在不同接口间
/// 类型不一致（数字 / 数字字符串混用）。这里只收敛 UI 需要的三个模块：
///   - `title`（模块 9）：当前佩戴称号 id（`title.data.match_title.use_title.id`）；
///   - `achieve`（模块 6/13）：勋章列表（`achieve.data.medal_list` → `[(id, level)]`）；
///   - `social_sign`（模块 16）：交友宣言（`{social_lab, game_lab}`）。
///
/// 解析口径与 `ui/widgets/session_player_info_popup.dart`、
/// `ui/player_home_page.dart` 中既有的私有实现保持一致（那两处的辅助函数为
/// 私有且不在本次改动范围，故此处收敛为可单测的公开函数）。
///
/// 约定（与仓库内其它解析器一致）：任何脏数据（非 Map / 缺字段 / 类型不符 /
/// 非正 id）只跳过，**绝不抛异常**；取不到时返回 `0` / 空列表 / `null`，
/// 由调用方自行降级为「—」占位。
library;

import '../services/social_sign.dart' show SocialDeclaration;

/// 数字容错：`int` / `num` / 数字字符串 → `int`，其余 → [fallback]。
int _toInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

/// 当前佩戴称号 id；未佩戴 / 数据缺失 → `0`。
int homepageTitleId(Map<String, Object?>? home) {
  final title = home?['title'];
  if (title is! Map) return 0;
  final data = title['data'];
  if (data is! Map) return 0;
  final match = data['match_title'];
  if (match is! Map) return 0;
  final use = match['use_title'];
  if (use is! Map) return 0;
  final m = use.cast<String, Object?>();
  return _toInt(m['id'] ?? m['ID']);
}

/// 勋章列表 `[(id, level)]`；`id <= 0` 的脏条目跳过。
///
/// `level` 缺失按 `0` 处理（渲染层回退到无等级边框）。
List<(int, int)> homepageMedals(Map<String, Object?>? home) {
  final achieve = home?['achieve'];
  if (achieve is! Map) return const <(int, int)>[];
  final data = achieve['data'];
  if (data is! Map) return const <(int, int)>[];
  final list = data['medal_list'];
  if (list is! List) return const <(int, int)>[];
  final out = <(int, int)>[];
  for (final e in list) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final id = _toInt(m['id'] ?? m['ID']);
    if (id <= 0) continue;
    out.add((id, _toInt(m['level'] ?? m['Level'])));
  }
  return out;
}

/// 交友宣言（`social_sign` 模块）；未设置 / 数据缺失 → `null`。
///
/// 字段既可能平铺在模块层（`player_home_page.dart` 的读法），也可能包在
/// `data` 里，两种都要兼容：先读模块层，为空再读 `data`。
SocialDeclaration? homepageDeclaration(Map<String, Object?>? home) {
  final module = home?['social_sign'];
  if (module is! Map) return null;
  final m = module.cast<String, Object?>();
  final direct = SocialDeclaration.fromMap(m);
  if (!direct.isEmpty) return direct;
  final data = m['data'];
  if (data is! Map) return null;
  final nested = SocialDeclaration.fromMap(data.cast<String, Object?>());
  return nested.isEmpty ? null : nested;
}
