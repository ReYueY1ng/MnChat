/// 消息中心 · 互动通知 —— /miniw/msg_box。
///
/// 对齐反编译 `MainChatInterface`（mainchatinterface.lua:277-430）：
///   - `get_channel_msg_list`  : 某频道通知列表（uin / channel / offset）
///   - `get_channel_msg_cnt`   : 某频道计数
///   - `get_channel_msg_list_x`: 多频道红点（channels 逗号串）
///   - `read_channel_msg` / `del_channel_msg` / `clear_msg`: 已读 / 删除 / 清空
///
/// 频道名（对齐 `DynamicsChannelType`，dynamicsdatamanager.lua:36-43）：
///   post_rep / post_prize / post_at（动态互动，3 频道合并）·
///   fans_change（新增粉丝）· map_interact（作品互动）· post_sys（动态助手）。
///
/// 签名与 msgcenter 相同（http_getParamMD5），仅路径不同。解析器均为纯函数：
/// 非零 code/ret → 空结果；异常结构跳过；绝不抛异常。
library;

import 'dart:convert' show jsonDecode;

import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart'
    show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';
import 'request_errors.dart' show reportIfFailed;

/// 本模块日志标签。
const String _logTag = 'MsgBox';

/// 互动通知路径。
const String kMsgBoxPath = 'miniw/msg_box';

/// 互动通知频道名（对齐 DynamicsChannelType）。
abstract final class MsgBoxChannel {
  static const String rep = 'post_rep'; // 评论我的
  static const String prize = 'post_prize'; // 点赞我的
  static const String at = 'post_at'; // @我的
  static const String fans = 'fans_change'; // 新增粉丝
  static const String mapInteract = 'map_interact'; // 作品互动
  static const String sys = 'post_sys'; // 动态助手（消息中心 0 频道）
}

/// 动态互动筛选项 —— 游戏下拉的 textList（`mainchatinteractivemsg.lua:65-71`）：
/// 全部(3820) / 评论(32034) / 点赞(6660446) / @我(9314037) / 回答(9314113)。
const List<String> kDynamicsNoticeFilters = ['全部', '评论', '点赞', '@我', '回答'];

/// 作品互动筛选项（同文件 72-78）：全部(3820) / 讨论(192151) / 点赞(6660446)
/// / 投块(25229) / 收藏(25228)。
const List<String> kWorksNoticeFilters = ['全部', '讨论', '点赞', '投块', '收藏'];

/// 消息中心顶部 3 个圆入口（对齐 `MainChatInteractiveMsg.MsgType`）。
///
/// 三者共用 `/miniw/msg_box` 的 `get_channel_msg_list` / `read_channel_msg`
/// / `del_channel_msg`，只是频道不同（`mainchatctrl.lua:3086-3200`）：
/// - 动态互动 = post_rep + post_prize + post_at（3 次调用合并）
/// - 新增粉丝 = fans_change
/// - 作品互动 = map_interact
enum MsgBoxEntry {
  dynamics('动态互动', [
    MsgBoxChannel.rep,
    MsgBoxChannel.prize,
    MsgBoxChannel.at,
  ], kDynamicsNoticeFilters),
  fans('新增粉丝', [MsgBoxChannel.fans], null),
  works('作品互动', [MsgBoxChannel.mapInteract], kWorksNoticeFilters);

  const MsgBoxEntry(this.label, this.channels, this.filters);

  /// 入口标题（9314036 / 9312658 / 9310022）。
  final String label;

  /// 该入口聚合的 msg_box 频道（按序合并）。
  final List<String> channels;

  /// 右栏「全部 ▾」的类型筛选项，首项固定「全部」（粉丝入口无类型维度 → null）。
  final List<String>? filters;
}

/// 一条互动通知（`get_channel_msg_list` 的 `msg_list` 条目）。
///
/// 原始结构：`{msg_id, msg_type, data(JSON 字符串), state, time, location,
/// uin, ...}`；`data` 解码后与条目平铺（对齐 `MergeInteractiveFunc`：
/// `itemData[k] = v.data[k]`，`type = msg_type`，`status = state`）。
class MsgBoxMessage {
  final String msgId;
  final String channel;
  final String msgType;
  final int uin;

  /// 载荷通常不含昵称（游戏用角色资料渲染）；为空时 UI 回退迷你号。
  final String nickname;

  /// post_sys（动态助手）条目的标题。
  final String title;

  /// 正文（动态互动=评论内容；粉丝条目为空）。
  final String content;

  /// 被互动动态的正文（`pid_content`，评论/点赞类条目）。
  final String pidContent;

  /// 问答类条目的问题（`question`）。
  final String question;

  /// 可跳转动态 id（"uin_ct"）；空表示无详情可跳。
  final String pid;

  final int time;

  /// IP 归属地（`location`，如"广东"），UI 渲染为 `N小时前 IP 省`。
  final String location;

  /// 缩略图（`pic_url`）。
  final String picUrl;

  /// 0 = 未读（对齐 `state`/`status`）。
  final int status;

  /// 展平后的原始 `data`（保留未建模字段供扩展）。
  final Map<String, Object?> data;

  const MsgBoxMessage({
    required this.msgId,
    required this.channel,
    this.msgType = '',
    this.uin = 0,
    this.nickname = '',
    this.title = '',
    this.content = '',
    this.pidContent = '',
    this.question = '',
    this.pid = '',
    this.time = 0,
    this.location = '',
    this.picUrl = '',
    this.status = 0,
    this.data = const {},
  });

  bool get unread => status == 0;

  /// 是否有可跳转的详情（动态 pid）。
  bool get hasDetail => pid.isNotEmpty && pid != '0';

  /// 行动作文案 —— 逐条对齐游戏卡片的 GetS 取值
  /// （动态 `chatdynamicsmsg.lua:248-320`、作品 `chatworksmsg.lua:140-225`）：
  /// 评论 / 回复 / 点赞 / @我 / 回答 各自一句；未知类型原样回退 msg_type。
  ///
  /// 点赞类在游戏里由模板图标（控制器 `c1`）承担「赞」这个动作，文案本身
  /// 就是「了这条动态：@1」这样的半句，故此处保持一致。
  String get actionLabel {
    if (channel == MsgBoxChannel.fans) return '关注了你';
    switch (msgType) {
      // ── 动态互动（DynamicsNoticeType，数字为枚举值）──
      case 'commented': // 1  9314032
        return '评论了你的动态';
      case 'prized': // 2  9312671
        return '了这条动态';
      case 'add_at': // 3  9314034
        return '在动态@了你';
      case 'comment_at': // 4  9314035
      case 'comment2_at': // 8  9314035
        return '在评论@了你';
      case 'comment_reply': // 5  9314033
        return '回复了你的评论';
      case 'comment_prized': // 6  9312663
      case 'comment2_prized': // 10 9312663
        return '了这条评论';
      case 'comment2': // 7  9312664
      case 'comment2_rep': // 9  9312664
        return '回复了你';
      case 'answer': // 11 9314123
        return '回答了你的问题';
      // ── 作品互动（works msg_type）──
      case 'map_posting': // 9310023
        return '评论了你的作品';
      case 'map_prize': // 9310024
        return '赞了你的作品';
      case 'map_collect': // 9310025
        return '收藏了你的作品';
      case 'map_tip': // 9310026
        return '投块了你的作品';
      case 'template_like': // 9310049
        return '赞了你的模板';
      case 'template_collect': // 9310050
        return '收藏了你的模板';
      // ── 动态助手（频道 0，`actMsgType`，mainchatsystemmsg.lua:195-206）──
      case '1':
        return '动态投票消息';
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
        return '动态抽奖消息';
      case '8':
      case '9':
        return '动态问答消息';
      default:
        return msgType.isNotEmpty ? msgType : '互动消息';
    }
  }

  /// 该条互动在游戏卡片里走「点赞」样式 —— 模板控制器 `c1` 置 1
  /// （`chatdynamicsmsg.lua:56-62`、`chatworksmsg.lua:59-66`），文案前面那个
  /// 「赞」就是这个图标；[actionLabel] 因此只给半句。
  bool get isLikeStyle {
    switch (msgType) {
      case 'prized':
      case 'comment_prized':
      case 'comment2_prized':
      case 'map_prize':
      case 'template_like':
        return true;
      default:
        return false;
    }
  }

  /// 摘要行（行动作 + 被互动动态正文；无则回退评论正文）。
  String get headline {
    final body = pidContent.isNotEmpty ? pidContent : (question.isNotEmpty ? question : content);
    return body.isEmpty ? actionLabel : '$actionLabel：$body';
  }

  /// 该条目归属的筛选分类（对齐 `MainChatInteractiveMsg:GetFilterData`，
  /// mainchatinteractivemsg.lua:150-208；未知类型返回空串，不进任何分类）。
  /// 取值与 [kDynamicsNoticeFilters] / [kWorksNoticeFilters] 除首项外的字面量一致。
  String get filterLabel {
    switch (msgType) {
      case 'commented':
      case 'comment_reply':
      case 'comment2':
      case 'comment2_rep':
        return '评论';
      case 'prized':
      case 'comment_prized':
      case 'comment2_prized':
        return '点赞';
      case 'add_at':
      case 'comment_at':
      case 'comment2_at':
        return '@我';
      case 'answer':
        return '回答';
      // ── 作品互动 ──
      case 'map_posting':
        return '讨论';
      case 'map_prize':
      case 'template_like':
        return '点赞';
      case 'map_tip':
        return '投块';
      case 'map_collect':
      case 'template_collect':
        return '收藏';
      default:
        return '';
    }
  }

  /// 摘要行 `行动作：参数` 里的 @1（游戏卡片 `tf_title` 的参数）：
  /// 作品 / 模板类的参数是**作品名 / 模板名**（`chatworksmsg.lua:185-221`，
  /// 作品名要用 `data.map_id` 查表 → [mapNames]），其余是被互动正文
  /// （pid_content / question）。查不到名字时返回空串，卡片退化成只显示行动作。
  String summaryParam({Map<String, String> mapNames = const {}}) {
    if (msgType == 'template_like' || msgType == 'template_collect') {
      final n = (data['name'] ?? '').toString();
      return n.isEmpty ? '' : '"$n"';
    }
    if (msgType.startsWith('map_')) {
      final n = mapNames[(data['map_id'] ?? '').toString()] ?? '';
      return n.isEmpty ? '' : '"$n"';
    }
    return pidContent.isNotEmpty ? pidContent : question;
  }

  MsgBoxMessage copyWith({int? status}) => MsgBoxMessage(
        msgId: msgId,
        channel: channel,
        msgType: msgType,
        uin: uin,
        nickname: nickname,
        title: title,
        content: content,
        pidContent: pidContent,
        question: question,
        pid: pid,
        time: time,
        location: location,
        picUrl: picUrl,
        status: status ?? this.status,
        data: data,
      );

  /// 从 `msg_list` 条目构造；缺 `msg_id` / 非 Map → null（跳过，不抛异常）。
  static MsgBoxMessage? fromItem(Object? raw, {required String channel}) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final msgId = '${m['msg_id'] ?? m['msgid'] ?? ''}';
    if (msgId.isEmpty || msgId == 'null') return null;

    final flat = _flattenData(m['data']);
    Object? pick(List<String> keys) {
      for (final k in keys) {
        final v = m[k] ?? flat[k];
        if (v != null) return v;
      }
      return null;
    }

    final ch = m['channel']?.toString();
    final msgType = _canonicalMsgType(pick(['msg_type', 'type'])?.toString() ?? '');
    return MsgBoxMessage(
      msgId: msgId,
      channel: (ch == null || ch.isEmpty) ? channel : ch,
      msgType: msgType,
      uin: _actorUin(msgType, m, flat),
      nickname: pick(['nickname', 'nick_name'])?.toString() ?? '',
      title: _safeDecode(pick(['title'])?.toString() ?? ''),
      content: _safeDecode(pick(['content', 'text'])?.toString() ?? ''),
      pidContent: _safeDecode(pick(['pid_content'])?.toString() ?? ''),
      question: _safeDecode(pick(['question'])?.toString() ?? ''),
      pid: pick(['pid'])?.toString() ?? '',
      time: _int(pick(['time', 'create_time', 'ts'])),
      location: pick(['location', 'ipaddress', 'ip_address'])?.toString() ?? '',
      picUrl: pick(['pic_url', 'pic', 'image_url', 'image'])?.toString() ?? '',
      status: _int(pick(['status', 'state'])),
      data: flat,
    );
  }

  /// 线上 `msg_type` 字符串（`DynamicsNoticeMsgBoxType` 的键，
  /// dynamicsdatamanager.lua:16-28）→ 本类沿用的一套规范名
  /// （`DynamicsNoticeType` 的键，同文件 4-15）。实测 post_prize 频道回的是
  /// `"prize"`、post_rep 回 `"rep"`；未知取值原样返回。
  static const Map<String, String> _wireMsgTypes = {
    'rep': 'commented',
    'prize': 'prized',
    'at': 'add_at',
    'com_at': 'comment_at',
    'com_rep': 'comment_reply',
    'com_prize': 'comment_prized',
    'com2': 'comment2',
    'com2_at': 'comment2_at',
    'com2_rep': 'comment2_rep',
    'com2_prize': 'comment2_prized',
  };

  static String _canonicalMsgType(String wire) =>
      _wireMsgTypes[wire] ?? wire;

  /// 互动者 uin —— **不要**用条目顶层的 `uin`：那是这条通知的接收者（本人），
  /// 拿它渲染就会把卡片昵称显示成自己（实测 `get_channel_msg_list` 的条目里
  /// 顶层 `uin` 恒为本人，互动者在 `data` 里）。
  ///
  /// 对齐游戏：`data` 平铺覆盖条目字段后再取
  /// （`chatdynamicsmsg.lua:78-84 ChatDynamicsMsg:SetUserInfo`、
  /// `mainchatinteractivemsg.lua:271-279 ReqNecessaryData`）——
  /// `prized`（点赞）取 `op_uin`，`comment_prized`（评论被赞）取 `act_uin`，
  /// 其余取 `uin`；取不到（评论类条目里 `op_uin` 为 0）时回落 `uin`。
  static int _actorUin(
    String msgType,
    Map<String, Object?> m,
    Map<String, Object?> flat,
  ) {
    // 作品发布类列出的是**动态作者**（`data.pid` 的 uin 前缀），
    // chatworksmsg.lua:34-39 / mainchatinteractivemsg.lua:299-303。
    if (msgType == 'map_posting') {
      final pid = flat['pid'] ?? m['pid'];
      final head = pid == null ? '' : '$pid'.split('_').first;
      final owner = int.tryParse(head) ?? 0;
      if (owner > 0) return owner;
    }
    final actorKey = msgType == 'prized'
        ? 'op_uin'
        : (msgType == 'comment_prized' ? 'act_uin' : 'uin');
    final actor = _int(flat[actorKey] ?? m[actorKey]);
    return actor > 0 ? actor : _int(flat['uin'] ?? m['uin']);
  }

  /// `data` 可能是 JSON 字符串或已是 Map；解析失败返回空 map。
  static Map<String, Object?> _flattenData(Object? raw) {
    if (raw is Map) return raw.cast<String, Object?>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, Object?>();
      } catch (_) {
        // 非 JSON（LuaTable 等）：按未建模处理
      }
    }
    return const {};
  }

  static int _int(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// 内容字段可能被 URL 编码（对齐 DynamicsNotice._safeDecode）。
  static String _safeDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }
}

/// 一页互动通知 + 下一页游标（`data.next_offset`）。
class MsgBoxPage {
  final List<MsgBoxMessage> items;
  final int nextOffset;

  const MsgBoxPage(this.items, this.nextOffset);

  static const MsgBoxPage empty = MsgBoxPage(<MsgBoxMessage>[], 0);
}

/// 校验 `code` / `ret`：存在且为 0 → 成功；非零 / 非数字 → 失败。
bool _codeOk(Map<String, Object?> m) {
  for (final key in const ['code', 'ret']) {
    final v = m[key];
    if (v == null) continue;
    if (v is num) return v == 0;
    final n = int.tryParse('$v');
    return n != null && n == 0;
  }
  return true; // 无失败信号：由调用方按 data 是否可用决定
}

/// 纯解析：`get_channel_msg_list` 响应 → (条目, next_offset)。
///
/// - 非 Map / 非零 code/ret / `data` 非 Map → [MsgBoxPage.empty]；
/// - `msg_list` 缺失或非 List → 空列表（next_offset 仍解析）；
/// - 列表元素非 Map / 缺 msg_id → 跳过。
MsgBoxPage parseChannelMsgList(Object? decoded, {String channel = ''}) {
  if (decoded is! Map) return MsgBoxPage.empty;
  final m = decoded.cast<String, Object?>();
  if (!_codeOk(m)) return MsgBoxPage.empty;
  final data = m['data'];
  if (data is! Map) return MsgBoxPage.empty;
  final dm = data.cast<String, Object?>();

  final items = <MsgBoxMessage>[];
  final rawList = dm['msg_list'];
  if (rawList is List) {
    for (final e in rawList) {
      final msg = MsgBoxMessage.fromItem(e, channel: channel);
      if (msg != null) items.add(msg);
    }
  }
  return MsgBoxPage(items, _asInt(dm['next_offset']));
}

/// 纯解析：`get_channel_msg_cnt` 响应 → 计数。
///
/// 失败 / 字段缺失 / 类型不符 → 0。兼容 `data` 为数字、数字字符串，
/// 或含 `count`/`cnt`/`total`/`unread` 等键的对象。
int parseChannelMsgCount(Object? decoded) {
  if (decoded is! Map) return 0;
  final m = decoded.cast<String, Object?>();
  if (!_codeOk(m)) return 0;
  final data = m['data'];
  if (data is num) return data.toInt();
  if (data is String) return int.tryParse(data) ?? 0;
  if (data is Map) {
    final dm = data.cast<String, Object?>();
    for (final k in const [
      'count',
      'cnt',
      'num',
      'total',
      'msgtotal',
      'msg_total',
      'msg_count',
      'unread',
      'unread_count',
    ]) {
      final n = _asIntOrNull(dm[k]);
      if (n != null) return n;
    }
  }
  return 0;
}

/// 纯解析：`get_channel_msg_list_x` 响应 → {频道名: 未读数}。
///
/// 兼容 `data` 为 {频道: 计数} 的 map（含 `channles`/`channels` 包裹），
/// 或 [{channel/channelid, count/cnt/unread}] 的数组；解析不了的条目跳过。
Map<String, int> parseMultiChannelRedpoints(Object? decoded) {
  if (decoded is! Map) return {};
  final m = decoded.cast<String, Object?>();
  if (!_codeOk(m)) return {};
  final data = m['data'];
  if (data is Map) {
    final dm = data.cast<String, Object?>();
    for (final k in const ['channles', 'channels', 'list', 'redpoints']) {
      final nested = dm[k];
      if (nested is Map) return _redpointsFromMap(nested.cast<String, Object?>());
      if (nested is List) return _redpointsFromList(nested);
    }
    return _redpointsFromMap(dm);
  }
  if (data is List) return _redpointsFromList(data);
  return {};
}

Map<String, int> _redpointsFromMap(Map<String, Object?> m) {
  final out = <String, int>{};
  for (final e in m.entries) {
    final n = _asIntOrNull(e.value);
    if (n == null) continue;
    if (e.key.isEmpty) continue;
    out[e.key] = n;
  }
  return out;
}

Map<String, int> _redpointsFromList(List<Object?> list) {
  final out = <String, int>{};
  for (final e in list) {
    if (e is! Map) continue;
    final em = e.cast<String, Object?>();
    final name = (em['channel'] ?? em['channelid'] ?? em['channel_id'] ?? em['name'])
        ?.toString();
    if (name == null || name.isEmpty) continue;
    final n = _asIntOrNull(
      em['count'] ?? em['cnt'] ?? em['unread'] ?? em['unread_count'] ?? em['num'],
    );
    if (n == null) continue;
    out[name] = n;
  }
  return out;
}

/// 纯解析写操作（read / del / clear）响应：`code`/`ret` 为 0 → true。
///
/// 两个字段都缺失时，非空对象视为成功（部分接口只回 data）；空对象 /
/// 非 Map / 非数字错误码 → false。
bool parseMsgBoxOk(Object? decoded) {
  if (decoded is! Map) return false;
  final m = decoded.cast<String, Object?>();
  var seen = false;
  for (final key in const ['code', 'ret']) {
    final v = m[key];
    if (v == null) continue;
    seen = true;
    if (v is num) {
      if (v != 0) return false;
      continue;
    }
    final n = int.tryParse('$v');
    if (n == null || n != 0) return false;
  }
  return seen || m.isNotEmpty;
}

int _asInt(Object? v) => _asIntOrNull(v) ?? 0;

int? _asIntOrNull(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// 互动通知客户端（`/miniw/msg_box`）。
class MsgBoxClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  MsgBoxClient({
    required this.uin,
    required this.s2,
    required this.s2t,
    Dio? dio,
    String? baseUrl,
  })  : _dio = dio ?? createDio(),
        baseUrl =
            baseUrl ?? (kDefaultUrls['HttpCommon'] ?? kDefaultBase);

  String _url(String act, [Map<String, String> params = const {}]) {
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
    final md5 = httpGetParamMd5(all,
        timeVal: now, s2: s2, s2t: s2t, key: httpGetParamKey);
    final parts = <String>[
      ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    return '$base/$kMsgBoxPath?${parts.join('&')}&md5=$md5';
  }

  Future<Object?> _get(String act,
      [Map<String, String> params = const {}]) async {
    final url = _url(act, params);
    log.debug('$act url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('$act RAW: $raw', tag: _logTag);
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    reportIfFailed(url, decoded);
    return decoded;
  }

  /// 拉某频道通知列表（act=get_channel_msg_list）。失败 → 空页。
  Future<MsgBoxPage> getChannelMsgList(String channel, {int offset = 0}) async {
    final decoded = await _get('get_channel_msg_list', {
      'uin': '$uin',
      'channel': channel,
      'offset': '$offset',
    });
    return parseChannelMsgList(decoded, channel: channel);
  }

  /// 某频道计数（act=get_channel_msg_cnt）。失败 → 0。
  Future<int> getChannelMsgCount(String channel) async {
    final decoded = await _get('get_channel_msg_cnt', {
      'uin': '$uin',
      'channel': channel,
    });
    return parseChannelMsgCount(decoded);
  }

  /// 多频道红点（act=get_channel_msg_list_x）。失败 → {}。
  Future<Map<String, int>> getChannelMsgListX(List<String> channels) async {
    if (channels.isEmpty) return {};
    final decoded = await _get('get_channel_msg_list_x', {
      'uin': '$uin',
      'channels': channels.join(','),
    });
    return parseMultiChannelRedpoints(decoded);
  }

  /// 标记已读（act=read_channel_msg）。空列表视为成功。
  Future<bool> readChannelMsg(String channel, List<String> msgIds) async {
    if (msgIds.isEmpty) return true;
    final decoded = await _get('read_channel_msg', {
      'uin': '$uin',
      'channel': channel,
      'msg_id_list': msgIds.join(','),
    });
    return parseMsgBoxOk(decoded);
  }

  /// 删除消息（act=del_channel_msg）。空列表视为成功。
  Future<bool> delChannelMsg(String channel, List<String> msgIds) async {
    if (msgIds.isEmpty) return true;
    final decoded = await _get('del_channel_msg', {
      'uin': '$uin',
      'channel': channel,
      'msg_id_list': msgIds.join(','),
    });
    return parseMsgBoxOk(decoded);
  }

  /// 清空频道（act=clear_msg）。
  Future<bool> clearMsg(String channel) async {
    final decoded = await _get('clear_msg', {
      'uin': '$uin',
      'channel': channel,
    });
    return parseMsgBoxOk(decoded);
  }
}
