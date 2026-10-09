/// 玩家资料客户端 —— /miniw/profile/ 接口。
/// 移植自 MNClient `services/http_profile.py` (getProfileBatch3)。
/// 用途：批量拉取好友昵称/头像（friend_list 只返回 {mark,uin,relation}）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart' show httpGetS1Map;
import '../models/skin_head_catalog.dart' show headIconAsset;
import '../net/config.dart'
    show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart';
import '../net/photo_upload.dart' show uploadPresignedFile;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import 'gateway.dart' show buildMiniwParamMd5Url;
import 'request_errors.dart' show reportIfFailed;

/// 资料接口路径。
const String kProfilePath = 'miniw/profile/';

/// 玩家资料批量结果。
class PlayerProfile {
  final int uin;
  final String nickname;
  final String? avatarUrl;

  /// 头像框 id（RoleInfo.head_frame_id，对应 `assets/headframes/<id>.png`）。
  final int? headFrameId;

  /// 已拥有的头像框 id 集合（`profile.head_frames` + `head_frames_temp` 的 key）。
  /// 空集合表示响应未含该字段（**不等于**"没有头像框"）。
  final Set<int> ownedHeadFrameIds;

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）；由 getPersonCenterHeadInfo 单独填充。
  final int? headType;
  final int? headId;

  /// 穿戴中的角色皮肤 ID（`RoleInfo.SkinID`）；0/缺失归一为 null。
  /// 本地图标需经 `kSkinHeadIcon` 映射到 `roleicons/<Head>.png`。
  final int? headSkinId;

  /// 角色本体模型 ID（`RoleInfo.Model`，官方默认 2）；0/缺失归一为 null。
  /// 未穿皮肤时官方用它兜底 `roleicons/<Model>.png`。
  final int? headModel;

  const PlayerProfile({
    required this.uin,
    required this.nickname,
    this.avatarUrl,
    this.headFrameId,
    this.ownedHeadFrameIds = const {},
    this.headType,
    this.headId,
    this.headSkinId,
    this.headModel,
  });

  /// 角色头像本地回退解析（对齐官方 `headinfosysmgr.lua:GetPlayerHeadPath`）。
  ///
  /// 人物中心头信息（[headType]/[headId]）可用时原样返回；否则从资料字段
  /// 补一个可本地渲染的 (type,id)：
  /// - 可用的头类型：1（皮肤）/3（坐骑）/4（立绘）且 id>0——它们分别经
  ///   `roleicons/<kSkinHeadIcon[id]>.png`、`rideicons/<id>.png`、
  ///   `roleicons/<id>.png` 落到本地资源；
  /// - 不可用时优先 `RoleInfo.SkinID` → type 1（皮肤 ID 仍需映射到 Head 图标）；
  /// - 无皮肤再用 `RoleInfo.Model` → type 4（id 直接寻址 `roleicons/<model>.png`），
  ///   这正是官方在未穿皮肤时的角色本体兜底路径；
  /// - 都没有返回 null，由调用方保留原值（最终回退网络头像/首字占位）。
  ///
  /// 注意：**绝不产出 type 2**（头套是 3D 组合部件，没有 2D 图标；
  /// 产出它只会挡住网络头像回退，渲染不出任何东西）。
  static ({int type, int id})? resolveRoleHeadFallback({
    int? headType,
    int? headId,
    int? skinId,
    int? model,
  }) {
    if (headType != null &&
        (headType == 1 || headType == 3 || headType == 4) &&
        headId != null &&
        headId > 0) {
      return (type: headType, id: headId);
    }
    if (skinId != null && skinId > 0) return (type: 1, id: skinId);
    if (model != null && model > 0) return (type: 4, id: model);
    return null;
  }

  /// 角色头像本体是否有本地图标（`assets/roleicons|rideicons`）。
  ///
  /// 官方头像展示只有两个来源（`headinfosysmgr.lua:321-383` `GetPlayerHeadPath`）：
  /// DIY 自定义头像（`use_diy == 1` 时取 `diy_header.pass_url`／本人取 `pre_url`）
  /// 与角色头像本体（`type/id` → `ui/roleicons|ui/rideicons/*.png`）；
  /// **资料里的 `header*` 从不参与头像展示**（`header3` 只由 `set_usr_header3`
  /// 写入）。客户端原先无条件把 `header3/2/1` 当头像 URL，所以没有 DIY 的玩家
  /// 会被显示成"自定义头像"，而游戏里显示的是角色头像。
  ///
  /// 只有在角色头像确实有本地图标时才敢压过网络头像；否则宁可保留网络头像，
  /// 免得退成首字占位。
  static bool roleHeadHasLocalIcon(({int type, int id})? roleHead) =>
      roleHead != null && headIconAsset(roleHead.type, roleHead.id) != null;

  /// 从 getProfileBatch3 响应项解析。
  /// 结构（LuaTable）: {profile: {uin, RoleInfo: {NickName, ...},
  ///        header: {url}, header2: {url}, header3: {url}}, uin}
  ///
  /// **`header*` 不是头像**：实测 2026-10-08，`header`/`header2` 的值一律是
  /// `map<NNN>.mini1.cn/map/...` 的**地图截图**（自用与好友都一样），而真正的
  /// 自定义头像是 `getPersonCenterHeadInfo` 的 `diy_header.pass_url`
  /// （`prod-env-cloud-resshop.mini1.cn/resshop/<uin>/...png`）。所以这里不再把
  /// `header*` 当头像，头像一律由「DIY → 角色头像本体 → 首字占位」决定；
  /// 否则会把地图截图当成头像显示（用户反馈的"并不是自定义头像却显示成自定义头像"）。
  static PlayerProfile? fromItem(Map<String, Object?> item) {
    final profile = item['profile'];
    if (profile is! Map) return null;
    final p = profile.cast<String, Object?>();

    var uin2 = _firstInt(item, ['uin', 'Uin']);
    if (uin2 == 0) uin2 = _firstInt(p, ['uin', 'Uin']);
    if (uin2 == 0) return null;

    var nickname = '';
    var skinId = 0;
    var model = 0;
    // 反编译 friendservice.lua:RespPlayerDatas 证实：`head_frame_id` 在
    // **profile 层**（与 RoleInfo 同级），RoleInfo 里只有 NickName/SkinID/Model。
    // 此前误从 RoleInfo 里取，导致好友/会话列表的头像框永远为 null（不显示）。
    var headFrameId = _firstInt(p, ['head_frame_id', 'headFrameId']);
    final ri = p['RoleInfo'];
    if (ri is Map) {
      final r = ri.cast<String, Object?>();
      nickname = r['NickName']?.toString() ?? '';
      // 角色头像兜底数据（官方 GetPlayerHeadPath 的型号来源）。
      skinId = _firstInt(r, ['SkinID', 'skin_id', 'skinId', 'skinid']);
      model = _firstInt(r, ['Model', 'model']);
      // 兼容个别响应把字段放进 RoleInfo 的情况
      if (headFrameId == 0) {
        headFrameId = _firstInt(r, ['head_frame_id', 'headFrameId']);
      }
    }

    final avatar = _pickAvatar(p);

    return PlayerProfile(
      uin: uin2,
      nickname: nickname,
      // header* 已证实是地图截图而非头像，不再当头像用。
      avatarUrl: avatar,
      headFrameId: headFrameId <= 0 ? null : headFrameId,
      ownedHeadFrameIds: _parseOwnedFrames(p),
      headSkinId: skinId <= 0 ? null : skinId,
      headModel: model <= 0 ? null : model,
    );
  }

  /// 解析已拥有头像框集合（head_frames 永久 / head_frames_temp 限时）。
  ///
  /// 对齐反编译 `playercenter_new.lua:func_has_opened_head_frames`：
  /// `profile.head_frames[id]` 与 `head_frames_temp[id]` 存在即视为已拥有。
  static Set<int> _parseOwnedFrames(Map<String, Object?> p) {
    final out = <int>{};
    for (final key in const ['head_frames', 'head_frames_temp']) {
      final m = p[key];
      if (m is Map) {
        for (final k in m.keys) {
          final id = int.tryParse('$k');
          if (id != null && id > 0) out.add(id);
        }
      }
    }
    return out;
  }

  /// 头像 URL —— 恒为 null。
  ///
  /// 历史实现按 `header3 → header2 → header` 取「头像」；实测 2026-10-08 证明
  /// 这三个字段在服务器上放的是**地图截图**（`map<NNN>.mini1.cn/map/...`），
  /// 与头像无关。留这个函数只为说明链路：头像来源是
  /// `getPersonCenterHeadInfo`（DIY `pass_url` / 头像本体 `type`,`id`）。
  static String? _pickAvatar(Map<String, Object?> p) {
    return null;
  }

  static int _firstInt(Map<String, Object?> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }
}

/// 当前账号的"头像本体"信息（getPersonCenterHeadInfo / setPersonCenterHeadInfo）。
/// [type]: 1=皮肤 2=头套 3=坐骑 4=头像立绘。
class HeadInfo {
  final int type;
  final int id;
  const HeadInfo(this.type, this.id);
}

/// 玩家头像槽位（DIY 自定义头像 url + 头像本体 type/id）。
class HeadSlot {
  final String? diyUrl;
  final int? type;
  final int? id;
  const HeadSlot({this.diyUrl, this.type, this.id});
}

/// DIY 自定义头像的审核状态（对齐官方 `GetPlayerHeadPath`）。
///
/// 官方语义（`headinfosysmgr.lua:321-355`）：
///   - `aduit_fail == 1` → 审核失败（本人仍能看到 `pre_url`，他人看不到）；
///   - `pre_url` 非空 → 审核中（仅本人可见，官方本人优先展示它）；
///   - 否则 `pass_url` → 审核通过（所有人可见）。
enum DiyAuditState {
  /// 未上传过 DIY 头像（无 `diy_header` / 无 url）。
  none,

  /// 审核通过（`pass_url` 可用）。
  approved,

  /// 审核中（`pre_url` 仅本人可见）。
  pending,

  /// 审核失败（`aduit_fail == 1`）。
  failed,
}

/// 当前账号的 DIY 自定义头像状态（`getPersonCenterHeadInfo` 单条条目）。
///
/// `diy_header` 为**单个对象**（非列表），字段 `{pre_url, pass_url, aduit_fail}`
/// （`headinfosysmgr.lua:321-355`、`playercenterv2homepageview.lua:226-236`）；
/// 一个账号同时只有一张待审/已过审的 DIY 头像，因此 UI 的「自定义」至多一项。
class DiyHeadInfo {
  /// 审核通过的 URL（所有人可见）。
  final String? passUrl;

  /// 审核中的 URL（仅本人可见）。
  final String? preUrl;

  /// `aduit_fail == 1` → 审核失败。
  final bool auditFail;

  /// `use_diy == 1` → 当前正在使用 DIY 头像。
  final bool useDiy;

  /// 头像本体 type/id（DIY 之下的回退头像）。
  final int? type;
  final int? id;

  const DiyHeadInfo({
    this.passUrl,
    this.preUrl,
    this.auditFail = false,
    this.useDiy = false,
    this.type,
    this.id,
  });

  /// 审核状态。
  DiyAuditState get auditState {
    if (auditFail) return DiyAuditState.failed;
    if (_nonEmpty(preUrl) != null) return DiyAuditState.pending;
    if (_nonEmpty(passUrl) != null) return DiyAuditState.approved;
    return DiyAuditState.none;
  }

  /// 可展示 / 可选的 URL（审核失败时回退展示本人可见的 `pre_url`）。
  String? get displayUrl => _nonEmpty(preUrl) ?? _nonEmpty(passUrl);

  /// 是否可选为当前头像（审核失败时不可选，对齐 `Btn_useEditClick`）。
  bool get selectable => auditState != DiyAuditState.failed && displayUrl != null;

  /// 审核状态文案；`null` = 审核通过 / 无状态。
  String? get auditLabel {
    switch (auditState) {
      case DiyAuditState.failed:
        return '审核失败';
      case DiyAuditState.pending:
        return '审核中';
      case DiyAuditState.approved:
      case DiyAuditState.none:
        return null;
    }
  }
}

/// 取非空字符串；空 / null → null。
String? _nonEmpty(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

/// 解析单个 uin 的头信息条目 → [DiyHeadInfo]。
///
/// 对齐 `headinfosysmgr.lua:321-355` 与 `resolveDiyUrl`：`diy_header` 为单个
/// 对象；`aduit_fail == 1` 为审核失败。条目非 Map / 为空 → null。
DiyHeadInfo? parseDiyHeadInfo(Object? entry) {
  if (entry is! Map) return null;
  final info = entry.cast<String, Object?>();
  final diy = info['diy_header'];
  final type = info['type'];
  final id = info['id'];
  final useDiy = info['use_diy'] == 1 || info['use_diy'] == true;
  if (diy is! Map) {
    // 无 DIY 记录：仅保留本体 type/id 与 use_diy，供 UI 判断。
    if (type is! num && id is! num && !useDiy) return null;
    return DiyHeadInfo(
      useDiy: useDiy,
      type: type is num ? type.toInt() : null,
      id: id is num ? id.toInt() : null,
    );
  }
  final dh = diy.cast<String, Object?>();
  final fail = dh['aduit_fail'] == 1 || dh['aduit_fail'] == true;
  return DiyHeadInfo(
    passUrl: _nonEmpty(dh['pass_url']),
    preUrl: _nonEmpty(dh['pre_url']),
    auditFail: fail,
    useDiy: useDiy,
    type: type is num ? type.toInt() : null,
    id: id is num ? id.toInt() : null,
  );
}


/// 解析 DIY 自定义头像 URL（对齐反编译 `headinfosysmgr.lua:GetPlayerHeadPath`）。
///
/// 规则（[headInfo] 为响应中单个 uin 的条目，取其中的 `diy_header`）：
/// - `pass_url`（审核通过）对所有人可见，优先使用；
/// - `pre_url`（审核中）**仅本人可见**：他人视角必须忽略，否则好友会看到
///   自己"审核中"的头像，而官方客户端此时回退显示角色头像（type/id）；
/// - 两者都不可用时返回 null，由调用方回退到头像本体。
String? resolveDiyUrl(Map<String, Object?> headInfo, {required bool isSelf}) {
  final diy = headInfo['diy_header'];
  if (diy is! Map) return null;
  final dh = diy.cast<String, Object?>();
  final pass = dh['pass_url']?.toString();
  if (pass != null && pass.isNotEmpty) return pass;
  if (!isSelf) return null;
  final pre = dh['pre_url']?.toString();
  return (pre != null && pre.isNotEmpty) ? pre : null;
}

/// 已拥有的头像立绘（`miniw/business?act=query_portrait`）。
class PortraitItem {
  final int id;
  final int time; // -1=永久；>0=到期时间戳（秒）
  const PortraitItem({required this.id, this.time = -1});
}

class ProfileClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;
  final String ver;
  final String apiId;
  final String lang;
  final String country;

  ProfileClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
    this.ver = '1.58.0',
    this.apiId = '110',
    this.lang = '0',
    this.country = 'CN',
  })  : _dio = dio ?? createDio(),
        baseUrl =
            baseUrl ?? (kDefaultUrls['HttpMap'] ?? kDefaultBase);

  /// 批量拉取玩家资料（昵称/头像）。
  ///
  /// URL 构造（Python http_profile.py:_build_url）:
  ///   {HttpMap}miniw/profile/?act=getProfileBatch3&uin={uin}&op_uin_list={uins}
  ///   &ver=..&apiid=..&lang=..&country=..&time=X&auth=MD5(time+s2+uin)&s2t=Y
  ///
  /// 注意：响应是 **LuaTable 数组**（{[1]=..,[2]=..}），非 JSON——
  /// 用 decodeHttpResponse 解析（支持 LuaTable 顶层 List）。
  Future<List<PlayerProfile>> getProfileBatch3(List<int> uins) async {
    if (uins.isEmpty) return [];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final uinList = uins.map((u) => '$u').join(',');
    final url =
        '$base/$kProfilePath?act=getProfileBatch3&uin=$uin&op_uin_list=$uinList'
        '&ver=$ver&apiid=$apiId&lang=$lang&country=$country&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);

    // LuaTable 数组 → List；{code,data:[...]} → data
    Object? data = decoded;
    if (data is Map) {
      if (data['data'] is List) data = data['data'];
    }
    if (data is! List) return [];

    final out = <PlayerProfile>[];
    for (final item in data) {
      if (item is Map) {
        final p = PlayerProfile.fromItem(item.cast<String, Object?>());
        if (p != null) out.add(p);
      }
    }
    return out;
  }

  /// 批量拉取玩家**DIY 自定义头像**（游戏内主界面头像来源）。
  ///
  /// 反编译 `headinfosysmgr.lua:ReqPlayerHeadInfo`:
  ///   `{HttpMap}miniw/profile?act=getPersonCenterHeadInfo&uin={me}&op_uin_list={uins}&…&{sign}`
  ///   （**必须带 `uin`**：2026-10-08 实测缺 `uin` 时服务端回空 body）
  /// 响应结构: `{code:0, data:{ "<uin>": {use_diy, diy_header:{pre_url, pass_url, aduit_fail}, ...} }}`
  /// 返回 Map&lt;uin, DIY头像URL&gt;（仅 use_diy==1 且解析出可用 url；其中
  /// `pre_url` 审核中头像仅本人可见，见 [resolveDiyUrl]）。
  /// 头像接口单次请求的 uin 上限（实测 2026-10-09）。
  ///
  /// 请求 45 / 49 / 50 个 → 全回；请求 51 / 60 / 100 / 164 个 → **只回前 50 条**，
  /// 其余静默丢失（对丢掉的人单独再问一次就有数据）。所以批量口一律在客户端分片。
  static const int kHeadInfoBatchSize = 50;

  /// 按 [kHeadInfoBatchSize] 切片（空列表 → 不产生任何批）。
  Iterable<List<int>> _headInfoBatches(List<int> uins) sync* {
    for (var i = 0; i < uins.length; i += kHeadInfoBatchSize) {
      yield uins.sublist(i, (i + kHeadInfoBatchSize).clamp(0, uins.length));
    }
  }

  Future<Map<int, String?>> getPersonCenterHeadInfo(List<int> uins) async {
    final out = <int, String?>{};
    for (final batch in _headInfoBatches(uins)) {
      try {
        out.addAll(await _headInfoDiyOnce(batch));
      } catch (_) {
        // 单批失败不阻断其它批（该批退到角色头像本体 / 首字）
      }
    }
    return out;
  }

  /// 单批（≤ [kHeadInfoBatchSize]）取 DIY 头像 url。
  Future<Map<int, String?>> _headInfoDiyOnce(List<int> uins) async {
    final out = <int, String?>{};
    if (uins.isEmpty) return out;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final uinList = uins.map((u) => '$u').join(',');
    // 必须带 uin：实测（2026-10-08）缺 uin 时服务端回**空 body**（长度 0），
    // 加回 uin（连同全局参数）才回 {code:0,data:{…}}。这条静默失败让好友头像的
    // 「头像本体 / DIY 自定义头像」一直取不到（好友头像只能退回头像本体推导或首字）。
    final url =
        '$base/miniw/profile?act=getPersonCenterHeadInfo&uin=$uin&op_uin_list=$uinList'
        '&ver=$ver&apiid=$apiId&lang=$lang&country=$country&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);

    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) return out;

    for (final e in data.entries) {
      final u = int.tryParse('${e.key}');
      if (u == null || e.value is! Map) continue;
      final info = (e.value as Map).cast<String, Object?>();
      // 未开启 DIY 头像则跳过
      if (info['use_diy'] != 1) continue;
      // pass_url=审核通过（所有人可见）；pre_url=审核中（仅本人可见，见 resolveDiyUrl）。
      out[u] = resolveDiyUrl(info, isSelf: u == uin);
    }
    return out;
  }

  /// 拉取当前账号完整资料（含已拥有头像框集合）。
  ///
  /// 反编译 `playerexhibitioncenter.lua:GetPlayerProfileByUin`:
  ///   `{HttpMap}miniw/profile?act=getProfile&op_uin={uin}&pop=1&{sign}`
  /// 响应 `{ret?, profile:{RoleInfo, head_frame_id, head_frames, header,...}}`。
  /// 缺少 `profile`（或 `ret==1` 私密/异常）时返回 null。
  Future<PlayerProfile?> getMyProfile() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final url = '$base/miniw/profile?act=getProfile&op_uin=$uin&pop=1&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    if (decoded is! Map) return null;
    final m = decoded.cast<String, Object?>();
    // 兼容两种信封：`{profile:{...}}` 与 `{data:{profile:{...}}}`（不同网关/版本
    // 会不一样）。此前只认前者，取不到时整个资料为 null，导致头像框选择器
    // 只剩默认框 1（用户反馈「只显示一个头像框」）。
    Object? rawProfile = m['profile'];
    final data = m['data'];
    if (rawProfile is! Map && data is Map) {
      rawProfile = (data.cast<String, Object?>())['profile'];
    }
    if (rawProfile is! Map) return null;
    return PlayerProfile.fromItem(<String, Object?>{
      'uin': uin,
      'profile': rawProfile,
    });
  }

  /// 设置当前账号头像框。
  ///
  /// 反编译 `playercenter_new.lua:WWW_setPlayerFrameId`:
  ///   `{HttpMap}miniw/profile?act=setProfile&head_frame_id={id}&{sign}`
  /// 响应 `{ret:0}` 表示成功。
  Future<bool> setHeadFrame(int frameId) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final url =
        '$base/miniw/profile?act=setProfile&head_frame_id=$frameId&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    if (decoded is Map) {
      final ret = decoded['ret'];
      if (ret is num) return ret.toInt() == 0;
    }
    return false;
  }

  /// 拉取当前账号的"头像本体"（type/id）。
  ///
  /// 反编译 `headinfosysmgr.lua:ReqPlayerHeadInfo`:
  ///   `{HttpMap}miniw/profile?act=getPersonCenterHeadInfo&uin={uin}&op_uin_list={uin}&…&{sign}`
  /// 响应 `{code:0, data:{"<uin>": {type, id, use_diy, diy_header, ...}}}`。
  /// （缺 `uin` 时服务端回空 body。）
  Future<HeadInfo?> getMyHeadInfo() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final url =
        '$base/miniw/profile?act=getPersonCenterHeadInfo&uin=$uin&op_uin_list=$uin'
        '&ver=$ver&apiid=$apiId&lang=$lang&country=$country&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    if (decoded is! Map) return null;
    final data = decoded['data'];
    if (data is! Map) return null;
    final info = data['$uin'];
    if (info is! Map) return null;
    final m = info.cast<String, Object?>();
    final type = m['type'];
    final id = m['id'];
    if (type is num && id is num) return HeadInfo(type.toInt(), id.toInt());
    return null;
  }

  /// 设置"头像本体"（皮肤/头套/坐骑/立绘）。
  ///
  /// 反编译 `headinfosysmgr.lua:ReqSetPlayerHeadInfo`:
  ///   `{HttpMap}miniw/profile?act=setPersonCenterHeadInfo&HeadInfo={urlencoded json}&use_diy=0&{sign}`
  /// 响应 `{code:0}` 表示成功。
  Future<bool> setHeadInfo({
    required int type,
    required int id,
    int? endTime,
    bool useDiy = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final headJson = jsonEncode({
      'type': type,
      'id': id,
      'endTime': ?endTime,
    });
    final ctx = Uri.encodeQueryComponent(headJson);
    // `use_diy=1` 表示启用 DIY 自定义头像（对齐 `headinfosysmgr.lua:540-544`）。
    final url =
        '$base/miniw/profile?act=setPersonCenterHeadInfo'
        '&HeadInfo=$ctx&use_diy=${useDiy ? 1 : 0}&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    if (decoded is Map) {
      final code = decoded['code'];
      if (code is num) return code.toInt() == 0;
    }
    return false;
  }

  /// 批量取「头像展示数据」（资料 + 头像本体 / DIY 自定义头像）。
  ///
  /// 给那些只拿到 uin 的列表（家族成员 / 好友申请 / 黑名单…）用：一次性把
  /// `getProfileBatch3`（昵称 / 头像框 / 皮肤 / 模型）与
  /// `getPersonCenterHeadInfo`（DIY 头像 / 头像本体 type,id）合起来，按与好友
  /// 列表**同一条规则**给出头像：DIY 自定义头像 > 角色头像本体（本机有图标时）
  /// > 首字占位（`headinfosysmgr.lua:321-383`）。
  ///
  /// 返回的 [PlayerProfile.headType]/[headId] 已填好，UI 直接：
  /// `AvatarView(name: p.nickname, avatarUrl: p.avatarUrl, headType: p.headType,
  /// headId: p.headId, frameId: p.headFrameId)`。
  /// 单个接口失败不影响另一个；全失败时条目头像一个字段都不给（退首字）。
  Future<Map<int, PlayerProfile>> fetchAvatarProfiles(List<int> uins) async {
    final out = <int, PlayerProfile>{};
    if (uins.isEmpty) return out;
    final profiles = <int, PlayerProfile>{};
    final heads = <int, HeadSlot>{};
    try {
      for (final p in await getProfileBatch3(uins)) {
        profiles[p.uin] = p;
      }
    } catch (_) {
      // 资料失败：只剩头像本体 / 首字
    }
    try {
      heads.addAll(await getPersonCenterHeadInfos(uins));
    } catch (_) {
      // 头像本体失败：只剩资料 / 首字
    }
    for (final u in uins) {
      final p = profiles[u];
      final head = heads[u];
      final fallback = PlayerProfile.resolveRoleHeadFallback(
        headType: head?.type,
        headId: head?.id,
        skinId: p?.headSkinId,
        model: p?.headModel,
      );
      final useDiy = head?.diyUrl != null;
      // 注意：角色头像本体**必须保留** headType/headId —— AvatarView 靠它们
      // 去查本地图标（`headIconAsset`）；只有 DIY 生效时才清空本体。
      out[u] = PlayerProfile(
        uin: u,
        nickname: p?.nickname ?? '',
        avatarUrl: useDiy ? head!.diyUrl : p?.avatarUrl,
        headType: useDiy ? null : fallback?.type,
        headId: useDiy ? null : fallback?.id,
        headFrameId: p?.headFrameId,
        headSkinId: p?.headSkinId,
        headModel: p?.headModel,
      );
    }
    return out;
  }

  /// 批量拉取"头像槽位"（DIY 头像 url + 头像本体 type/id）。
  ///
  /// 反编译 `headinfosysmgr.lua:ReqPlayerHeadInfo`。响应
  /// `{code:0, data:{"<uin>": {type, id, use_diy, diy_header:{pre_url,pass_url}}}}`。
  Future<Map<int, HeadSlot>> getPersonCenterHeadInfos(List<int> uins) async {
    final out = <int, HeadSlot>{};
    for (final batch in _headInfoBatches(uins)) {
      try {
        out.addAll(await _headSlotsOnce(batch));
      } catch (_) {
        // 单批失败不阻断其它批（该批退到角色头像本体 / 首字）
      }
    }
    return out;
  }

  /// 单批（≤ [kHeadInfoBatchSize]）取头像槽位。
  Future<Map<int, HeadSlot>> _headSlotsOnce(List<int> uins) async {
    final out = <int, HeadSlot>{};
    if (uins.isEmpty) return out;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final uinList = uins.map((u) => '$u').join(',');
    // 同 getPersonCenterHeadInfo：必须带 uin，否则服务端回空 body。
    final url =
        '$base/miniw/profile?act=getPersonCenterHeadInfo&uin=$uin&op_uin_list=$uinList'
        '&ver=$ver&apiid=$apiId&lang=$lang&country=$country&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) return out;

    for (final e in data.entries) {
      final u = int.tryParse('${e.key}');
      if (u == null || e.value is! Map) continue;
      final info = (e.value as Map).cast<String, Object?>();
      String? diy;
      if (info['use_diy'] == 1) {
        // 同 getPersonCenterHeadInfo：pre_url（审核中）仅本人可见。
        diy = resolveDiyUrl(info, isSelf: u == uin);
      }
      final type = info['type'];
      final id = info['id'];
      out[u] = HeadSlot(
        diyUrl: diy,
        type: type is num ? type.toInt() : null,
        id: id is num ? id.toInt() : null,
      );
    }
    return out;
  }

  /// 拉取当前账号的 DIY 自定义头像状态（`diy_header` + `use_diy`）。
  ///
  /// 复用 `getPersonCenterHeadInfo` 的端点（`headinfosysmgr.lua:194-199`），
  /// 但保留完整 `diy_header` 审核字段（`pre_url`/`pass_url`/`aduit_fail`），
  /// 供「头像编辑 → 自定义」展示审核态。无条目 → null。
  Future<DiyHeadInfo?> getMyDiyHeadInfo() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    // 同 getPersonCenterHeadInfo：必须带 uin，否则服务端回空 body。
    final url =
        '$base/miniw/profile?act=getPersonCenterHeadInfo&uin=$uin&op_uin_list=$uin'
        '&ver=$ver&apiid=$apiId&lang=$lang&country=$country&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) return null;
    return parseDiyHeadInfo(data['$uin']);
  }

  /// 预上传 DIY 头像：GET `miniw/profile?act=upload_pre_photo`。
  ///
  /// 对齐 `http.lua:1771-1783` `upload_md5_file_pre`：URL = `act=upload_pre_photo`
  /// + `http_getS1Map()`。响应为字符串 `ok:<上传目标 URL>`，返回去掉 `ok:`
  /// 前缀的上传 URL；失败 / 非 `ok:` → null。
  ///
  /// 注意：游戏走 `ns_http.func.rpc_string`，它会再过一遍 `url_addParams`
  /// （`http.lua:891`）—— 所以真实请求必须带 `uin/apiid/ver/country/lang`。
  /// 实测缺这些参数时服务端回 **空 body**（http 200），补上才回 `ok:<url>`。
  Future<String?> uploadPrePhoto() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final url = '$base/miniw/profile?act=upload_pre_photo&uin=$uin'
        '&apiid=$kApiId&ver=$kClientVersionStr&country=CN&lang=0&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : '${resp.data}';
    final t = text.trim();
    if (!t.startsWith('ok:')) return null;
    final u = t.substring(3).trim();
    return u.isEmpty ? null : u;
  }

  /// 上传 DIY 头像图片字节到 [uploadUrl]（[uploadPrePhoto] 的返回值）。
  ///
  /// 对齐 `http.lua:1784-1818` `upload_md5_file`（内部 `MiniHttp.CustomUpload`）——
  /// 线格式按真实抓包（2026-10-06）复刻，见 [uploadPresignedFile]：分片
  /// multipart，`act=info` → `upload_begin` → `upload_step`×N → `upload_end`。
  /// 成功时 `upload_end` 回 `ok:<确认 token>`，返回去前缀 token；否则 null。
  Future<String?> uploadDiyPhoto(
    String uploadUrl,
    List<int> bytes, {
    required String fileMd5,
    required String ext,
  }) =>
      uploadPresignedFile(
        _dio,
        uploadUrl,
        bytes,
        fileMd5: fileMd5,
        ext: ext,
      );

  /// 确认 DIY 头像：GET `miniw/profile?act=set_usr_header3`。
  ///
  /// 对齐 `http.lua:1972-1989` `set_user_profile_head3`：
  /// `act=set_usr_header3&<token>&md5=<文件 md5>&ext=<扩展名>&http_getS1Map()`；
  /// 响应 `{ret:0}` 表示成功。
  ///
  /// 同 [uploadPrePhoto]：游戏走 `rpc_string` → `url_addParams`，真实请求必须带
  /// `uin/apiid/ver/country/lang`（缺了服务端回空 body）。
  Future<bool> confirmDiyHeader({
    required String token,
    required String fileMd5,
    required String ext,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final url =
        '$base/miniw/profile?act=set_usr_header3&uin=$uin'
        '&apiid=$kApiId&ver=$kClientVersionStr&country=CN&lang=0'
        '&$token&md5=$fileMd5&ext=$ext&$sign';

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    if (decoded is Map) {
      final ret = decoded['ret'] ?? decoded['code'];
      if (ret is num) return ret.toInt() == 0;
    }
    return false;
  }

  /// 一步上传 DIY 头像：预上传 → 上传字节 → 确认。
  ///
  /// [fileName] 仅用于取扩展名（默认 png）。任一步失败返回 false。
  Future<bool> uploadDiyAvatar(
    List<int> bytes, {
    String fileName = 'head.png',
  }) async {
    final uploadUrl = await uploadPrePhoto();
    if (uploadUrl == null) return false;
    final dot = fileName.lastIndexOf('.');
    final ext = dot >= 0 ? fileName.substring(dot + 1) : 'png';
    final md5 = crypto.md5.convert(bytes).toString();
    final token = await uploadDiyPhoto(
      uploadUrl,
      bytes,
      fileMd5: md5,
      ext: ext,
    );
    if (token == null) return false;
    return confirmDiyHeader(token: token, fileMd5: md5, ext: ext);
  }

  /// 已拥有头像立绘列表（`miniw/business?act=query_portrait`）。
  ///
  /// 反编译 `headinfosysmgr.lua:ReqPlayerHeadData`。响应 `{data:[{id,time},...]}`
  /// 或 `{data:{...}}`；`time==-1` 永久，`>0` 为到期时间戳。
  Future<List<PortraitItem>> getOwnedPortraits() async {
    // 走共享构造器：真机请求会带上 uin/ver/apiid/lang/country/server_ts 全局参数
    // （见 buildMiniwParamMd5Url），漏掉会 400 或 md5 对不上。
    final url = buildMiniwParamMd5Url(
      baseUrl: baseUrl,
      path: '/miniw/business',
      params: const {'act': 'query_portrait'},
      uin: uin,
      s2: s2,
      s2t: s2t,
    );

    final resp = await _dio.get(url);
    final text = resp.data is String ? resp.data as String : jsonEncode(resp.data);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    final data = decoded is Map ? decoded['data'] : null;

    final out = <PortraitItem>[];
    void add(Object? e) {
      if (e is! Map) return;
      final m = e.cast<String, Object?>();
      final id = m['id'];
      if (id is! num || id.toInt() <= 0) return;
      final t = m['time'];
      out.add(PortraitItem(id: id.toInt(), time: t is num ? t.toInt() : -1));
    }

    if (data is List) {
      data.forEach(add);
    } else if (data is Map) {
      data.values.forEach(add);
    }
    return out;
  }
}
