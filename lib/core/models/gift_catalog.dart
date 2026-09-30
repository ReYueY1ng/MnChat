/// 赠送礼物的目录（visual-cfg `new_give_gift_config`）+ 礼物名/图标（`items`）。
///
/// 对齐反编译：
/// - `NewFriendGiftInterface:OpenFriendGiftMainUI`（`newfriendgiftinterface.lua:46-115`）
///   读 `ret.gift.gift_cfg`，逐项按 `is_time_limit` + `ctrl` 过滤；
/// - `FriendGiftDataMgr:SendFriendGift`（`friendgiftdatamgr.lua:476-578`）
///   发 `act=give_gift&op_uin&id&num&type&role_name`；
/// - 礼物名/图标来自道具定义（游戏里是 `ItemDefCsv:get(itemid).Name`），
///   客户端没有那份 csv，用 visual-cfg `items` 兜底，取不到就只显示编号。
library;

import '../services/title_config.dart' show extractLuaBlock;

/// 一个可赠送的礼物（`gift_cfg` 项）。
class GiftItem {
  /// 道具 ID（也是 `give_gift` 的 `id`）。
  final int id;

  /// 支付货币：`10002` = 迷你币，`10000` = 迷你豆（其余按迷你币处理）。
  final int costId;

  /// 单价。
  final int costNum;

  /// 赠送增加的默契度。
  final int intimacies;

  /// 增加的魅力值。
  final int charmValue;

  /// 免费礼物（`if_free`）。
  final bool free;

  /// 看广告赠送（`if_advert`）。
  final bool ad;

  /// 是否限时（`is_time_limit` + `startTime`/`endTime`，毫秒）。
  final bool timeLimited;
  final int? startTime;
  final int? endTime;

  /// 展示名 / 图标（来自 `items` 配置；拿不到为 null）。
  final String? name;
  final String? icon;

  const GiftItem({
    required this.id,
    this.costId = 10002,
    this.costNum = 0,
    this.intimacies = 0,
    this.charmValue = 0,
    this.free = false,
    this.ad = false,
    this.timeLimited = false,
    this.startTime,
    this.endTime,
    this.name,
    this.icon,
  });

  /// 货币名（对齐游戏：`cost_id == 10002` 是迷你币，否则迷你豆）。
  String get currency => costId == 10002 ? '迷你币' : '迷你豆';

  /// 展示名：优先道具名，其次编号。
  String get displayName => (name != null && name!.isNotEmpty) ? name! : '礼物 $id';

  /// 是否在有效期内（限时礼物过期则不展示）。
  bool activeAt(DateTime now) {
    if (!timeLimited) return true;
    final ms = now.millisecondsSinceEpoch;
    if (startTime != null && startTime! > 0 && ms < startTime!) return false;
    if (endTime != null && endTime! > 0 && ms > endTime!) return false;
    return true;
  }

  GiftItem withMeta({String? name, String? icon}) => GiftItem(
    id: id,
    costId: costId,
    costNum: costNum,
    intimacies: intimacies,
    charmValue: charmValue,
    free: free,
    ad: ad,
    timeLimited: timeLimited,
    startTime: startTime,
    endTime: endTime,
    name: name ?? this.name,
    icon: icon ?? this.icon,
  );
}

/// 礼物目录。
class GiftCatalog {
  final List<GiftItem> items;

  /// `gift.select_times`：默认赠送份数。
  final int defaultTimes;

  /// `gift.day_intimacies_limit`：每日默契度上限（0 = 未下发）。
  final int dayIntimaciesLimit;

  const GiftCatalog({
    required this.items,
    this.defaultTimes = 1,
    this.dayIntimaciesLimit = 0,
  });

  static const GiftCatalog empty = GiftCatalog(items: <GiftItem>[]);

  bool get isEmpty => items.isEmpty;

  /// 按 id 找礼物。
  GiftItem? byId(int id) {
    for (final g in items) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// 过滤掉过期礼物后的列表。
  List<GiftItem> activeAt(DateTime now) =>
      [for (final g in items) if (g.activeAt(now)) g];
}

/// 取出 [text] 里所有平衡的 `{...}` 块内容（含嵌套层，外层在前）。
///
/// 配置里常有 `ctrl = {...}` 这类嵌套，用"最内层块"的 regex 会把它们拆散，
/// 所以统一按大括号配平来切。
List<String> allLuaBlocks(String text) {
  final out = <String>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i] != '{') continue;
    var depth = 0;
    for (var j = i; j < text.length; j++) {
      if (text[j] == '{') {
        depth++;
      } else if (text[j] == '}') {
        depth--;
        if (depth == 0) {
          out.add(text.substring(i + 1, j));
          break;
        }
      }
    }
  }
  return out;
}

/// 取出 [text] 里所有**深度 1** 的 `{...}` 块（跳过更深的嵌套）。
List<String> topLevelBlocks(String text) {
  final out = <String>[];
  var depth = 0;
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '{') {
      if (depth == 0) start = i + 1;
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0 && start >= 0) {
        out.add(text.substring(start, i));
        start = -1;
      }
      if (depth < 0) depth = 0;
    }
  }
  return out;
}

/// 解析 `new_give_gift_config`（`gift.gift_cfg`）。
///
/// 只认同时带 `id` 与 `cost_num` 的项 —— 每项还带一层 `ctrl`，
/// 不筛会把 `ctrl` 里的字段也当成一项。
GiftCatalog parseGiftCatalog(String text) {
  final block = extractLuaBlock(text, 'gift_cfg');
  if (block == null) return GiftCatalog.empty;
  // extractLuaBlock 带回最外层大括号，去掉后深度 1 就是各项。
  final inner = block.length >= 2
      ? block.substring(1, block.length - 1)
      : block;

  int? intOf(String body, String key) {
    final m = RegExp('\\b$key\\s*=\\s*(-?\\d+)').firstMatch(body);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  final items = <GiftItem>[];
  for (final body in topLevelBlocks(inner)) {
    final id = intOf(body, 'id');
    final costNum = intOf(body, 'cost_num');
    if (id == null || id <= 0 || costNum == null) continue;
    items.add(
      GiftItem(
        id: id,
        costId: intOf(body, 'cost_id') ?? 10002,
        costNum: costNum,
        intimacies: intOf(body, 'intimacies') ?? 0,
        charmValue: intOf(body, 'charm_value') ?? 0,
        free: (intOf(body, 'if_free') ?? 0) == 1,
        ad: (intOf(body, 'if_advert') ?? 0) == 1,
        timeLimited: (intOf(body, 'is_time_limit') ?? 0) == 1,
        startTime: intOf(body, 'startTime'),
        endTime: intOf(body, 'endTime'),
      ),
    );
  }
  int top(String key) {
    final m = RegExp('\\b$key\\s*=\\s*(-?\\d+)').firstMatch(text);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  return GiftCatalog(
    items: items,
    defaultTimes: top('select_times') > 0 ? top('select_times') : 1,
    dayIntimaciesLimit: top('day_intimacies_limit'),
  );
}

/// 从 visual-cfg `items` 解析 `道具ID → 名称 / 图标`。
///
/// 客户端没有游戏里的 `ItemDefCsv`，这份配置是能拿到的最接近的替代；
/// 字段名按游戏习惯（`ID`/`Name`/`Icon`/`Photo`/`url`）宽松匹配，
/// 解析不出来就返回空表 —— 调用方只显示「礼物 #id」。
Map<int, ({String name, String? icon})> parseItemDefs(String text) {
  final out = <int, ({String name, String? icon})>{};
  for (final body in allLuaBlocks(text)) {
    final idM = RegExp(r'\b(ID|id)\s*=\s*(\d+)').firstMatch(body);
    if (idM == null) continue;
    final nameM = RegExp(
      r"""\b(Name|name)\s*=\s*['"]([^'"]+)['"]""",
    ).firstMatch(body);
    if (nameM == null) continue;
    final iconM = RegExp(
      r"""\b(Icon|icon|Photo|photo|url)\s*=\s*['"]([^'"]+)['"]""",
    ).firstMatch(body);
    final id = int.tryParse(idM.group(2)!);
    if (id == null || id <= 0) continue;
    out[id] = (name: nameM.group(2)!, icon: iconM?.group(2));
  }
  return out;
}

/// 把目录与道具名/图标合并（礼品目录里的 id 就是道具 id）。
GiftCatalog mergeGiftNames(
  GiftCatalog catalog,
  Map<int, ({String name, String? icon})> defs,
) {
  if (defs.isEmpty) return catalog;
  return GiftCatalog(
    items: [
      for (final g in catalog.items)
        g.withMeta(
          name: defs[g.id]?.name,
          icon: defs[g.id]?.icon,
        ),
    ],
    defaultTimes: catalog.defaultTimes,
    dayIntimaciesLimit: catalog.dayIntimaciesLimit,
  );
}
