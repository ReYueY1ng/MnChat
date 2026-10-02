/// 迷你世界辅助接口客户端 —— 表情 / 气泡 / 好友礼物 / 红包。
///
/// 这些接口共用 `http_getParamMD5` 签名（http.lua:470）：
///   参数按 key 排序拼 `k=v`（值先 urlDecode 再 urlEncode）追加私钥做 md5；
///   query 为 `k=v` 全量（**不含 s2**，s2 仅入签名）`&time=&s2t=&encrypt_ver=3`。
/// 与 `profile.dart` 的 `query_portrait`（`/miniw/business`）同一套。
///
/// 端点：
/// - 表情 `/miniw/emoji/act/<act>?`（`emojisysservice.lua:175-200`）
/// - 气泡 `/miniw/business?act=bubble_*`（`chatbubbleservice.lua`）
/// - 好友礼物 `/miniw/welfare?act=*`（`friendgiftdatamgr.lua`）
/// - 红包 `/miniw/red_packet?act=*`（`redpocketservice.lua` / `sendfriendrpservice.lua`）
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../net/config.dart' show kApiId, kClientVersionStr, kDefaultBase;
import '../net/http_factory.dart' show createDio;
import 'gateway.dart' show buildMiniwParamMd5Url;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';
import 'request_errors.dart' show reportIfFailed;

/// 本模块日志标签。
const String _logTag = 'MiniwExtra';

/// `/miniw/*` 参数签名 GET 请求基类。
class MiniwParamClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;
  final String apiId;
  final String ver;
  final String country;
  final String lang;

  MiniwParamClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
    this.apiId = kApiId,
    this.ver = kClientVersionStr,
    this.country = 'CN',
    this.lang = '0',
  })  : _dio = dio ?? createDio(),
        baseUrl = baseUrl ?? kDefaultBase;

  /// 构造带 md5 的完整 URL —— 见 [buildMiniwParamMd5Url]
  /// （业务参数之外还会带 uin/ver/apiid/lang/country/server_ts 全局参数）。
  String buildUrl(
    String path,
    Map<String, String> params, {
    List<String> trailing = const [],
  }) =>
      buildMiniwParamMd5Url(
        baseUrl: baseUrl,
        path: path,
        params: params,
        uin: uin,
        s2: s2,
        s2t: s2t,
        ver: ver,
        apiId: apiId,
        lang: lang,
        country: country,
        trailing: trailing,
      );

  /// GET 并解码响应（JSON → LuaTable 兼容）。
  Future<Map<String, Object?>> get(
    String path,
    Map<String, String> params, {
    List<String> trailing = const [],
  }) async {
    final url = buildUrl(path, params, trailing: trailing);
    log.debug('${path.split('/').last} url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    final text = raw is String ? raw : jsonEncode(raw);
    final decoded = decodeHttpResponse(text);
    reportIfFailed(url, decoded);
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// 响应业务码（`ret` / `code`）。
  static int codeOf(Map<String, Object?> resp) {
    final c = resp['ret'] ?? resp['code'];
    return c is num ? c.toInt() : -1;
  }
}

// ── 表情系统（/miniw/emoji）─────────────────────────────────────────────────

/// 已拥有的表情包（`own_list` / `get_emoji_own_list` 项）。
class OwnedEmoji {
  /// 表情包 ID。
  final String packId;

  /// 过期时间（`expire_time`，<0 = 永久/未给）。
  final int expireTime;

  /// 获取方式（`GetType`）。
  final int getType;

  const OwnedEmoji({
    required this.packId,
    this.expireTime = -1,
    this.getType = 0,
  });

  /// 从 own_list 项解析；`id`/`ID` 即包 ID，也兼容纯字符串项。
  static OwnedEmoji? from(Object? e) {
    if (e is String || e is num) {
      final id = e.toString();
      return id.isEmpty ? null : OwnedEmoji(packId: id);
    }
    if (e is! Map) return null;
    final m = e.cast<String, Object?>();
    final id = (m['id'] ?? m['ID'])?.toString() ?? '';
    if (id.isEmpty) return null;
    int i(Object? v, {int f = 0}) => v is num ? v.toInt() : int.tryParse('$v') ?? f;
    return OwnedEmoji(
      packId: id,
      expireTime: i(m['expire_time'] ?? m['ExpireTime'], f: -1),
      getType: i(m['GetType'] ?? m['get_type']),
    );
  }
}

/// 表情系统客户端（`/miniw/emoji/act/<act>`，`emojisysservice.lua:175-200`）。
///
/// act：get_emoji_own_list / get_user_emoji_data / get_emoji_sequence /
/// set_emoji_sequence / check_emoji_owned / use_emoji_item / add_emoji。
///
/// 注意 `check_emoji_owned` / `use_emoji_item` / `add_emoji` 的参数名以
/// `emoji_id` 传包 ID（`ReqUseEmojiProp` 从道具 item_id 反查包 ID）。
class EmojiClient extends MiniwParamClient {
  EmojiClient({
    required super.uin,
    required super.s2,
    required super.s2t,
    super.dio,
    super.baseUrl,
  });

  Future<Map<String, Object?>> _act(
    String act, [
    Map<String, String> params = const {},
  ]) =>
      get(
        'miniw/emoji/act/$act',
        {'act': act, ...params},
        trailing: const ['json=1'],
      );

  /// 我拥有的表情包列表（`get_emoji_own_list`）。
  Future<List<OwnedEmoji>> ownList() async {
    final resp = await _act('get_emoji_own_list');
    return _parseOwned(resp['own_list'] ?? resp['data']);
  }

  /// 已拥有 + 展示顺序（`get_user_emoji_data`）→ `{own_list, seq}`。
  Future<Map<String, Object?>> userData() => _act('get_user_emoji_data');

  /// 我的表情展示顺序（`get_emoji_sequence`）→ 包 ID 列表。
  Future<List<String>> getSequence() async {
    final resp = await _act('get_emoji_sequence');
    final raw = resp['seq'] ?? resp['data'];
    final out = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final id = e?.toString() ?? '';
        if (id.isNotEmpty) out.add(id);
      }
    }
    return out;
  }

  /// 设置表情展示顺序（`set_emoji_sequence`，参数 `seq` 为逗号分隔包 ID）。
  Future<Map<String, Object?>> setSequence(List<String> packIds) =>
      _act('set_emoji_sequence', {'seq': packIds.join(',')});

  /// 是否拥有某表情包（`check_emoji_owned`）。
  Future<Map<String, Object?>> checkOwned(String packId) =>
      _act('check_emoji_owned', {'emoji_id': packId});

  /// 使用表情道具解锁表情包（`use_emoji_item`）。
  Future<Map<String, Object?>> useItem(String packId) =>
      _act('use_emoji_item', {'emoji_id': packId});

  /// 添加表情包（`add_emoji`）。
  Future<Map<String, Object?>> add(String packId) =>
      _act('add_emoji', {'emoji_id': packId});

  static List<OwnedEmoji> _parseOwned(Object? raw) {
    final out = <OwnedEmoji>[];
    if (raw is List) {
      for (final e in raw) {
        final item = OwnedEmoji.from(e);
        if (item != null) out.add(item);
      }
    } else if (raw is Map) {
      raw.forEach((k, v) {
        final item = OwnedEmoji.from(v is Map ? v : k.toString());
        if (item != null) out.add(item);
      });
    }
    return out;
  }
}

// ── 聊天气泡（/miniw/business?act=bubble_*）─────────────────────────────────

/// 气泡条目（`bubble_get_data` 项，字段按 id/param_id 归一化）。
class BubbleItem {
  final int id;
  final int paramId;
  final int expireTime;

  const BubbleItem({required this.id, this.paramId = 0, this.expireTime = -1});

  static BubbleItem? from(Object? e) {
    if (e is! Map) return null;
    final m = e.cast<String, Object?>();
    int i(Object? v, {int f = 0}) => v is num ? v.toInt() : int.tryParse('$v') ?? f;
    return BubbleItem(
      id: i(m['id'] ?? m['ID'] ?? m['bubble_id']),
      paramId: i(m['param_id'] ?? m['ParamId']),
      expireTime: i(m['time'] ?? m['expire_time'], f: -1),
    );
  }
}

/// 聊天气泡客户端（`chatbubbleservice.lua`，走 `/miniw/business`）。
class BubbleClient extends MiniwParamClient {
  BubbleClient({
    required super.uin,
    required super.s2,
    required super.s2t,
    super.dio,
    super.baseUrl,
  });

  /// 我拥有的气泡（`bubble_get_data`）。
  Future<Map<String, Object?>> getData() =>
      get('miniw/business', {'act': 'bubble_get_data'});

  /// 使用气泡道具（`bubble_use_item`）。
  Future<Map<String, Object?>> useItem({
    required int itemId,
    int count = 1,
  }) =>
      get('miniw/business', {
        'act': 'bubble_use_item',
        'item_id': '$itemId',
        'item_num': '$count',
      });

  /// 切换当前佩戴气泡（`bubble_use_record`）。
  Future<Map<String, Object?>> useRecord(int paramId) =>
      get('miniw/business', {
        'act': 'bubble_use_record',
        'param_id': '$paramId',
      });

  /// 购买气泡（`bubble_buy`）。
  Future<Map<String, Object?>> buy(int itemId) =>
      get('miniw/business', {'act': 'bubble_buy', 'item_id': '$itemId'});
}

// ── 好友礼物（/miniw/welfare）──────────────────────────────────────────────

/// 好友礼物客户端（`friendgiftdatamgr.lua`，走 `/miniw/welfare`）。
///
/// 注意：`give_gift` / `buy_give_gift` 涉及迷你币支付，外部客户端通常只做
/// 「查看礼物数据」；赠送链路是否可用需按支付能力评估。
class FriendGiftClient extends MiniwParamClient {
  FriendGiftClient({
    required super.uin,
    required super.s2,
    required super.s2t,
    super.dio,
    super.baseUrl,
  });

  /// 礼物面板数据（`get_gift_data`）。
  Future<Map<String, Object?>> getGiftData(Object opUin) =>
      get('miniw/welfare', {'act': 'get_gift_data', 'op_uin': '$opUin'});

  /// 赠送礼物（`give_gift`）。[type] 为支付方式。
  Future<Map<String, Object?>> giveGift({
    required Object opUin,
    required int itemId,
    required int num,
    int type = 0,
    String roleName = '',
  }) =>
      get('miniw/welfare', {
        'act': 'give_gift',
        'op_uin': '$opUin',
        'id': '$itemId',
        'num': '$num',
        'type': '$type',
        'role_name': roleName,
      });

  /// 购买并赠送（`buy_give_gift`）。
  Future<Map<String, Object?>> buyGiveGift({
    required Object opUin,
    required int itemId,
    required int num,
    int type = 0,
  }) =>
      get('miniw/welfare', {
        'act': 'buy_give_gift',
        'op_uin': '$opUin',
        'id': '$itemId',
        'num': '$num',
        'type': '$type',
      });

  /// 收到的礼物记录（`client_query_gift_records`）。
  Future<Map<String, Object?>> giftRecords() =>
      get('miniw/welfare', {'act': 'client_query_gift_records'});
}

// ── 红包（/miniw/red_packet）────────────────────────────────────────────────

/// 红包客户端（`redpocketservice.lua` / `sendfriendrpservice.lua`）。
///
/// `redpocketType`：1=地图红包，2=家族红包，3=队伍红包（见 ReqGrabRedPocket）。
class RedPacketClient extends MiniwParamClient {
  RedPacketClient({
    required super.uin,
    required super.s2,
    required super.s2t,
    super.dio,
    super.baseUrl,
  });

  /// 领取红包（`grab_red_packet`）。[rpIndex] 来自红包卡片的 rp_index。
  Future<Map<String, Object?>> grab({
    required Object rpIndex,
    int redpocketType = 1,
    Object? mapId,
    Object? roomId,
    Object? familyId,
    Object? teamId,
  }) {
    final params = <String, String>{
      'act': 'grab_red_packet',
      'rp_index': '$rpIndex',
    };
    if (redpocketType == 1) {
      params['map_id'] = '${mapId ?? 0}';
      params['room_id'] = '${roomId ?? 0}';
    } else if (redpocketType == 2) {
      params['map_id'] = '0';
      params['room_id'] = '${familyId ?? 0}';
      params['family_id'] = '${familyId ?? 0}';
      params['redpocketType'] = '$redpocketType';
    } else {
      params['map_id'] = '0';
      params['room_id'] = '${teamId ?? 0}';
      params['redpocketType'] = '$redpocketType';
    }
    return get('miniw/red_packet', params);
  }

  /// 发放红包（`make_red_packet`）。
  Future<Map<String, Object?>> make(Map<String, String> params) =>
      get('miniw/red_packet', {'act': 'make_red_packet', ...params});

  /// 查好友红包领取/发放限制（`query_friend_redpacket_limit_status`）。
  Future<Map<String, Object?>> friendLimitStatus({
    required Object opUin,
    required int rpId,
  }) =>
      get('miniw/red_packet', {
        'act': 'query_friend_redpacket_limit_status',
        'opt_uin': '$opUin',
        'rpId': '$rpId',
      });

  /// 创建迷你币订单（`create_minicoin_order`，走 `/miniw/business`）。
  Future<Map<String, Object?>> createMinicoinOrder({
    required Object payUin,
    required String payNickname,
    required int amount,
    required int price,
    int present = 0,
  }) =>
      get('miniw/business', {
        'act': 'create_minicoin_order',
        'is_direct_buy': '1',
        'order_type': '2',
        'nickname': '',
        'pay_uin': '$payUin',
        'pay_nickname': payNickname,
        'amount': '$amount',
        'price': '$price',
        'present': '$present',
      });
}
