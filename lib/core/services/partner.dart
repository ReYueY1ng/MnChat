/// 最佳拍档 / 玩家等级 / 大会员服务客户端。
///
/// 覆盖好友面板所需的只读数据与写操作：
///   - 平台等级批量：`miniw/upgrade?act=get_level_info_batch`
///   - **拍档列表（含默契度）**：`miniw/bestpartner?act=get_list`（s7 包裹，
///     见 [bestpartnerUrl]；响应里非拍档好友也在）
///   - 拍档槽位：`miniw/bestpartner?act=get_bestpartner_data`
///   - 红点：`miniw/bestpartner?act=get_red_dot_info`
///   - 大会员（本人）：`miniw/business?act=vip_get_data`
///   - 大会员（他人批量）：`miniw/business?act=vip_get_uinlst_vipdata`
///   - 写操作：`set_bestpartner_title` / `unlock_bestpartnet_pos` / `apply`
///
/// 签名与 [PlayerHomeClient] 一致（http_getParamMD5）。所有解析器均为纯函数、
/// 对脏数据只跳过不抛异常；非 0 的 `code`/`ret` 一律视为失败返回空值。
///
/// 关系等级阈值（`tacitnum` 对应的 `FriendSystem.levelIntimacy.partnerLevel_list`）
/// 由服务端 visual-cfg 下发：与 [TitleConfigClient] 同源，先取
/// `miniw/ma/configIndex.lua` 中 `FriendSystem` 的 md5，再取 `miniw/ma/<md5>.lua`
/// 解析（见 [PartnerClient.getPartnerLevels]）。拉取失败 → 阈值缺失，UI 不画
/// 进度条（见 [RelationProgress]），绝不硬编码阈值。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart' show md5Sign, md5Token;
import '../crypto/s7_sign.dart' show encodeS7Url;
import 'gateway.dart' show buildMiniwParamMd5Url;
import '../net/config.dart'
    show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart'
    show decodeHttpResponse, LuaTableDecodeError;
import 'request_errors.dart' show RequestErrorBus;
import '../utils/log.dart';
import '../utils/request_cache.dart' show RequestCache;
import 'config_text_cache.dart';
import 'title_config.dart' show parseConfigIndex;

/// 本模块日志标签。
const String _logTag = 'Partner';

/// 兼容解析数字：int / num / 数字字符串 / bool（游戏各接口类型不一致）。
int _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is bool) return v ? 1 : 0;
  return int.tryParse('$v') ?? 0;
}

/// 定位 `FriendSystem` 配置中的 `partnerLevel_list`。
///
/// 兼容三种入参：整表 `{FriendSystem:{levelIntimacy:{partnerLevel_list:[...]}}}`、
/// 直接给出 `partnerLevel_list` 的 List、或无法定位时的 null。
Object? _partnerLevelListOf(Object? decoded) {
  if (decoded is List) return decoded;
  if (decoded is! Map) return null;
  final root = decoded['FriendSystem'];
  if (root is! Map) return null;
  final intimacy = root['levelIntimacy'];
  if (intimacy is! Map) return null;
  return intimacy['partnerLevel_list'];
}

/// 解析 `FriendSystem` 配置 → 关系等级阈值列表。
///
/// 入参为 `decodeHttpResponse` 的解析结果；沿
/// `FriendSystem.levelIntimacy.partnerLevel_list` 取值，每条为
/// `{ level, intimacyValue }`。返回按 `level` 升序去重的
/// `(level, intimacyValue)` 列表；脏条目（非 Map / `level` 非正 /
/// `intimacyValue` 非正）只跳过、绝不抛异常；非 0 `code`/`ret` 或路径缺失 → 空列表。
List<(int level, int intimacyValue)> parsePartnerLevels(Object? decoded) {
  if (decoded is Map && !PartnerClient._isOk(decoded.cast<String, Object?>())) {
    return const <(int, int)>[];
  }
  final raw = _partnerLevelListOf(decoded);
  if (raw is! List) return const <(int, int)>[];
  final byLevel = <int, int>{};
  for (final e in raw) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final level = _toInt(m['level'] ?? m['Level']);
    final value = _toInt(m['intimacyValue'] ?? m['intimacy_value']);
    if (level <= 0 || value <= 0) continue;
    byLevel.putIfAbsent(level, () => value);
  }
  final levels = byLevel.keys.toList()..sort();
  return <(int, int)>[for (final l in levels) (l, byLevel[l]!)];
}

/// 由默契度 [score] 与升序阈值 [levels] 计算当前等级与下一级阈值。
///
/// 逐字复刻 `bestpartnerdatamgr.lua:1081-1099`：`curlevel` 初值 1，顺序遍历，
/// `score >= intimacyValue` 时抬升 `curlevel`，首个 `score < intimacyValue`
/// 即为下一级门槛；全部越界时 `nextLevelScore` 退化为末级阈值。[levels] 为空
/// → `(1, 0)`。参数 `lab`（拍档类型）在官方算法中未使用，故此处不接收。
(int curlevel, int nextLevelScore) partnerLevelFor(
  int score,
  List<(int level, int intimacyValue)> levels,
) {
  if (levels.isEmpty) return (1, 0);
  var nextLevelScore = levels.last.$2;
  var curlevel = 1;
  for (final (level, value) in levels) {
    if (score < value) {
      nextLevelScore = value;
      break;
    }
    curlevel = level;
  }
  return (curlevel, nextLevelScore);
}

/// 拍档类型（`lab`）→ 名称。
///
/// 协议固定映射（1..7 与 100）；未知值回退为「拍档」。
abstract final class PartnerLab {
  static const Map<int, String> names = <int, String>{
    1: '挚友',
    2: '知己',
    3: '姐妹',
    4: '兄弟',
    5: '闺蜜',
    6: '兄妹',
    7: '最佳拍档',
    100: '最佳拍档',
  };

  /// `lab == 0` 不是拍档：`get_list` 会给**每个好友**都下发一条带 `tacitnum`
  /// 的记录，没建立关系的 `lab` 就是 0（只有默契值），不能叫「拍档」。
  static const String noRelation = '未结成拍档';

  static String name(int lab) =>
      lab <= 0 ? noRelation : (names[lab] ?? '拍档');

  /// 是否已建立拍档关系（`lab > 0`）。UI 判「有拍档」一律用这个，
  /// 不要用「在不在列表里」。
  static bool isPartnerLab(int lab) => lab > 0;
}

/// 一条拍档关系（`get_list` 响应项）。
class PartnerInfo {
  /// 拍档的迷你号（`bestUin`）。
  final int bestUin;

  /// 拍档类型 1..7 / 100（见 [PartnerLab]）。
  final int lab;

  /// 默契度。
  final int tacitnum;

  /// 结成时间，epoch 秒。
  final int createtime;

  /// 别称 id（`title_id`；0 = 未设置）。
  final int titleId;

  /// 申请方 uin。
  final int applyUin;

  /// 申请方拍档类型。
  final int applyLab;

  /// 申请时间，epoch 秒。
  final int applyTime;

  /// 申请是否被移除。
  final int applyRemove;

  /// 类型最近变更时间，epoch 秒。
  final int labChgTime;

  /// 当日默契度累计。
  final int dayTacitTotal;

  /// 当日赠送默契度累计。
  final int giftDayTacitTotal;

  const PartnerInfo({
    required this.bestUin,
    this.lab = 0,
    this.tacitnum = 0,
    this.createtime = 0,
    this.titleId = 0,
    this.applyUin = 0,
    this.applyLab = 0,
    this.applyTime = 0,
    this.applyRemove = 0,
    this.labChgTime = 0,
    this.dayTacitTotal = 0,
    this.giftDayTacitTotal = 0,
  });

  /// 拍档类型名称（[PartnerLab]）。
  String get labName => PartnerLab.name(lab);

  /// 结成关系天数：`ceil((now - createtime) / 86400)`，最小 1。
  ///
  /// `createtime` 缺失/非正 → 0（未知，区别于「刚结成」的 1）。
  static int daysSince(int createtime, int now) {
    if (createtime <= 0 || now <= 0) return 0;
    final days = ((now - createtime) / 86400).ceil();
    return days < 1 ? 1 : days;
  }

  /// 以 [now]（epoch 秒）计算的结成关系天数。
  int daysAt(int now) => daysSince(createtime, now);

  /// 解析单条；`bestUin` 缺失/非正 → null。
  ///
  /// 字段名做多写法兼容：服务端在不同接口/版本里会给 `bestUin`/`best_uin`/
  /// `bestuin`，默契度可能是 `tacitnum`/`tacitNum`/`tacit_num` —— 少兼容一种
  /// 就会静默变成 0（表现就是"默契度只显示 0"）。
  static PartnerInfo? fromItem(Object? item) {
    if (item is! Map) return null;
    final m = item.cast<String, Object?>();
    final bestUin = _toInt(
      m['bestUin'] ??
          m['best_uin'] ??
          m['bestuin'] ??
          m['BestUin'] ??
          m['uin'] ??
          m['Uin'],
    );
    if (bestUin <= 0) return null;
    return PartnerInfo(
      bestUin: bestUin,
      lab: _toInt(m['lab'] ?? m['Lab']),
      tacitnum: _toInt(
        m['tacitnum'] ??
            m['tacitNum'] ??
            m['tacit_num'] ??
            m['TacitNum'] ??
            m['Tacitnum'],
      ),
      createtime: _toInt(m['createtime']),
      titleId: _toInt(m['title_id'] ?? m['titleId']),
      applyUin: _toInt(m['applyuin'] ?? m['applyUin']),
      applyLab: _toInt(m['applylab'] ?? m['applyLab']),
      applyTime: _toInt(m['applytime'] ?? m['applyTime']),
      applyRemove: _toInt(m['apply_remove'] ?? m['applyRemove']),
      labChgTime: _toInt(m['labchgtime'] ?? m['labChgTime']),
      dayTacitTotal: _toInt(m['daytacittotal'] ?? m['dayTacitTotal']),
      giftDayTacitTotal: _toInt(
        m['giftdaytacittotal'] ?? m['giftDayTacitTotal'],
      ),
    );
  }

  /// 解析列表（`data`）；非 List / 脏条目只跳过。
  ///
  /// 兼容 `data` 直接是数组，或包一层 `{list|partner_list|data: [...]}`。
  static List<PartnerInfo> parseList(Object? data) {
    var list = data;
    if (list is Map) {
      final m = list.cast<String, Object?>();
      list = m['list'] ?? m['partner_list'] ?? m['data'];
    }
    if (list is! List) return const <PartnerInfo>[];
    final out = <PartnerInfo>[];
    for (final e in list) {
      final p = fromItem(e);
      if (p != null) out.add(p);
    }
    return out;
  }
}

/// 拍档槽位（`get_bestpartner_data` 的 `data`）。
///
/// [total]（`unlock_normal + unlock_special`）即可建立拍档数上限。
class PartnerSlotInfo {
  final int unlockNormal;
  final int unlockSpecial;

  const PartnerSlotInfo({this.unlockNormal = 0, this.unlockSpecial = 0});

  /// 可建立拍档数上限。
  int get total => unlockNormal + unlockSpecial;

  /// 解析 `data`；非 Map → null（字段缺失按 0）。
  static PartnerSlotInfo? parse(Object? data) {
    if (data is! Map) return null;
    final m = data.cast<String, Object?>();
    return PartnerSlotInfo(
      unlockNormal: _toInt(m['unlock_normal'] ?? m['unlockNormal']),
      unlockSpecial: _toInt(m['unlock_special'] ?? m['unlockSpecial']),
    );
  }
}

/// 关系等级进度。
///
/// 官方由 `tacitnum` 与 `FriendSystem.levelIntimacy.partnerLevel_list`
/// （`{level, intimacyValue}`）比较得出当前等级与下一级阈值（见 [partnerLevelFor]）。
/// 阈值配置拉取失败时 [next] 为 null：[ratio] 返回 null，UI 只展示 [current]
/// 数值，不臆造阈值与进度条比例。
class RelationProgress {
  final int current;
  final int? next;

  const RelationProgress({required this.current, this.next});

  /// 进度比例；[next] 未知时返回 null（UI 不画进度条）。
  double? get ratio {
    final n = next;
    if (n == null || n <= 0) return null;
    return (current / n).clamp(0.0, 1.0);
  }
}

/// 会话可见好友的等级 / 拍档 / 大会员聚合缓存。
class PartnerDirectory {
  /// uin → 平台等级。
  final Map<int, int> levels;

  /// uin → 拍档关系。
  final Map<int, PartnerInfo> partners;

  /// uin → 大会员到期时间（epoch 秒）；缺省表示未知 / 非会员。
  final Map<int, int> vipExpiry;

  const PartnerDirectory({
    this.levels = const <int, int>{},
    this.partners = const <int, PartnerInfo>{},
    this.vipExpiry = const <int, int>{},
  });

  static const PartnerDirectory empty = PartnerDirectory();

  int levelOf(int uin) => levels[uin] ?? 0;

  PartnerInfo? partnerOf(int uin) => partners[uin];

  /// 与某个好友的默契度。**每个好友都有**（`get_list` 会返回 `lab == 0`
  /// 的非拍档项，见 `bestpartnerdatamgr.lua:738-797`；取不到就是 0）。
  int tacitOf(int uin) => partners[uin]?.tacitnum ?? 0;

  /// 是不是最佳拍档 —— 判定用 `lab > 0`（`GetUinRepotType == 2`），
  /// 不能只看"在不在 get_list 的返回里"（非拍档也在）。
  bool isPartner(int uin) => (partners[uin]?.lab ?? 0) > 0;

  /// 是否大会员：到期时间存在且晚于 [now]（默认当前时间）。
  bool isVip(int uin, {int? now}) {
    final expiry = vipExpiry[uin];
    if (expiry == null || expiry <= 0) return false;
    final t = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return t < expiry;
  }
}

/// `miniw/bestpartner` 的私有 key（`bestpartnerserver.lua:16`）。
const String kBestpartnerKey = 'ad0fd4743357398df92dc58e9c56937e';

/// `miniw/bestpartner` 的请求 URL —— 与游戏客户端 `ParamEncode`
/// （`bestpartnerserver.lua:14-37`）一致：`extdata` + `auth` 自定义签名，
/// 再按 `http.lua` 的全局参数补齐 `uin/ver/apiid/lang/country`，最后做 s7 包裹。
///
/// ```text
/// extdata = base64(JSON(reqParams))
/// auth1   = md5("$time$s2$uin")
/// auth    = md5(auth1 + act + extdata + privateKey)
/// url     = <base>/miniw/bestpartner?s7=<mybase64(query&s7e=1)>&s7t=<...>
/// ```
///
/// 几点实测（2026-10-01 真实账号）：
/// - 形状必须和游戏一致：**base 保留尾斜杠**（路径形如 `//miniw/bestpartner`，
///   游戏 `g_http_root` 自带 `/`）、**s7 包裹**、**全局参数齐全**。
///   缺全局参数时服务端回 `code=2`（UNKNOW_SERVICE）。
/// - `code=9`（NO_ROUTE）/ `code=23`（WAITTING）**不是形状或版本问题**：同一
///   请求隔 ~2s 重发就好，连发时第一条成功、第二条失败——网关排队/限流。
///   所以调用侧要做单飞缓存 + 退避重试（见 [PartnerClient.getPartnerList]）。
/// - 签名用的 `s2`/`s2t` 必须是 WS 心跳那一对（login_v3 的 sign 会 `auth fail`）。
///
/// 纯函数，便于单测。
String bestpartnerUrl({
  required String base,
  required String act,
  required Map<String, Object?> reqParams,
  required int time,
  required int uin,
  required String s2,
  required String s2t,
  String ver = kClientVersionStr,
  String apiId = kApiId,
  String lang = '0',
  String country = 'CN',
}) {
  final root = base.endsWith('/') ? base : '$base/';
  final extdata = base64Encode(utf8.encode(jsonEncode(reqParams)));
  final auth1 = md5Token(time, s2, uin);
  final auth = md5Sign([auth1, act, extdata, kBestpartnerKey]);
  final query = 'extdata=$extdata&auth=$auth&act=$act&time=$time&s2t=$s2t'
      '&uin=$uin&ver=$ver&apiid=$apiId&lang=$lang&country=$country';
  return encodeS7Url('$root/miniw/bestpartner?$query');
}

/// bestpartner 系列的退避重试时间表（网关排队时用；测试可注入空表）。
///
/// 实测：连发两条同样请求，第一条 `code=0`、第二条 `code=9`（NO_ROUTE）；
/// 间隔 ~2s 重发就恢复，所以按 0.7s → 1.5s → 3s 退避，共最多 4 次。
const List<Duration> kBestpartnerRetryBackoff = <Duration>[
  Duration(milliseconds: 700),
  Duration(milliseconds: 1500),
  Duration(milliseconds: 3000),
];

/// 网关「排队中」类响应码：重发可恢复（`errorcode.lua`：8 DEAD_NODE /
/// 9 NO_ROUTE / 10 NO_CANDIDATE / 23 WAITTING）。
const Set<int> kPartnerTransientCodes = <int>{8, 9, 10, 23};

/// 拍档 / 等级 / 大会员客户端。
class PartnerClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  /// 网关排队（`code=9` 等）时的退避重试时间表；测试可传空表关掉等待。
  final List<Duration> retryBackoff;

  /// 本人拍档列表缓存时长：同账号短时间内重复拉取（多个 provider 同时要）
  /// 直接复用，避开网关的「连发第二条必失败」。
  final Duration listCacheTtl;

  PartnerClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
    this.retryBackoff = kBestpartnerRetryBackoff,
    this.listCacheTtl = const Duration(seconds: 5),
  }) : _dio = dio ?? createDio(),
       baseUrl =
           baseUrl ?? (kDefaultUrls['HttpCommon'] ?? kDefaultBase);

  /// 通用签名 URL（可指定相对路径）。与 [PlayerHomeClient] 同源。
  String _url(
    String path,
    String act, [
    Map<String, String> params = const {},
  ]) {
    // 复用 /miniw/* 的通用构造器（`buildMiniwParamMd5Url`）：它会把
    // uin/ver/apiid/lang/country/server_ts 一起放进签名与 query。
    //
    // 签名用的 s2/s2t 必须是 **WS 心跳/网关** 下发的那一对：login_v3 返回的
    // sign 只够 `/server/*` 用，拿它打 `/miniw/*` 会回 `auth fail` / `参数错误`
    // （2026-10 实测；[ChatService.login] 已用 `WsConnection.fetchS2` 换签后再
    // 构造这些客户端）。
    return buildMiniwParamMd5Url(
      baseUrl: baseUrl,
      path: path.startsWith('/') ? path : '/$path',
      uin: uin,
      s2: s2,
      s2t: s2t,
      params: {'act': act, ...params},
    );
  }

  Future<Map<String, Object?>> _get(String url) async {
    log.debug('url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('RAW: $raw', tag: _logTag);
    if (raw is! String) {
      return raw is Map
          ? raw.cast<String, Object?>()
          : const <String, Object?>{};
    }
    // 脏响应（非 Lua/JSON 表）按失败处理，与本模块「解析器不抛异常」的约定一致。
    try {
      final decoded = decodeHttpResponse(raw);
      return decoded is Map
          ? decoded.cast<String, Object?>()
          : const <String, Object?>{};
    } on LuaTableDecodeError catch (e) {
      log.warn('响应解析失败：$e', tag: _logTag);
      return const <String, Object?>{};
    }
  }

  /// 配置表 base（去掉尾部 `/`），与 [TitleConfigClient] 同源。
  String _cfgBase() => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String> _getText(String url) async {
    // 配置文件名带 md5（内容变了文件名就变）→ 可永久缓存：先读本地，命中即用
    // （离线也能画出亲密度进度条），未命中才发请求并回写。
    final cached = await ConfigTextCache.instance.get(url);
    if (cached != null) return cached;
    final resp = await _dio.get(url);
    final d = resp.data;
    final text = d is String ? d : '$d';
    await ConfigTextCache.instance.put(url, text);
    return text;
  }

  /// 进程内缓存：关系等级阈值（`FriendSystem.levelIntimacy.partnerLevel_list`）。
  static List<(int level, int intimacyValue)>? _levelCache;

  /// 拉取关系等级阈值配置（进程内缓存）。
  ///
  /// 与 [TitleConfigClient] 同源：GET `miniw/ma/configIndex.lua` 取 `FriendSystem`
  /// 的 md5 文件名，再 GET `miniw/ma/<md5>.lua` 解析 `levelIntimacy.partnerLevel_list`
  /// （实测 `miniw/ma/FriendSystem.lua` 直连 404，须走 configIndex → md5）。
  /// 失败返回已缓存值或空列表 → UI 不画进度条，绝不硬编码阈值。
  Future<List<(int level, int intimacyValue)>> getPartnerLevels() async {
    final cached = _levelCache;
    if (cached != null) return cached;
    final cfgUrl = '${_cfgBase()}/miniw/ma/configIndex.lua';
    try {
      final index = parseConfigIndex(await _getText(cfgUrl));
      final md5 = index['FriendSystem'];
      if (md5 == null) {
        _reportIfFailed('关系等级配置', cfgUrl, const <String, Object?>{'code': 1});
        return const <(int, int)>[];
      }
      final cfg = await _getText('${_cfgBase()}/miniw/ma/$md5.lua');
      return _levelCache = parsePartnerLevels(decodeHttpResponse(cfg));
    } catch (e) {
      RequestErrorBus.instance.report(
        label: '关系等级配置',
        endpoint: redactUrl(cfgUrl),
        message: '$e',
      );
      return const <(int, int)>[];
    }
  }

  /// 响应码：优先 `code`，缺省回退 `ret`（等级接口用 `ret`）。
  static int _codeOf(Map<String, Object?> ret) {
    final c = ret['code'];
    if (c is num) return c.toInt();
    final r = ret['ret'];
    if (r is num) return r.toInt();
    return 0;
  }

  static bool _isOk(Map<String, Object?> ret) => _codeOf(ret) == 0;

  /// 解析等级批量响应 `{ret:0, data:[{uin, level}]}`。
  ///
  /// 非 Map / 非 0 code / `data` 非 List → 空 map；条目非 Map / uin 非正跳过。
  static Map<int, int> parseLevelBatchResponse(Object? response) {
    if (response is! Map) return const <int, int>{};
    final ret = response.cast<String, Object?>();
    if (!_isOk(ret)) return const <int, int>{};
    final data = ret['data'];
    if (data is! List) return const <int, int>{};
    final out = <int, int>{};
    for (final e in data) {
      if (e is! Map) continue;
      final m = e.cast<String, Object?>();
      final uin = _toInt(m['uin'] ?? m['Uin']);
      if (uin <= 0) continue;
      out[uin] = _toInt(m['level'] ?? m['Level']);
    }
    return out;
  }

  /// 解析拍档列表响应 `{code:0, data:[...]}`。非 0 → 空列表。
  static List<PartnerInfo> parsePartnerListResponse(Object? response) {
    if (response is! Map) return const <PartnerInfo>[];
    final ret = response.cast<String, Object?>();
    if (!_isOk(ret)) {
      // 静默降级会让「默契度全是 0」看起来像服务端没数据，打一行便于定位。
      // code=9（NO_ROUTE）/ code=3 都是路由/鉴权类失败，必须带上实际发出去的
      // 版本号才分得清是「客户端版本过期」还是「形状/签名不对」。
      log.warn(
        '拍档列表拉取失败：code=${ret['code'] ?? ret['ret']} '
        'msg=${ret['msg']} ver=$kClientVersionStr',
        tag: _logTag,
      );
      return const <PartnerInfo>[];
    }
    final list = PartnerInfo.parseList(ret['data']);
    // 一行摘要：默契度全 0 通常意味着服务端没下发非拍档项，或字段名又变了。
    final withTacit = list.where((p) => p.tacitnum > 0).length;
    final asPartner = list.where((p) => p.lab > 0).length;
    final summary =
        'get_list: ${list.length} 条（拍档 $asPartner，默契度>0 的 $withTacit）';
    if (list.isEmpty || withTacit == 0) {
      log.warn(summary, tag: _logTag);
    } else {
      log.debug(summary, tag: _logTag);
    }
    return list;
  }

  /// 解析槽位响应 `{code:0, data:{unlock_normal, unlock_special}}`。
  /// 非 0 / `data` 非 Map → null。
  static PartnerSlotInfo? parsePartnerSlotResponse(Object? response) {
    if (response is! Map) return null;
    final ret = response.cast<String, Object?>();
    if (!_isOk(ret)) return null;
    return PartnerSlotInfo.parse(ret['data']);
  }

  /// 解析红点响应 `{code:0, data:{count}}`。非 0 / 缺字段 → 0。
  static int parseRedDotResponse(Object? response) {
    if (response is! Map) return 0;
    final ret = response.cast<String, Object?>();
    if (!_isOk(ret)) return 0;
    final data = ret['data'];
    if (data is! Map) return 0;
    return _toInt(data.cast<String, Object?>()['count']);
  }

  /// 解析本人大会员响应 `{code:0, data:[{repiredtime, ...}]}`。
  /// 非 0 / 空列表 / 到期时间非正 → null。
  static int? parseSelfVipResponse(Object? response) {
    if (response is! Map) return null;
    final ret = response.cast<String, Object?>();
    if (!_isOk(ret)) return null;
    final data = ret['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is! Map) return null;
    final m = first.cast<String, Object?>();
    final expiry = _toInt(
      m['repiredtime'] ?? m['repiretime'] ?? m['expiretime'],
    );
    return expiry > 0 ? expiry : null;
  }

  /// 解析他人批量大会员响应：顶层 `tvip_info` 为 `uin → 到期 epoch 秒`。
  /// 非 Map / 缺 `tvip_info` → 空 map；非正到期时间跳过。
  static Map<int, int> parseVipUinListResponse(Object? response) {
    if (response is! Map) return const <int, int>{};
    final ret = response.cast<String, Object?>();
    final info = ret['tvip_info'];
    if (info is! Map) return const <int, int>{};
    final out = <int, int>{};
    for (final e in info.entries) {
      final uin = int.tryParse('${e.key}');
      if (uin == null || uin <= 0) continue;
      final expiry = _toInt(e.value);
      if (expiry > 0) out[uin] = expiry;
    }
    return out;
  }

  /// 平台等级批量（`miniw/upgrade?act=get_level_info_batch`）。
  ///
  /// 单飞 + [listCacheTtl]：同一批 uin 会被多条链路同时要（会话列表逐行、好友页、
  /// 拍档页），重复请求只会撞上网关的账号排队。业务失败也返回空 map → 不缓存。
  Future<Map<int, int>> getPlatformLevels(List<int> uins) {
    if (uins.isEmpty) return Future.value(const <int, int>{});
    return _levels.run(
      _uinSetKey(uins),
      () => _fetchPlatformLevels(uins),
      cacheable: (m) => m.isNotEmpty,
    );
  }

  Future<Map<int, int>> _fetchPlatformLevels(List<int> uins) async {
    final url = _url('miniw/upgrade', 'get_level_info_batch', {
      'op_uin_list': uins.join(','),
    });
    final ret = await _get(url);
    _reportIfFailed('平台等级', url, ret);
    return parseLevelBatchResponse(ret);
  }

  /// 非 0 业务码 → 上报给 `RequestErrorBus`（UI 显示「哪个请求失败了」）。
  ///
  /// 上报地址前统一 [redactUrl]：`/miniw/*` 的签名/令牌都在查询串里。
  static void _reportIfFailed(
    String label,
    String url,
    Map<String, Object?> ret,
  ) {
    if (_isOk(ret)) return;
    log.warn('$label 失败：code=${_codeOf(ret)}', tag: _logTag);
    RequestErrorBus.instance.report(
      label: label,
      endpoint: redactUrl(url),
      code: _codeOf(ret),
      message: '${ret['msg'] ?? ''}',
    );
  }

  /// `miniw/bestpartner` 专用请求（见 [bestpartnerUrl]）。
  String _bestpartnerUrl(String act, Map<String, Object?> reqParams) =>
      bestpartnerUrl(
        base: baseUrl,
        act: act,
        reqParams: reqParams,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        uin: uin,
        s2: s2,
        s2t: s2t,
      );

  /// bestpartner 请求 + 网关排队退避重试（见 [kBestpartnerRetryBackoff]）。
  ///
  /// 重试耗尽或遇到不可重试的业务码时，把失败上报给 `RequestErrorBus`，
  /// UI 才会显示「哪个请求失败了」（以前是静默返回空数据）。
  Future<Map<String, Object?>> _bestpartnerGet(
    String act,
    Map<String, Object?> reqParams, {
    String label = '拍档数据',
  }) async {
    final attempts = retryBackoff.length + 1;
    var ret = const <String, Object?>{};
    var url = '';
    for (var i = 0; i < attempts; i++) {
      url = _bestpartnerUrl(act, reqParams);
      ret = await _get(url);
      if (!kPartnerTransientCodes.contains(_codeOf(ret))) break;
      if (i == attempts - 1) break;
      await Future<void>.delayed(retryBackoff[i]);
    }
    final code = _codeOf(ret);
    if (!_isOk(ret)) {
      log.warn(
        'bestpartner $act 失败：code=$code（重试 $attempts 次）',
        tag: _logTag,
      );
      _reportIfFailed(label, url, ret);
    }
    return ret;
  }

  /// 本人拍档列表 / 平台等级 / 大会员：进程内单飞 + [listCacheTtl] 缓存。
  ///
  /// 三个都要：这些接口会被多条链路在同一时刻要（会话列表、好友页、拍档页、
  /// 玩家浮窗），而网关对同账号连发会排队 —— 第二条回 `code=9`。列表最早加上
  /// （线上实测「连续获取两遍，第一遍有数据、第二遍 code=9」），等级与大会员
  /// 此前完全没有缓存，一并补上。缓存只活 [listCacheTtl]（默认 5s）。
  late final RequestCache<(List<PartnerInfo>, bool)> _selfList =
      RequestCache<(List<PartnerInfo>, bool)>(ttl: listCacheTtl);
  late final RequestCache<Map<int, int>> _levels =
      RequestCache<Map<int, int>>(ttl: listCacheTtl);
  late final RequestCache<Map<int, int>> _vip =
      RequestCache<Map<int, int>>(ttl: listCacheTtl);

  /// uin 集合的缓存键：去重 + 升序 → 与调用方传入的顺序无关。
  static String _uinSetKey(List<int> uins) {
    final sorted = uins.toSet().toList()..sort();
    return sorted.join(',');
  }

  /// 拍档列表（含默契度 `tacitnum`）；[otherUin] 传他人迷你号（缺省查自己）。
  ///
  /// `miniw/bestpartner?act=get_list`（URL 形状见 [bestpartnerUrl]），`otheruin`
  /// 放在 `extdata` 里。响应 `{code:0, data:[{bestUin, tacitnum, lab, createtime,
  /// daytacittotal, giftdaytacittotal, ...}]}` —— **非拍档好友也在列表里**
  /// （`lab == 0`），所以每个好友都有默契度。
  ///
  /// 网关对同一账号连发会排队（第二条回 `code=9`），所以本人列表做了单飞 +
  /// 短缓存（[RequestCache]）；查他人不进缓存。
  Future<List<PartnerInfo>> getPartnerList({int? otherUin}) async {
    if (otherUin != null) return (await _fetchPartnerList(otherUin)).$1;
    // 本人列表只有一份 → 缓存键固定；业务失败（code != 0）不缓存。
    final result = await _selfList.run(
      'self',
      () => _fetchPartnerList(null),
      cacheable: (v) => v.$2,
    );
    return result.$1;
  }

  /// 拉一次拍档列表；第二个值 = 业务是否成功（成功才允许进缓存）。
  Future<(List<PartnerInfo>, bool)> _fetchPartnerList(int? otherUin) async {
    final ret = await _bestpartnerGet(
      'get_list',
      {'otheruin': ?otherUin},
      label: otherUin == null ? '拍档列表（我）' : '拍档列表（$otherUin）',
    );
    return (parsePartnerListResponse(ret), _isOk(ret));
  }

  /// 拍档槽位（`act=get_bestpartner_data`，`uin` 放在 `extdata` 里）。
  Future<PartnerSlotInfo?> getPartnerSlot(int targetUin) async {
    return parsePartnerSlotResponse(
      await _bestpartnerGet(
        'get_bestpartner_data',
        {'uin': targetUin},
        label: '拍档槽位',
      ),
    );
  }

  /// 红点数量（`act=get_red_dot_info`）。
  Future<int> getRedDotCount() async {
    return parseRedDotResponse(
      await _bestpartnerGet('get_red_dot_info', {'uin': uin}, label: '拍档红点'),
    );
  }

  /// 设置拍档别称（`act=set_bestpartner_title`，参数进 `extdata`）。成功返回 true。
  Future<bool> setPartnerTitle({
    required int target,
    required int titleId,
  }) async {
    return _isOk(await _get(_bestpartnerUrl('set_bestpartner_title', {
      'uin': uin,
      'target': target,
      'title_id': titleId,
    })));
  }

  /// 开启拍档槽位（`act=unlock_bestpartnet_pos`，注意官方拼写）。成功 true。
  Future<bool> unlockPartnerSlot({
    required int pos,
    required int special,
  }) async {
    return _isOk(await _get(_bestpartnerUrl('unlock_bestpartnet_pos', {
      'uin': uin,
      'pos': pos,
      'special': special,
    })));
  }

  /// 申请成为拍档（`act=apply`）。成功返回 true。
  Future<bool> applyPartner({
    required int desUin,
    required int applyLab,
  }) async {
    return _isOk(await _get(_bestpartnerUrl('apply', {
      'desUin': desUin,
      'applyLab': applyLab,
    })));
  }

  /// 本人大会员到期时间（`miniw/business?act=vip_get_data`）；非会员 null。
  Future<int?> getMyVipExpiry() async {
    final url = _url('miniw/business', 'vip_get_data');
    final ret = await _get(url);
    _reportIfFailed('大会员（本人）', url, ret);
    return parseSelfVipResponse(ret);
  }

  /// 他人批量大会员到期时间（`act=vip_get_uinlst_vipdata`）。
  /// [uins] 以 `_` 连接为 `param_id`；返回 `{uin: 到期 epoch 秒}`。
  ///
  /// 与 [getPlatformLevels] 同样做单飞 + [listCacheTtl]。
  Future<Map<int, int>> getVipExpiry(List<int> uins) {
    if (uins.isEmpty) return Future.value(const <int, int>{});
    return _vip.run(
      _uinSetKey(uins),
      () => _fetchVipExpiry(uins),
      cacheable: (m) => m.isNotEmpty,
    );
  }

  Future<Map<int, int>> _fetchVipExpiry(List<int> uins) async {
    final url = _url('miniw/business', 'vip_get_uinlst_vipdata', {
      'param_id': uins.join('_'),
    });
    final ret = await _get(url);
    _reportIfFailed('大会员（批量）', url, ret);
    return parseVipUinListResponse(ret);
  }
}
