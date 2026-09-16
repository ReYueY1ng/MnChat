/// 玩家主页客户端 —— /miniw/personal_center（主页信息）与 /miniw/posting（关系）。
///
/// 移植自反编译源码 playercenterv2homepageservice.lua：
///   - get_user_homepage(uin, target, module_list)：主页各模块数据
///   - add_visit_record(uin, target, prize)：访问（+送礼物）
///   - query_target_relation(op_uin, target_list)：查询关注/粉丝关系
///   - get_top_flag_list / set_top_flag：模块置顶状态与置顶开关
/// 签名用 http_getParamMD5（与 dynamics 相同）。
library;

import 'dart:convert' show jsonEncode;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../models/homepage_modules.dart'
    show
        favoriteFolderCount,
        homeLayoutEntries,
        multimediaImprintCount,
        userAddrFromResponse;
import '../net/config.dart'
    show backendShequ, kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';

/// 本模块日志标签。
const String _logTag = 'PlayerHome';

/// 主页模块 id（对齐 playerCenterV2Config.moduleList）。
class PlayerHomeModule {
  static const int roleInfo = 1;
  static const int avatar = 2;
  static const int posting = 3; // 动态
  static const int skin = 4;
  static const int avatarCollect = 5;
  static const int achieve = 6;
  static const int headFrame = 7;
  static const int charm = 8; // 魅力
  static const int title = 9; // 称号
  static const int enjoyMatch = 10;
  static const int map = 11;
  static const int partner = 12; // 好友关系/搭档
  static const int achieve2 = 13;
  static const int socialSign = 16; // 交友标签
  static const int family = 17; // 家族
  static const int favoriteFolder = 18;
  static const int multimedia = 19;

  /// 主页完整模块列表（逗号分隔字符串）。
  ///
  /// 对齐 `playerCenterV2Config.homePageCompItem`（`playercenterv2config.lua:129-143`）
  /// 全部组件模块，另加 `role_info`(1)（统计 / 头像）与 `family`(17)——
  /// 官方 `QueryComponentInfo` 即把二者补进请求
  /// （`playercenterv2homepagectrl.lua:128-142`）。`enjoy_match`(10) 无主页组件，
  /// 不请求。含 `achieve`(6) 以取 `data.medal_list` 勋章列表
  /// （`playercenterv2datamanager.lua:162`）。
  static const String fullList = '1,2,3,4,5,6,7,8,9,11,12,13,16,17,18,19';

  /// 默认请求的模块列表（已扩展为完整列表）。
  ///
  /// 保留旧名以兼容既有调用方；新代码可直接用 [fullList]。
  static const String defaultList = fullList;
}

/// 一条访客记录（`get_visitor_list` 响应项）。
///
/// 响应只含 uin 与访问时间，昵称/头像/头像框需另用
/// `ProfileClient.getProfileBatch3` 批量补全。
class VisitRecord {
  /// 访客的迷你号。
  final int uin;

  /// 访问时间，epoch **秒**（对齐官方 `getServerTime() - v.time`）。
  final int time;

  const VisitRecord({required this.uin, required this.time});
}

/// 玩家主页客户端。
class PlayerHomeClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  PlayerHomeClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
  }) : _dio = dio ?? createDio(),
       baseUrl =
           baseUrl ??
           (kIsWeb
               ? backendShequ()
               : (kDefaultUrls['HttpCommon'] ?? kDefaultBase));

  /// 通用签名 URL（可指定相对路径）。
  String _url(
    String path,
    String act, [
    Map<String, String> params = const {},
  ]) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final all = <String, String>{
      'act': act,
      'uin': '$uin',
      'apiid': kApiId,
      'ver': kClientVersionStr,
      'country': 'CN',
      'lang': '0',
      ...params,
    };
    final md5 = httpGetParamMd5(
      all,
      timeVal: now,
      s2: s2,
      s2t: s2t,
      key: httpGetParamKey,
    );
    final parts = <String>[
      ...all.entries.map(
        (e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}',
      ),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    return '$base/$path?${parts.join('&')}&md5=$md5';
  }

  Future<Map<String, Object?>> _get(String url) async {
    log.debug('url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('RAW: $raw', tag: _logTag);
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// 拉取玩家主页数据（act=get_user_homepage，路径 personal_center）。
  /// [moduleList] 逗号分隔的模块 id。返回完整 data map。
  Future<Map<String, Object?>> getUserHomepage(
    int targetUin, {
    String moduleList = PlayerHomeModule.defaultList,
  }) async {
    final url = _url('miniw/personal_center', 'get_user_homepage', {
      'target': '$targetUin',
      'module_list': moduleList,
    });
    final ret = await _get(url);
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return {};
    }
    final data = ret['data'];
    if (data is Map) return data.cast<String, Object?>();
    return {};
  }

  /// 角色等级（`miniw/upgrade?act=get_level_info_batch`）。
  /// 返回 `{uin: level}`；失败返回空 map。
  Future<Map<int, int>> getPlatformLevels(List<int> uins) async {
    final out = <int, int>{};
    if (uins.isEmpty) return out;
    final url = _url('miniw/upgrade', 'get_level_info_batch', {
      'op_uin_list': uins.join(','),
    });
    final ret = await _get(url);
    final data = ret['data'];
    if (data is List) {
      for (final e in data) {
        if (e is! Map) continue;
        final m = e.cast<String, Object?>();
        final u = m['uin'];
        final lv = m['level'];
        if (u is num && lv is num) out[u.toInt()] = lv.toInt();
      }
    }
    return out;
  }

  /// 冒险家等级（`miniw/mini_season?act=get_other_player_score`）。
  /// 返回 `{level, level_s, name}`；失败返回 null。
  Future<Map<String, Object?>?> getOtherPlayerScore(int targetUin) async {
    final url = _url('miniw/mini_season', 'get_other_player_score', {
      'op_uin': '$targetUin',
    });
    final ret = await _get(url);
    final code = ret['code'] ?? ret['ret'];
    if (code is num && code != 0) return null;
    final data = ret['data'];
    return data is Map ? data.cast<String, Object?>() : null;
  }

  /// 我的收藏夹数量（`miniw/favorite?act=get_collect_ids`）。
  ///
  /// 对齐反编译 `ContentFavsService:ReqPlayerCreatedData`
  /// （`contentfavsservice.lua:205-209`）：参数仅 `op_uin`（本人传自身 uin），
  /// URL 根 `miniw/favorite`（同文件 `:23`），签名用 http_getParamMD5。
  /// 响应 `data.list` 为「收藏夹 id → 数据」映射，数量即条目数
  /// （`contentfavsdata.lua:525-543`）。失败或 `code!=0` 返回 `null`。
  Future<int?> getFavoriteFolderCount(int targetUin) async {
    final url = _url('miniw/favorite', 'get_collect_ids', {
      'op_uin': '$targetUin',
    });
    final ret = await _get(url);
    return favoriteFolderCount(ret);
  }

  /// 迷你印迹数量（`miniw/camera?act=get_photo_homepage`）。
  ///
  /// 对齐反编译 `MultimediaAlbumService:ReqPlayerCenterPhotoData`
  /// （`multimediaalbumservice.lua:255-261`）：参数 `page=1`、`page_size=1000`、
  /// `op_uin`，URL 根 `miniw/camera`（同文件 `:26-31`）。主页组件固定请求照片
  /// 类型（`playercenterv2multimediacompctrl.lua:158-173`）。响应 `data.list`
  /// 为照片数组，数量即条目数（`multimediaalbumdata.lua:5200-5233`）。
  /// 失败或 `code!=0` 返回 `null`。
  Future<int?> getMultimediaImprintCount(int targetUin) async {
    final url = _url('miniw/camera', 'get_photo_homepage', {
      'page': '1',
      'page_size': '1000',
      'op_uin': '$targetUin',
    });
    final ret = await _get(url);
    return multimediaImprintCount(ret);
  }

  /// IP 属地（`miniw/user_ext?act=get_user_addr`）。
  ///
  /// 对齐反编译 `playerCenterIpAdressCtrl:RequestIpAdress`
  /// （`playercenteripadressctrl.lua:77-105`）：参数仅 `op_uin`，
  /// URL 根 `miniw/user_ext`（同文件 `:84`），签名同其它接口。
  /// 解析见 [userAddrFromResponse]（请求失败与空值统一回退「未知」）。
  /// 官方另有 `ns_version.ip_home` 版本门控（`:68-72`），外部客户端不做门控。
  Future<String> getUserAddr(int targetUin) async {
    final url = _url('miniw/user_ext', 'get_user_addr', {
      'op_uin': '$targetUin',
    });
    final ret = await _get(url);
    return userAddrFromResponse(ret);
  }

  /// 主页布局（`act=get_homepage_layout`，路径 personal_center）。
  ///
  /// 对齐反编译 `playerCenterV2HomePageService:ReqLayout`
  /// （`playercenterv2homepageservice.lua:26-43`）：参数 `target`；
  /// 响应 `data.layout` 为 JSON 串（同文件 `:87`）。条目原样返回，
  /// 供 UI 拖拽排序后 round-trip 保存（见 [changeHomepageLayout]）。
  Future<List<Map<String, Object?>>> getHomepageLayout(int targetUin) async {
    final url = _url('miniw/personal_center', 'get_homepage_layout', {
      'target': '$targetUin',
    });
    final ret = await _get(url);
    return homeLayoutEntries(ret);
  }

  /// 保存主页布局（`act=change_homepage_layout`）。
  ///
  /// 对齐反编译 `playerCenterV2HomePageService:ChangeLayout`
  /// （`playercenterv2homepageservice.lua:45-66`）：参数 `data` = 布局 JSON，
  /// 成功后 `ret.code == 0`。**只改顺序、不改字段**，避免臆造布局 schema。
  Future<bool> changeHomepageLayout(
    List<Map<String, Object?>> layout,
  ) async {
    final url = _url('miniw/personal_center', 'change_homepage_layout', {
      'data': jsonEncode(layout),
    });
    final ret = await _get(url);
    final code = ret['code'] ?? ret['ret'];
    return code is num && code == 0;
  }

  /// 访问记录去重窗口（秒），对齐官方客户端
  /// playercenterv2homepagectrl.lua:GetNeedSendVisitorInfo 的
  /// `offsetTime >= 86400`。
  static const int visitRecordDedupSeconds = 86400;

  /// 是否应上报一次访问记录：仅当开启"留下踪迹"，且距上次发送已满 24 小时。
  /// [lastSentAt] 为上次发送时间（epoch 秒，0 表示从未发送），[now] 为当前时间；
  /// 86400 秒窗口与官方客户端一致。
  static bool shouldRecordVisit({
    required bool leaveTrace,
    required int lastSentAt,
    required int now,
  }) =>
      leaveTrace &&
      (lastSentAt <= 0 || now - lastSentAt >= visitRecordDedupSeconds);

  /// 访问主页（act=add_visit_record）。[prize]=1 附带送花等。
  Future<bool> addVisitRecord(int targetUin, {int prize = 0}) async {
    final url = _url('miniw/personal_center', 'add_visit_record', {
      'target': '$targetUin',
      'prize': '$prize',
    });
    final ret = await _get(url);
    return (ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) == 0;
  }

  /// 拉取访客记录（act=get_visitor_list，路径 personal_center）。
  ///
  /// 对齐反编译 playercenterv2homepageservice.lua:ReqVisitorList：
  /// `{act=get_visitor_list, uin=<ownerUin>, offset=<offset>}`，
  /// 签名与其它 personal_center 接口一致（http_getParamMD5）。
  /// 官方客户端始终只取第一页（offset=0），响应 `data.list` 为
  /// `[{uin, time}]`（time 为 epoch 秒）。失败或 code!=0 返回空列表。
  Future<List<VisitRecord>> getVisitorList(
    int ownerUin, {
    int offset = 0,
  }) async {
    final url = _url('miniw/personal_center', 'get_visitor_list', {
      'uin': '$ownerUin',
      'offset': '$offset',
    });
    final ret = await _get(url);
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return <VisitRecord>[];
    }
    return parseVisitorList(ret['data']);
  }

  /// 解析访客列表响应中的 `data` 字段（纯函数，可单测）。
  ///
  /// 结构：`{list: [{uin: <int>, time: <epoch 秒>}, ...]}`。
  /// 防御性约定（脏数据只跳过，绝不抛异常）：
  ///   - 非 Map / 缺 `list` / `list` 非 List → 空列表；
  ///   - 条目非 Map → 跳过；
  ///   - `uin` 缺失 / 0 / 非数字 → 跳过；
  ///   - `uin`/`time` 兼容 num 与数字字符串；`time` 缺失/非法 → 0。
  static List<VisitRecord> parseVisitorList(Object? data) {
    final out = <VisitRecord>[];
    if (data is! Map) return out;
    final list = data['list'];
    if (list is! List) return out;
    for (final e in list) {
      if (e is! Map) continue;
      final m = e.cast<String, Object?>();
      final uin = _toNum(m['uin']);
      if (uin <= 0) continue;
      out.add(VisitRecord(uin: uin, time: _toNum(m['time'])));
    }
    return out;
  }

  /// 兼容解析数字：int / num / 数字字符串（游戏各接口类型不一致）。
  static int _toNum(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// 查询与目标玩家的关注/粉丝关系（act=query_target_relation，路径 posting）。
  /// 返回 data（key=uin 字符串 → 关系掩码字符串）。
  Future<Map<String, String>> queryTargetRelation(
    int opUin,
    List<int> targets,
  ) async {
    if (targets.isEmpty) return {};
    final url = _url('miniw/posting', 'query_target_relation', {
      'op_uin': '$opUin',
      'target_list': targets.join(','),
    });
    final ret = await _get(url);
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return {};
    }
    final data = ret['data'];
    final out = <String, String>{};
    if (data is Map) {
      for (final e in data.entries) {
        out['${e.key}'] = '${e.value}';
      }
    }
    return out;
  }

  // ── 置顶（set_top_flag / get_top_flag_list） ──────────────────────────

  /// 拉取某模块已置顶条目 id（act=get_top_flag_list，路径 personal_center）。
  ///
  /// 对齐反编译 `playerCenterV2HomePageService:GetTopList`
  /// （`playercenterv2homepageservice.lua:421-446`）：参数 `uin`（本人）+
  /// `module_id`，非本人主页时追加 `target`。响应 `data.top_list` 为
  /// `[{top_id, time}]`，经 [parseTopFlagList] 解析为已置顶 id 集合。
  /// 失败 / code!=0 返回空集合。
  Future<Set<int>> getTopFlagList({
    int moduleId = PlayerHomeModule.headFrame,
    int? targetUin,
  }) async {
    final params = <String, String>{'module_id': '$moduleId'};
    if (targetUin != null && targetUin != uin) {
      params['target'] = '$targetUin';
    }
    final url = _url('miniw/personal_center', 'get_top_flag_list', params);
    final ret = await _get(url);
    return parseTopFlagList(ret);
  }

  /// 解析 `get_top_flag_list` 响应，返回已置顶 id 集合（纯函数，可单测）。
  ///
  /// 结构：`{code:0, data:{module_id:<int>, top_list:[{top_id, time}, ...]}}`
  /// （`playercenterv2homepageservice.lua:448-495`）。防御性约定（脏数据只跳过，
  /// 绝不抛异常）：
  ///   - 非 Map / `code`（或 `ret`）非 0 → 空集合；
  ///   - 缺 `data` / `data` 非 Map / 缺 `top_list` / `top_list` 非 List → 空集合；
  ///   - 条目非 Map → 跳过；`top_id` 缺失 / 0 / 非数字 → 跳过；
  ///   - `time`（即 `top_time`）缺失 / 非正 → 跳过（只统计有效置顶）。
  static Set<int> parseTopFlagList(Object? resp) {
    final out = <int>{};
    if (resp is! Map) return out;
    final m = resp.cast<String, Object?>();
    final code = m['code'] ?? m['ret'];
    if (code is num && code != 0) return out;
    final data = m['data'];
    if (data is! Map) return out;
    final list = (data.cast<String, Object?>())['top_list'];
    if (list is! List) return out;
    for (final e in list) {
      if (e is! Map) continue;
      final em = e.cast<String, Object?>();
      final id = _toNum(em['top_id']);
      if (id <= 0) continue;
      if (_toNum(em['time']) <= 0) continue;
      out.add(id);
    }
    return out;
  }

  /// 置顶 / 取消置顶（act=set_top_flag，路径 personal_center）。
  ///
  /// 对齐反编译 `playerCenterV2HomePageService:ChangeTopState`
  /// （`playercenterv2homepageservice.lua:309-325`）：参数 `uin`（本人）+
  /// `module_id` + `op_id` + `op_type`（**1=置顶 / 0=取消**，见
  /// `playercenterv2headeditorctrl.lua:1515`）。
  ///
  /// 上限校验由服务端裁决（客户端 `CheckMaxTop` 依赖 `MaxTopNum`，见
  /// `playercenterv2homepageservice.lua:339-356`）；服务端拒绝时原样返回其
  /// `msg`，不在此硬编码上限数字。
  Future<SetTopFlagResult> setTopFlag(
    int opId, {
    required bool pin,
    int moduleId = PlayerHomeModule.headFrame,
  }) async {
    final url = _url('miniw/personal_center', 'set_top_flag', {
      'module_id': '$moduleId',
      'op_id': '$opId',
      'op_type': pin ? '1' : '0',
    });
    final ret = await _get(url);
    final code = ret['code'] ?? ret['ret'];
    if (code is num && code == 0) return const SetTopFlagResult(ok: true);
    final msg = ret['msg'] ?? ret['message'] ?? ret['tips'];
    return SetTopFlagResult(
      ok: false,
      message: msg is String && msg.isNotEmpty ? msg : null,
    );
  }
}

/// 置顶 / 取消置顶结果：成功，或携带服务端拒绝原因（如超出置顶上限）。
class SetTopFlagResult {
  /// 服务端是否接受本次操作。
  final bool ok;

  /// 服务端返回的错误文案（`msg`）；无则为 null。
  final String? message;

  const SetTopFlagResult({required this.ok, this.message});
}
