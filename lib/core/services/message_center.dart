/// 消息中心 / 邮件客户端 —— /miniw/msgcenter。
/// 移植自反编译源码 messagecenterdatamgr.lua：
///   - fetch_msgflow / fetch_msgflow_history: 消息流(新增type=1/删除type=2/变更type=3)
///   - fetch_msgbyids: 按 id 批量取详情
///   - read_message / delete_message / take_attachments: 已读/删除/领附件
///   - fetch_reddot: 官方邮件红点数
/// 签名与 dynamics 相同(http_getParamMD5)，路径不同。
library;

import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart'
    show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';

/// 本模块日志标签。
const String _logTag = 'MsgCenter';

/// 消息中心路径。
const String kMsgCenterPath = 'miniw/msgcenter';

/// 邮件/消息频道 id（对齐 MainChatSystemMsg.systemTabList，
/// mainchatsystemmsg.lua:16-63；新消息中心 7 分类）。
///
/// 左列分类与频道：礼物消息=10005 / 官方邮件=1 / 创作者助手=20001 /
/// 系统消息=20002 / 好友邮件=2 / 动态助手=0 / 运营活动=20003。
/// 其中频道 1/2/10005/20001/20002/20003 走 `/miniw/msgcenter`；
/// **动态助手 channelID=0 不走 msgcenter**，而是 `/miniw/msg_box` 的
/// `post_sys` 频道（见 [MsgBoxChannel.sys]）。
class MsgChannel {
  static const int systemMail = 1; // 官方邮件
  static const int friendMail = 2; // 好友邮件
  static const int creator = 20001; // 创作者助手
  static const int sysMsg = 20002; // 系统消息
  static const int activity = 20003; // 运营活动
  static const int gift = 10005; // 礼物消息

  /// 动态助手（对齐 systemTabList channelID="0"，数据走 msg_box post_sys）。
  static const int activityAssistant = 0;

  /// 左列 7 分类显示顺序（按参考截图自上而下）。
  static const List<int> categoryOrder = [
    gift,
    systemMail,
    creator,
    sysMsg,
    friendMail,
    activityAssistant,
    activity,
  ];

  /// 走 `/miniw/msgcenter` 的左列频道（排除动态助手）。
  static const List<int> mailChannels = [
    gift,
    systemMail,
    creator,
    sysMsg,
    friendMail,
    activity,
  ];

  static const Map<int, String> names = {
    systemMail: '官方邮件',
    friendMail: '好友邮件',
    creator: '创作者助手',
    sysMsg: '系统消息',
    activity: '运营活动',
    gift: '礼物消息',
    activityAssistant: '动态助手',
  };

  static String name(int id) => names[id] ?? '频道$id';

  // ── 旧版 msgsys_tree 频道（互动消息 4 及其子频道 10001-10004）──
  // 旧消息中心的"互动消息"聚合页；新 UI 已由顶部
  // 动态互动(post_rep/post_prize/post_at) 与 新增粉丝/作品互动(msg_box) 取代。
  // 保留常量仅作协议参考，新代码禁止使用。
  @Deprecated('旧消息中心 msgsys_tree 子频道，已由 msg_box 互动通知取代')
  static const int interact = 4; // 旧：互动消息
  @Deprecated('旧消息中心 msgsys_tree 子频道，已由 msg_box 互动通知取代')
  static const int commentMe = 10001; // 旧：评论我的
  @Deprecated('旧消息中心 msgsys_tree 子频道，已由 msg_box 互动通知取代')
  static const int likeMe = 10002; // 旧：点赞我的
  @Deprecated('旧消息中心 msgsys_tree 子频道，已由 msg_box 互动通知取代')
  static const int topComment = 10003; // 旧：评论置顶
  @Deprecated('旧消息中心 msgsys_tree 子频道，已由 msg_box 互动通知取代')
  static const int atMe = 10004; // 旧：@我的
}

/// 频道计数摘要（`fetch_channels_info` 单频道条目）。
class ChannelSummary {
  final int channel;

  /// 未读数（`fetch_channels_info` 的计数语义按未读处理）。
  final int unread;

  /// 总数；缺失时回退为 [unread]。
  final int total;

  const ChannelSummary({
    required this.channel,
    this.unread = 0,
    this.total = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is ChannelSummary &&
      other.channel == channel &&
      other.unread == unread &&
      other.total == total;

  @override
  int get hashCode => Object.hash(channel, unread, total);
}

/// 纯解析 `fetch_channels_info` 响应 → {频道 id: 摘要}。
///
/// 调研笔记只确认入参 `channellist` 与计数由 `data` 承载，未固化字段名，
/// 因此按容错解析：`data` 可为 {频道: 计数}、`channles`/`channels` 包裹对象
/// 或 `[{channel, count}]` 数组；计数可为数字 / 数字字符串 / 含
/// `unread`/`count`/`total` 等键的对象。解析不了的条目跳过；非零
/// `code`/`ret`、非 Map 响应 → 空结果。绝不抛异常。
Map<int, ChannelSummary> parseChannelsInfo(Object? decoded) {
  if (decoded is! Map) return {};
  final m = decoded.cast<String, Object?>();
  if (!_retOk(m)) return {};
  final data = m['data'];
  if (data is Map) {
    final dm = data.cast<String, Object?>();
    for (final k in const ['channles', 'channels', 'channellist', 'list']) {
      final nested = dm[k];
      if (nested is Map) return _summariesFromMap(nested.cast<String, Object?>());
      if (nested is List) return _summariesFromList(nested);
    }
    return _summariesFromMap(dm);
  }
  if (data is List) return _summariesFromList(data);
  return {};
}

Map<int, ChannelSummary> _summariesFromMap(Map<String, Object?> m) {
  final out = <int, ChannelSummary>{};
  for (final e in m.entries) {
    final ch = int.tryParse(e.key);
    if (ch == null) continue;
    final s = _summaryFromValue(ch, e.value);
    if (s != null) out[ch] = s;
  }
  return out;
}

Map<int, ChannelSummary> _summariesFromList(List<Object?> list) {
  final out = <int, ChannelSummary>{};
  for (final e in list) {
    if (e is! Map) continue;
    final em = e.cast<String, Object?>();
    final ch = _asInt(em['channelid'] ??
        em['channel_id'] ??
        em['channel'] ??
        em['id']);
    if (ch <= 0) continue;
    final s = _summaryFromValue(ch, em);
    if (s != null) out[ch] = s;
  }
  return out;
}

ChannelSummary? _summaryFromValue(int ch, Object? v) {
  if (v is num) {
    return ChannelSummary(channel: ch, unread: v.toInt(), total: v.toInt());
  }
  if (v is String) {
    final n = int.tryParse(v);
    if (n == null) return null;
    return ChannelSummary(channel: ch, unread: n, total: n);
  }
  if (v is Map) {
    final m = v.cast<String, Object?>();
    final unread = _asInt(_firstOf(m, const [
      'unread',
      'unread_count',
      'unreadcount',
      'new',
      'news',
      'news_count',
      'newcount',
      'count',
      'cnt',
      'num',
      'msgcount',
      'msg_count',
    ]));
    final total = _asInt(_firstOf(m, const [
      'total',
      'msgtotal',
      'msg_total',
      'all',
      'msgcount',
      'msg_count',
    ]));
    return ChannelSummary(
      channel: ch,
      unread: unread,
      total: total > 0 ? total : unread,
    );
  }
  return null;
}

Object? _firstOf(Map<String, Object?> m, List<String> keys) {
  for (final k in keys) {
    if (m.containsKey(k)) return m[k];
  }
  return null;
}

int _asInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// 校验 `code` / `ret`：存在且为 0 → 成功；非零 / 非数字 → 失败。
bool _retOk(Map<String, Object?> m) {
  for (final key in const ['ret', 'code']) {
    final v = m[key];
    if (v == null) continue;
    if (v is num) return v == 0;
    final n = int.tryParse('$v');
    return n != null && n == 0;
  }
  return true;
}

/// 邮件附件（extra.attach 条目）。
class MailAttachment {
  final int id;
  final int count;
  final String name;
  final String icon;

  const MailAttachment({
    required this.id,
    this.count = 0,
    this.name = '',
    this.icon = '',
  });

  static MailAttachment fromItem(Map<String, Object?> m) {
    final rawId = m['id'] ?? m['item_id'];
    final rawCount = m['num'] ?? m['count'];
    return MailAttachment(
      id: rawId is int
          ? rawId
          : int.tryParse('$rawId') ?? 0,
      count: rawCount is int
          ? rawCount
          : int.tryParse('$rawCount') ?? 0,
      name: m['name']?.toString() ?? '',
      icon: m['icon']?.toString() ?? m['icon_url']?.toString() ?? '',
    );
  }
}

/// 一条邮件/系统消息详情。
class MsgItem {
  final String id;
  final int channel;
  final int type; // email_comm_type (0=normal, 25=sendFriendGift, 26=sendRedPocket ...)
  final String title;
  final String content;
  final int createTime;
  final int readState; // 0=未读 1=已读 2=已删除
  final String? image;
  final List<String> images;
  final List<MailAttachment> attach;
  final String jumpTo;
  final String jumpName;

  /// 附件是否已领取（服务器 take_attachments 返回 data[id] 非空后置 true）。
  bool attachmentTaken;

  MsgItem({
    required this.id,
    required this.channel,
    this.type = 0,
    this.title = '',
    this.content = '',
    this.createTime = 0,
    this.readState = 0,
    this.image,
    this.images = const [],
    this.attach = const [],
    this.jumpTo = '',
    this.jumpName = '',
    this.attachmentTaken = false,
  });

  bool get unread => readState == 0;

  MsgItem copyWith({
    int? readState,
    bool? attachmentTaken,
  }) =>
      MsgItem(
        id: id,
        channel: channel,
        type: type,
        title: title,
        content: content,
        createTime: createTime,
        readState: readState ?? this.readState,
        image: image,
        images: images,
        attach: attach,
        jumpTo: jumpTo,
        jumpName: jumpName,
        attachmentTaken: attachmentTaken ?? this.attachmentTaken,
      );

  static MsgItem fromDetail(int channel, Map<String, Object?> m) {
    final id = '${m['id'] ?? m['msgid'] ?? 0}';
    final images = <String>[];
    final rawImages = m['images'];
    if (rawImages is List) {
      for (final e in rawImages) {
        final s = e?.toString();
        if (s != null && s.isNotEmpty) images.add(s);
      }
    }
    final single = m['image']?.toString();
    if (single != null && single.isNotEmpty && !images.contains(single)) {
      images.add(single);
    }

    var attach = <MailAttachment>[];
    var jumpTo = '';
    var jumpName = '';
    final extra = m['extra'];
    if (extra is Map) {
      final ex = extra.cast<String, Object?>();
      final rawAttach = ex['attach'];
      if (rawAttach is List) {
        attach = rawAttach
            .whereType<Map>()
            .map((e) => MailAttachment.fromItem(e.cast<String, Object?>()))
            .toList();
      }
      final jump = ex['jump'];
      if (jump is Map) {
        final jm = jump.cast<String, Object?>();
        jumpTo = jm['jump_to']?.toString() ?? '';
        jumpName = jm['jump_name']?.toString() ?? '';
        final ji = jm['images'];
        if (ji is List) {
          for (final e in ji) {
            final s = e?.toString();
            if (s != null && s.isNotEmpty) images.add(s);
          }
        }
        if (jumpTo.isEmpty) {
          final jt = jm['image_jump_to'];
          jumpTo = jt?.toString() ?? '';
        }
      }
    }

    int ts = 0;
    final t = m['create_time'] ?? m['createtime'] ?? m['time'] ?? m['ts'];
    if (t is num) {
      ts = t.toInt();
    } else {
      ts = int.tryParse('$t') ?? 0;
    }

    final readRaw = m['readState'] ?? m['read_state'] ?? m['readstate'];
    // 详情另有 status 位域（1=已读 2=已领取 3=both），readState 缺失时用它兜底。
    final statusRaw = m['status'];
    final status = statusRaw is num
        ? statusRaw.toInt()
        : int.tryParse('$statusRaw') ?? 0;
    final readState = readRaw != null
        ? (readRaw is num ? readRaw.toInt() : int.tryParse('$readRaw') ?? 0)
        : (status & 1) != 0
            ? 1
            : 0;

    return MsgItem(
      id: id,
      channel: channel,
      type: (m['type'] is num
              ? (m['type'] as num)
              : int.tryParse('${m['type']}') ?? 0)
          .toInt(),
      title: m['title']?.toString() ?? '',
      content: m['content']?.toString() ?? '',
      createTime: ts,
      readState: readState,
      images: images,
      attach: attach,
      jumpTo: jumpTo,
      jumpName: jumpName,
      attachmentTaken: (status & 2) != 0,
    );
  }
}

/// 消息中心客户端。
class MessageCenterClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  MessageCenterClient({
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
    return '$base/$kMsgCenterPath?${parts.join('&')}&md5=$md5';
  }

  Future<Map<String, Object?>> _get(String act,
      [Map<String, String> params = const {}]) async {
    final url = _url(act, params);
    log.debug('$act url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('$act RAW: $raw', tag: _logTag);
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  /// 拉取消息流。返回 `(新增条目, msgtotal)`；type!=1（删除/变更）被过滤。
  /// [lastTime]=0 拉最新，非 0 按历史时间游标。
  Future<(List<MsgFlowEntry>, int)> fetchMsgFlow(int channel,
      {int lastTime = 0, bool history = false}) async {
    final ret = await _get(
      history ? 'fetch_msgflow_history' : 'fetch_msgflow',
      {
        'channelid': '$channel',
        'lasttime': '$lastTime',
      },
    );
    if (ret['ret'] is num && ret['ret'] != 0) return (<MsgFlowEntry>[], 0);
    final data = ret['data'];
    if (data is! Map) return (<MsgFlowEntry>[], 0);
    final dm = data.cast<String, Object?>();
    final total = dm['msgtotal'] is num
        ? (dm['msgtotal'] as num).toInt()
        : int.tryParse('${dm['msgtotal']}') ?? 0;
    final out = <MsgFlowEntry>[];
    final rawList = dm['flowlist'];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is! Map) continue;
        final m = e.cast<String, Object?>();
        final id = '${m['msgid']}';
        if (id == 'null' || id.isEmpty) continue;
        final type = (m['type'] is num
                ? (m['type'] as num)
                : int.tryParse('${m['type']}') ?? 0)
            .toInt();
        final ts = (m['ts'] is num
                ? (m['ts'] as num)
                : int.tryParse('${m['ts']}') ?? 0)
            .toInt();
        if (type == 1) out.add(MsgFlowEntry(id: id, type: type, ts: ts));
      }
    }
    return (out, total);
  }

  /// 批量取详情。返回 `{msgid → MsgItem}`。
  Future<Map<String, MsgItem>> fetchMsgByIDs(int channel, List<String> ids) async {
    if (ids.isEmpty) return {};
    final jsonList = ids.map((e) => '"$e"').join(',');
    final ret = await _get('fetch_msgbyids', {
      'json': '1',
      'channelid': '$channel',
      'idlist': '[$jsonList]',
    });
    if (ret['ret'] is num && ret['ret'] != 0) return {};
    final data = ret['data'];
    if (data is! Map) return {};
    final out = <String, MsgItem>{};
    for (final e in data.entries) {
      if (e.value is! Map) continue;
      final item = MsgItem.fromDetail(channel, (e.value as Map).cast<String, Object?>());
      out['${e.key}'] = item;
    }
    return out;
  }

  /// 标记已读。
  Future<bool> readMessages(int channel, List<String> ids) async {
    if (ids.isEmpty) return true;
    final jsonList = ids.map((e) => '"$e"').join(',');
    final ret = await _get('read_message', {
      'channelid': '$channel',
      'ids': '[$jsonList]',
    });
    return ret['ret'] is num && ret['ret'] == 0;
  }

  /// 删除消息。
  Future<bool> deleteMessages(int channel, List<String> ids) async {
    if (ids.isEmpty) return true;
    final jsonList = ids.map((e) => '"$e"').join(',');
    final ret = await _get('delete_message', {
      'channelid': '$channel',
      'ids': '[$jsonList]',
    });
    return ret['ret'] is num && ret['ret'] == 0;
  }

  /// 领取附件。返回领取成功的 msgid 集合（服务器 ret.data[id] 非空）。
  Future<Set<String>> takeAttachments(int channel, List<String> ids) async {
    if (ids.isEmpty) return {};
    final jsonList = ids.map((e) => '"$e"').join(',');
    final ret = await _get('take_attachments', {
      'channelid': '$channel',
      'ids': '[$jsonList]',
    });
    final ok = <String>{};
    final data = ret['data'];
    if (data is Map) {
      for (final e in data.entries) {
        final v = e.value;
        if (v is List && v.isNotEmpty) ok.add('${e.key}');
      }
    }
    return ok;
  }

  /// 官方邮件红点数（频道 1）。返回未读数。
  Future<int> fetchReddot() async {
    final ret = await _get('fetch_reddot', {'json': '1', 'channellist': '1'});
    final data = ret['data'];
    if (data is Map) {
      final ch = data['channles'];
      if (ch is Map) {
        final v = ch['1'];
        if (v is num) return v.toInt();
        final n = int.tryParse('$v');
        if (n != null) return n;
      }
    }
    return 0;
  }

  /// 批量拉取频道计数（act=fetch_channels_info，入参 `channellist` JSON 数组）。
  /// 返回 `{频道: 摘要}`；失败 / 解析不了返回空 map（解析见 [parseChannelsInfo]）。
  Future<Map<int, ChannelSummary>> fetchChannelsInfo(List<int> channels) async {
    if (channels.isEmpty) return {};
    final list = channels.map((c) => '$c').join(',');
    final ret = await _get('fetch_channels_info', {'channellist': '[$list]'});
    return parseChannelsInfo(ret);
  }
}

/// 消息流条目（fetch_msgflow 的 flowlist 元素，type=1 保留）。
class MsgFlowEntry {
  final String id;
  final int type; // 1=新增 2=删除 3=变更
  final int ts;

  const MsgFlowEntry({required this.id, required this.type, required this.ts});
}
