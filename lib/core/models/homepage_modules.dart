/// 玩家主页（`get_user_homepage`）模块的纯解析函数。
///
/// 主页响应是 `{模块名: {data: {...}}}` 的松散结构，且同一字段在不同接口间
/// 类型不一致（数字 / 数字字符串混用）。这里收敛 UI 需要的模块：
///   - `role_info`（模块 1）：关注 / 粉丝 / 人气值 / 信用分统计；
///   - `posting`（模块 3）：动态数量；
///   - `skin`（模块 4）：已拥有皮肤 / 坐骑 / 武器 / 座位（个性装扮）；
///   - `avatar_collect`（模块 5）：追光计划收集数（`data.count`）；
///   - `achieve`（模块 6）：勋章列表（`data.medal_list` → `[(id, level)]`）；
///   - `head_frame`（模块 7）：已拥有头像框数量；
///   - `charm`（模块 8）：魅力值（`data.charm_value`）；
///   - `title`（模块 9）：当前佩戴称号 id（`data.match_title.use_title.id`）；
///   - `map`（模块 11）：发布作品数量与列表；
///   - `achieve2`（模块 13）：勋章列表（`data` 为数组，`[(id, level)]`）；
///   - `social_sign`（模块 16）：交友宣言（`{social_lab, game_lab}`）。
///
/// 另有两个主页卡片不来自 `get_user_homepage`，而是独立接口，故解析器直接
/// 接收完整响应（含 `code`）：
///   - `我的收藏夹`：`miniw/favorite?act=get_collect_ids`（[favoriteFolderCount]）；
///   - `迷你印迹`：`miniw/camera?act=get_photo_homepage`（[multimediaImprintCount]）。
///
/// 解析口径与 `ui/widgets/session_player_info_popup.dart`、
/// `ui/player_home_page.dart` 中既有的私有实现保持一致（那两处的辅助函数为
/// 私有且不在本次改动范围，故此处收敛为可单测的公开函数）。
///
/// 约定（与仓库内其它解析器一致）：任何脏数据（非 Map / 缺字段 / 类型不符 /
/// 非正 id）只跳过，**绝不抛异常**；取不到时返回 `0` / 空列表 / `null`，
/// 由调用方自行降级为「—」占位。计数类解析器返回 `int?`：`null` 表示该模块
/// 缺失（或结构不符），`0` 表示模块存在但计数确为 0，二者在 UI 上区分展示。
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

/// 数字容错（可空版）：`int` / `num` / 数字字符串 → `int`，其余 → `null`。
int? _toOptInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

/// 取模块的 `data` 子 map；模块缺失 / 非 Map / `data` 非 Map → `null`。
Map<String, Object?>? _moduleDataMap(Map<String, Object?>? home, String module) {
  final m = home?[module];
  if (m is! Map) return null;
  final data = m['data'];
  return data is Map ? data.cast<String, Object?>() : null;
}

/// 魅力值（`charm` 模块 8）：`charm.data.charm_value`。
///
/// 依据 `playerCenterV2CharmCompModel:GetCharmVal`：
/// `return self.data.charmInfo.charm_value or 0`
/// （`playercenterv2charmcompmodel.lua:67-69`；ctrl 取 `serverData.data`
/// 于 `playercenterv2charmcompctrl.lua:110`）。模块缺失 → `null`。
int? homepageCharmValue(Map<String, Object?>? home) {
  final data = _moduleDataMap(home, 'charm');
  if (data == null) return null;
  return _toOptInt(data['charm_value']);
}

/// 发布作品数量（`map` 模块 11）：地图数 + 资源商品总数。
///
/// 依据 `playerCenterV2MapCompModel:TransferMapInfo`
/// （`playercenterv2mapcompmodel.lua:29-94`）：
/// `map_list` 逐条计入（`:30-45`）；`serverData.goods_count.total` 为资源总数
/// （`:72-74`）；`goods` 内层 `data.list` 为兜底（`:76-89`）。
/// 模块缺失 → `null`。
int? homepageWorkCount(Map<String, Object?>? home) {
  final data = _moduleDataMap(home, 'map');
  if (data == null) return null;
  var total = 0;
  final mapList = data['map_list'];
  if (mapList is List) total += mapList.whereType<Map>().length;
  final goodsCount = data['goods_count'];
  if (goodsCount is Map) {
    total += _toOptInt(goodsCount['total']) ?? 0;
  } else {
    final goods = data['goods'];
    if (goods is Map) {
      for (final v in goods.values) {
        if (v is! Map) continue;
        final inner = v['data'];
        if (inner is Map && inner['list'] is List) {
          total += (inner['list'] as List).whereType<Map>().length;
        }
      }
    }
  }
  return total;
}

/// 发布作品名称列表（`map.data.map_list`）。
///
/// 依据 `playerCenterV2MapCompModel:TransferMapInfo`
/// （`playercenterv2mapcompmodel.lua:30-45`）：每条 `{id, name, ctype,
/// create_time, top}`，`id <= 0` 的脏条目跳过。
List<HomeWork> homepageWorks(Map<String, Object?>? home) {
  final data = _moduleDataMap(home, 'map');
  if (data == null) return const <HomeWork>[];
  final list = data['map_list'];
  if (list is! List) return const <HomeWork>[];
  final out = <HomeWork>[];
  for (final e in list) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final id = _toInt(m['id'] ?? m['ID']);
    if (id <= 0) continue;
    final name = '${m['name'] ?? ''}'.trim();
    out.add(HomeWork(id: id, name: name.isEmpty ? '#$id' : name));
  }
  return out;
}

/// 动态数量（`posting` 模块 3）。
///
/// 优先取 `posting.data.posting_count`（`playercenterv2dynamicview.lua:120`
/// / `:156` 直接展示该字段）；缺失时按 `playerCenterV2DynamicCtrl:GetCount`
/// （`playercenterv2dynamicctrl.lua:101-117`）统计 `posting_data.list` 中
/// `homepage_hide ~= 1` 的条目。模块缺失 → `null`。
int? homepagePostingCount(Map<String, Object?>? home) {
  final data = _moduleDataMap(home, 'posting');
  if (data == null) return null;
  final count = _toOptInt(data['posting_count']);
  if (count != null) return count;
  final posting = data['posting_data'];
  if (posting is! Map) return 0;
  final list = posting['list'];
  if (list is! List) return 0;
  var n = 0;
  for (final e in list) {
    if (e is! Map) continue;
    if (_toInt(e['homepage_hide']) != 1) n++;
  }
  return n;
}

/// 追光计划收集数（`avatar_collect` 模块 5）：`data.count`。
///
/// 依据 `playerCenterV2DressGalleryView:SetSmallComponent`
/// （`playercenterv2dressgalleryview.lua:60-61`）：
/// `local curScore = serverData.data.count or 0`；`standName` 亦将该模块记为
/// `ChaseLight`（`playercenterv2config.lua:291`）。模块缺失 → `null`。
int? homepageChaseLightCount(Map<String, Object?>? home) {
  final data = _moduleDataMap(home, 'avatar_collect');
  if (data == null) return null;
  return _toOptInt(data['count']);
}

/// 个性装扮（已拥有）数量（`skin` 模块 4）。
///
/// 依据 `playerCenterV2MiniShowCompModel:SetSkinInfo`
/// （`playercenterv2minishowcompmodel.lua:35-172`）：统计
/// `data.skin_list`（`:51`）、`data.seat.seat_list`（`:88-89`）、
/// `data.mount_list`（`:126`）、`data.weapon_list`（`:145`）四项。模块缺失 → `null`。
int? homepageSkinCount(Map<String, Object?>? home) {
  final data = _moduleDataMap(home, 'skin');
  if (data == null) return null;
  var n = 0;
  final skinList = data['skin_list'];
  if (skinList is List) n += skinList.whereType<Map>().length;
  final mountList = data['mount_list'];
  if (mountList is List) n += mountList.whereType<Map>().length;
  final weaponList = data['weapon_list'];
  if (weaponList is List) n += weaponList.whereType<Map>().length;
  final seat = data['seat'];
  if (seat is Map && seat['seat_list'] is List) {
    n += (seat['seat_list'] as List).whereType<Map>().length;
  }
  return n;
}

/// 已拥有头像框数量（`head_frame` 模块 7）。
///
/// 依据 `playerCenterV2HeadFrameCompModel:SetHeadFrameInfo`
/// （`playercenterv2headframecompmodel.lua:13-14`）：`self.headFrameList = data`
/// 后按 `ipairs` 遍历（`:28`），即 `data` 为数组。模块缺失 → `null`。
int? homepageHeadFrameCount(Map<String, Object?>? home) {
  final m = home?['head_frame'];
  if (m is! Map) return null;
  final data = m['data'];
  if (data is! List) return null;
  return data.whereType<Map>().length;
}

/// 勋章列表（`achieve2` 模块 13）：`data` 为数组，逐条 `{id, max_level, level}`。
///
/// 依据 `playerCenterV2MedalCompCtrl:SetServerData`
/// （`playercenterv2medalcompctrl.lua:134`：`for _, value in ipairs(serverData)`）
/// 与 `playerCenterV2MedalCompModel:SetMedalInfo`
/// （`playercenterv2medalcompmodel.lua:20-23`：`max_level > 0` 时
/// `value.level = value.max_level`）。`id <= 0` 的脏条目跳过。
List<(int, int)> homepageMedals2(Map<String, Object?>? home) {
  final m = home?['achieve2'];
  if (m is! Map) return const <(int, int)>[];
  final data = m['data'];
  if (data is! List) return const <(int, int)>[];
  final out = <(int, int)>[];
  for (final e in data) {
    if (e is! Map) continue;
    final mm = e.cast<String, Object?>();
    final id = _toInt(mm['id'] ?? mm['ID']);
    if (id <= 0) continue;
    final maxLevel = _toInt(mm['max_level'] ?? mm['maxLevel']);
    final level = maxLevel > 0
        ? maxLevel
        : _toInt(mm['level'] ?? mm['Level']);
    out.add((id, level));
  }
  return out;
}

/// 顶部四项统计（`role_info` 模块 1）。
///
/// 字段依据：
///   - 关注 `role_info.data.profile.relation.friend_attention`
///     （`playercenterv2homepageview.lua:197-203`）；
///   - 粉丝 `role_info.data.profile.relation.friend_beattention`
///     （`playercenterv2homepageview.lua:154-160`）；
///   - 人气值 `role_info.data.popularity`
///     （`playercenterv2popularctrl.lua:36`）；
///   - 信用分 `role_info.data.credit`
///     （`playercenterv2homepageview.lua:171-181`）。
///
/// `role_info` 缺失 → `null`；单项缺失时该字段为 `null`（与真实的 0 区分）。
HomeStats? homepageStats(Map<String, Object?>? home) {
  final role = home?['role_info'];
  if (role is! Map) return null;
  final data = role['data'];
  if (data is! Map) return null;
  final d = data.cast<String, Object?>();
  final profile = d['profile'];
  final relation = profile is Map ? profile['relation'] : null;
  final rel = relation is Map
      ? relation.cast<String, Object?>()
      : const <String, Object?>{};
  return HomeStats(
    following: _toOptInt(rel['friend_attention']),
    followers: _toOptInt(rel['friend_beattention']),
    popularity: _toOptInt(d['popularity']),
    credit: _toOptInt(d['credit']),
  );
}

/// 独立接口响应的列表计数（`ret.data.list`）。
///
/// 约定：`ret` 非 Map / `code`(或 `ret`) 非 0 / `data` 非 Map → `null`（请求
/// 失败，UI 降级为「—」）；`list` 为 Map（映射）或 List（数组）→ 其条目数；
/// `list` 缺失 → `0`（请求成功但为空）；`list` 类型不符 → `null`（脏数据）。
int? _responseListCount(Object? ret) {
  if (ret is! Map) return null;
  final code = _toOptInt(ret['code'] ?? ret['ret']);
  if (code != null && code != 0) return null;
  final data = ret['data'];
  if (data is! Map) return null;
  final list = data['list'];
  if (list is Map) return list.length;
  if (list is List) return list.length;
  if (list == null) return 0;
  return null;
}

/// 我的收藏夹数量（`miniw/favorite?act=get_collect_ids`）。
///
/// 依据 `ContentFavsService:ReqPlayerCreatedData`
/// （`contentfavsservice.lua:205-209`：`rpc("get_collect_ids", {op_uin=desUin})`，
/// URL 根 `miniw/favorite` 见同文件 `:23`；本人与查看他人均走此接口，
/// 见 `contentfavsdata.lua:98-140` 的 `InitMineCreateData`）——
/// `ContentFavsData:LoadPlayerCreateData` 取 `(retTable.data or {}).list or {}`
/// （`contentfavsdata.lua:525-543`），该 `list` 为「收藏夹 id → 收藏夹数据」的
/// 映射；官方在 `playercenterv2contentfavscompctrl.lua:137-182` 对 `pairs(data)`
/// 逐条收集后以 `#self.dataList` 展示（计数见 `:167`）。
///
/// [ret] 为完整响应；失败 / 脏数据 → `null`，成功但无收藏夹 → `0`。
int? favoriteFolderCount(Object? ret) => _responseListCount(ret);

/// 迷你印迹数量（`miniw/camera?act=get_photo_homepage`）。
///
/// 依据 `MultimediaAlbumService:ReqPlayerCenterPhotoData`
/// （`multimediaalbumservice.lua:255-261`：`rpc("get_photo_homepage",
/// {page=1, page_size=1000, op_uin=desUin})`；URL 根 `miniw/camera` 见同文件
/// `:26-31` 的 `GetBaseUrl`）——主页组件固定请求照片类型
/// （`playercenterv2multimediacompctrl.lua:158-173` 取 `defMediaType.photo`），
/// `MultimediaAlbumData:LoadPlayerCenterData` 取 `(retTable.data or {}).list or {}`
/// （`multimediaalbumdata.lua:5200-5233`），该 `list` 为照片数组，数量即条目数。
///
/// [ret] 为完整响应；失败 / 脏数据 → `null`，成功但无印迹 → `0`。
int? multimediaImprintCount(Object? ret) => _responseListCount(ret);

/// 一条已发布作品（`map.data.map_list` 条目）。
class HomeWork {
  /// 作品（地图）id。
  final int id;

  /// 作品名（缺失时回退 `#id`）。
  final String name;

  const HomeWork({required this.id, required this.name});
}

/// 个人主页顶部四项统计；`null` 字段表示该项未下发。
class HomeStats {
  /// 关注数（`friend_attention`）。
  final int? following;

  /// 粉丝数（`friend_beattention`）。
  final int? followers;

  /// 人气值（`popularity`）。
  final int? popularity;

  /// 信用分（`credit`）。
  final int? credit;

  const HomeStats({
    this.following,
    this.followers,
    this.popularity,
    this.credit,
  });
}
