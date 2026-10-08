/// 动态(Posting)服务客户端 —— /miniw/posting 与 /miniw/com_posting。
/// 移植自反编译源码 dynamicsdatamanager.lua：
///   - 好友 feed: POSTING + get_friend_posting (+ from)
///   - 热门/时间: COM_POSTING + get_list_by_hot / get_list_by_time (+ offset)
/// URL 用 act + http_getParamMD5 签名。
library;

import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart'
    show httpGetParamKey, httpGetParamMd5, httpGetS1Map, httpGetS2Act;
import '../net/config.dart' show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../net/photo_upload.dart' show uploadPresignedFile;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';
import 'request_errors.dart' show reportIfFailed;

/// 本模块日志标签。
const String _logTag = 'Dynamics';

const String kCountry = 'CN';
const String kLang = '0';

const String kPostingPath = 'miniw/posting';
const String kComPostingPath = 'miniw/com_posting';

/// 动态图片（带宽高，用于按自身宽高比排版；无宽高时由 UI 兜底）。
class PostImage {
  final String url;
  final int width;
  final int height;

  const PostImage({required this.url, this.width = 0, this.height = 0});

  /// 宽高比（宽/高），无效时返回 [kDefaultAspect]。
  double get aspect {
    if (width > 0 && height > 0) return width / height;
    return 0;
  }
}

const double kDefaultAspect = 1.5;

/// 一页动态 + 下一页游标（data.ct）。nextCt==0 表示没有更多。
class FeedResult {
  final List<DynamicsPost> posts;
  final int nextCt;

  const FeedResult(this.posts, this.nextCt);
}

/// 动态 feed 类型（对应动态大厅的 tab，均在 /miniw/posting）。
enum DynamicsFeedType {
  recommend('推荐', 'get_friend_posting'),
  hot('热门', 'get_hot_posting2'),
  city('同城', 'get_city_posting2'),
  official('官方', 'get_official_posting'),
  mine('我的', 'get_posting_list');

  const DynamicsFeedType(this.label, this.act);
  final String label;
  final String act;
}

/// 从多候选键取首个数值（数值或数值字符串）；都没有 → 0。
/// 宽松解析：脏/缺省数据一律降级为 0，绝不抛。
int _pickInt(Map<String, Object?> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is num) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return n;
    }
  }
  return 0;
}

/// 一条动态。
/// 从头像框字段解析 head_frame_id（数值或字符串；缺省/0 视为无框）。
int? _headFrameId(Map<String, Object?> m) {
  for (final k in ['head_frame_id', 'headFrameId']) {
    final v = m[k];
    if (v is num && v.toInt() > 0) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null && n > 0) return n;
    }
  }
  return null;
}

class DynamicsPost {
  /// 动态 id，形如 `"<uin>_<ct>"`（如 "273640665_1787757890"）。
  final String pid;
  final int uin;
  final String content;
  final int createTime; // 秒
  final int ctype;
  final String? nickname;
  final String? avatar;

  /// 头像框 id（role_info_list.head_frame_id，对应 `assets/headframes/<id>.png`）。
  final int? headFrameId;

  /// 图片列表（带宽高）。
  final List<PostImage> pics;

  /// 属地（city / location）。
  final String city;
  final String location;

  /// 点赞 / 评论 / 转发数。
  final int likeCount;
  final int commentCount;
  final int shareCount;

  /// 附加信息：作品/地图链接名（evaluate_extract_info.name / com_map_info）。
  final String? linkName;
  final String? linkAuthor;

  /// 是否抽奖/投票。
  final bool isLottery;

  /// 可见范围（对齐反编译 `DynamicConstant.AUTH`，dynamicsdatamanager.lua:94）。
  final int authSee;

  /// 视频资源 id（`video_res_id`）；非空即视频动态。
  final String? videoResId;

  /// 关联话题列表（`topic_list`）。
  final List<DynamicsTopic> topics;

  /// 抽奖 id（`lottery_id`）；非空即抽奖动态。
  final String? lotteryId;

  /// 投票 id（`vote_id` / 转发投票 `share_vote`）；非空即投票动态。
  final String? voteId;

  const DynamicsPost({
    required this.pid,
    required this.uin,
    required this.content,
    this.createTime = 0,
    this.ctype = 0,
    this.nickname,
    this.avatar,
    this.headFrameId,
    this.pics = const [],
    this.city = '',
    this.location = '',
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.linkName,
    this.linkAuthor,
    this.isLottery = false,
    this.authSee = 0,
    this.videoResId,
    this.topics = const [],
    this.lotteryId,
    this.voteId,
  });

  static int _int(Map<String, Object?> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  /// 从 pic_list（[{url, width, height, ...}]）提取图片列表。
  static List<PostImage> _picUrls(Map<String, Object?> m) {
    final pl = m['pic_list'];
    if (pl is! List) return const [];
    final out = <PostImage>[];
    for (final e in pl) {
      if (e is Map) {
        final u = e['url']?.toString();
        if (u != null && u.isNotEmpty) {
          final w = e['width'] is num ? (e['width'] as num).toInt() : 0;
          final h = e['height'] is num ? (e['height'] as num).toInt() : 0;
          out.add(PostImage(url: u, width: w, height: h));
        }
      }
    }
    return out;
  }

  static DynamicsPost? fromItem(Map<String, Object?> m) {
    // pid：可能是数字，也可能是 "uin_ct" 字符串（真实服务器返回字符串）。
    final rawPid = m['pid'] ?? m['posting_id'] ?? m['id'];
    String pid = '';
    int uin = _int(m, ['uin', 'Uin', 'author_uin']);
    int ct = _int(m, ['create_time', 'ct', 'time', 'send_time']);
    if (rawPid is String) {
      pid = rawPid;
      final idx = rawPid.indexOf('_');
      if (idx > 0) {
        if (uin == 0) uin = int.tryParse(rawPid.substring(0, idx)) ?? 0;
        if (ct == 0) ct = int.tryParse(rawPid.substring(idx + 1)) ?? 0;
      }
    } else if (rawPid is num) {
      pid = '${rawPid.toInt()}';
      if (uin == 0) uin = rawPid.toInt();
    }
    if (pid.isEmpty) return null;

    String? linkName;
    String? linkAuthor;
    final ev = m['evaluate_extract_info'];
    if (ev is Map) {
      linkName = ev['name']?.toString();
      linkAuthor = ev['author_uin']?.toString();
    }
    if (linkName == null) {
      final cm = m['com_map_info'];
      if (cm is Map) {
        linkName = cm['name']?.toString();
        linkAuthor = cm['uin']?.toString();
      }
    }

    return DynamicsPost(
      pid: pid,
      uin: uin,
      content: m['content']?.toString() ?? '',
      createTime: ct,
      ctype: _int(m, ['ctype', 'content_type']),
      nickname: m['nickname']?.toString() ?? m['NickName']?.toString(),
      avatar: m['header']?.toString() ?? m['avatar']?.toString(),
      pics: _picUrls(m),
      city: m['city']?.toString() ?? '',
      location: m['location']?.toString() ?? '',
      likeCount: _int(m, ['prize_count', 'cai', 'like_count']),
      commentCount: _int(m, ['comment_count', 'comment_num']),
      shareCount: _int(m, ['share', 'forward_count']),
      linkName: linkName,
      linkAuthor: linkAuthor,
      isLottery: m['com_lottery'] == 1 || m['lottery_id'] != null,
      authSee: _pickInt(m, ['auth_see', 'authSee']),
      videoResId: _nonEmpty(m['video_res_id'] ?? m['videoResId']),
      topics: _parseTopicList(m['topic_list']),
      lotteryId: _nonEmpty(m['lottery_id'] ?? m['lotteryId']),
      voteId: _nonEmpty(m['vote_id'] ?? m['share_vote'] ?? m['voteId']),
    );
  }

  DynamicsPost withProfile({
    String? nickname,
    String? avatar,
    int? headFrameId,
  }) =>
      DynamicsPost(
        pid: pid,
        uin: uin,
        content: content,
        createTime: createTime,
        ctype: ctype,
        nickname: nickname ?? this.nickname,
        avatar: avatar ?? this.avatar,
        headFrameId: headFrameId ?? this.headFrameId,
        pics: pics,
        city: city,
        location: location,
        likeCount: likeCount,
        commentCount: commentCount,
        shareCount: shareCount,
        linkName: linkName,
        linkAuthor: linkAuthor,
        isLottery: isLottery,
        authSee: authSee,
        videoResId: videoResId,
        topics: topics,
        lotteryId: lotteryId,
        voteId: voteId,
      );
}

/// 宽松 URL 解码：脏/不完整百分号转义（实测服务端会下发）保持原样，绝不抛。
String _lenientDecode(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

/// 非空字符串；缺省 / 空白 / 字面 `"null"` → null。
String? _nonEmpty(Object? v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

/// 解析 `topic_list` → 话题列表；脏数据只跳过。
///
/// 动态条目上的 `topic_list` 实测是**字符串数组**（如 `["u:1813749331:1704717010"]`），
/// 而 `get_topic_list` 返回的是对象数组（`{topic_id, title}`）；两种都支持。
List<DynamicsTopic> _parseTopicList(Object? raw) {
  if (raw is List) {
    final out = <DynamicsTopic>[];
    for (final e in raw) {
      if (e is Map) {
        final t = DynamicsTopic.fromItem(e.cast<String, Object?>());
        if (t != null) out.add(t);
      } else if (e is String && e.trim().isNotEmpty) {
        out.add(DynamicsTopic(topicId: e.trim()));
      }
    }
    return out;
  }
  if (raw is Map) {
    final out = <DynamicsTopic>[];
    for (final e in raw.entries) {
      if (e.value is! Map) continue;
      final t = DynamicsTopic.fromItem((e.value as Map).cast<String, Object?>());
      if (t != null) out.add(t);
    }
    return out;
  }
  return const [];
}

/// 一条评论。
class DynamicsComment {
  final int uin;
  final String content;
  final int createTime;
  final String? nickname;
  final String? avatar;

  /// 头像框 id（role_info_list.head_frame_id）。
  final int? headFrameId;
  final int likeCount;
  final int replyCount;

  /// 属地（location）。
  final String location;

  // ── 父评论定位字段（回复接口 get_comment_rep 必需）────────────────────
  /// 动态作者 uin（pid 前半段）与动态 ct（pid 后半段）。
  final int pidUin;
  final int pidCt;

  /// 评论作者 uin（= uin，回复接口的 com_uin）。
  final int opUin;

  /// 评论 last_time（回复/分页游标用）。
  final int lastTime;

  /// 回复条目 id（`rep_id`）；一级评论为 0/空。
  ///
  /// 回复的点赞/删除接口（prize_comment_rep / delete_*_comment_rep）用它定位。
  final String repId;

  /// 「回复给谁」的目标 uin：有被回复者（`op_uin`）时为它，否则为评论作者。
  ///
  /// 注意与线上的 [opUin] 区分：`com_op_uin` 定位参数要用 [opUin] 原值，
  /// 而 `add_comment_rep` 的 `op_uin` 参数要用本值。
  int get replyTargetUin => opUin != 0 ? opUin : uin;

  const DynamicsComment({
    required this.uin,
    required this.content,
    this.createTime = 0,
    this.nickname,
    this.avatar,
    this.headFrameId,
    this.likeCount = 0,
    this.replyCount = 0,
    this.location = '',
    this.pidUin = 0,
    this.pidCt = 0,
    this.opUin = 0,
    this.lastTime = 0,
    this.repId = '',
  });

  /// 从多个候选 key 取首个数值。
  static int _int(Map<String, Object?> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v);
        if (n != null) return n;
      }
    }
    return 0;
  }

  static DynamicsComment? fromItem(Map<String, Object?> m) {
    final rawUin = m['uin'] ?? m['Uin'] ?? m['sender'] ?? 0;
    final uin = rawUin is num ? rawUin.toInt() : int.tryParse('$rawUin') ?? 0;
    // 回复条目用 rep_uin（回复者）；评论用 uin。
    final rawRep = m['rep_uin'];
    final repUin = rawRep is num
        ? rawRep.toInt()
        : int.tryParse('$rawRep') ?? 0;
    final authorUin = repUin != 0 ? repUin : uin;
    // content 是 URL 编码（UTF-8），需解码（脏转义必须降级为原文，不能抛）。
    final content = _lenientDecode(m['content']?.toString() ?? '');
    if (content.isEmpty) return null;
    int time = 0;
    // 评论/回复时间：评论用 last_time；回复用 rep_time。
    final t = m['last_time'] ?? m['rep_time'] ?? m['time'] ?? m['ct'];
    if (t is num) {
      time = t.toInt();
    } else {
      time = int.tryParse('$t') ?? 0;
    }
    // 回复数：评论用 com_cnt；回复条目可能无。
    final like = m['cai'] ?? m['like_count'] ?? m['prize'] ?? 0;
    final reply = m['com_cnt'] ?? m['reply_count'] ?? 0;
    // 父动态定位字段：优先条目自带 pid_uin/pid_ct；缺失时尝试从 pid
    // （形如 "uin_ct"）拆出，兜底用 authorUin。
    var pidUin = _int(m, ['pid_uin', 'p_uin', 'com_pid_uin']);
    var pidCt = _int(m, ['pid_ct', 'com_pid_ct']);
    if ((pidUin == 0 || pidCt == 0) && m['pid'] != null) {
      final pidParts = '${m['pid']}'.split('_');
      if (pidParts.isNotEmpty) {
        pidUin = pidUin != 0 ? pidUin : int.tryParse(pidParts[0]) ?? 0;
        if (pidCt == 0 && pidParts.length > 1) {
          pidCt = int.tryParse(pidParts[1]) ?? 0;
        }
      }
    }
    final opUinRaw = m['op_uin'] ?? m['com_op_uin'];
    final opUin = opUinRaw is num
        ? opUinRaw.toInt()
        : int.tryParse('$opUinRaw') ?? 0;
    return DynamicsComment(
      uin: authorUin,
      content: content,
      createTime: time,
      nickname: m['nickname']?.toString() ?? m['NickName']?.toString(),
      likeCount: like is num ? like.toInt() : 0,
      replyCount: reply is num ? reply.toInt() : 0,
      location: m['location']?.toString() ?? '',
      pidUin: pidUin,
      pidCt: pidCt,
      // 保持服务端原值：一级评论实测下发 op_uin=0（不能拿作者 uin 兜底，
      // 否则 get_comment_rep / prize_comment 的定位参数就对不上了 —— live 探针实测）。
      opUin: opUin,
      lastTime: _int(m, ['last_time', 'com_last_time']),
      repId: m['rep_id']?.toString() ?? '',
    );
  }

  DynamicsComment withProfile({
    String? nickname,
    String? avatar,
    int? headFrameId,
  }) =>
      DynamicsComment(
        uin: uin,
        content: content,
        createTime: createTime,
        nickname: nickname ?? this.nickname,
        avatar: avatar ?? this.avatar,
        headFrameId: headFrameId ?? this.headFrameId,
        likeCount: likeCount,
        replyCount: replyCount,
        location: location,
        pidUin: pidUin,
        pidCt: pidCt,
        opUin: opUin,
        lastTime: lastTime,
        repId: repId,
      );
}

/// 动态通知频道（对齐 DynamicsChannelType）。
class DynamicsNoticeChannel {
  static const String rep = 'post_rep'; // 评论我的
  static const String prize = 'post_prize'; // 点赞我的
  static const String at = 'post_at'; // @我的
  static const String fans = 'fans_change'; // 粉丝
  static const String sys = 'post_sys'; // 系统
  static const String mapInteract = 'map_interact'; // 地图互动

  static const Map<String, String> labels = {
    rep: '评论',
    prize: '点赞',
    at: '@我',
    fans: '粉丝',
    sys: '系统',
    mapInteract: '地图',
  };

  static String label(String c) => labels[c] ?? c;
}

/// 一条动态通知（get_channel_msg_list 的 msg_list 条目）。
///
/// 原始结构：{msg_id, msg_type, data(JSON字符串), state, ...}，
/// data 解码后与条目平铺（对齐 MergeInteractiveFunc：itemData[k]=v.data[k]，
/// type=msg_type, status=state）。展示字段：uin/nickname/content/pid 等。
class DynamicsNotice {
  final String msgId;
  final String channel;
  final String msgType;
  final int uin;
  final String nickname;
  final String content;
  final String pid;
  final int time;
  final Map<String, Object?> data;

  const DynamicsNotice({
    required this.msgId,
    required this.channel,
    this.msgType = '',
    this.uin = 0,
    this.nickname = '',
    this.content = '',
    this.pid = '',
    this.time = 0,
    this.data = const {},
  });

  /// 从 msg_list 条目构造。data 是 JSON 字符串，解码后取展示字段。
  static DynamicsNotice? fromItem(Map<String, Object?> m) {
    final msgId = '${m['msg_id'] ?? m['msgid'] ?? ''}';
    if (msgId.isEmpty || msgId == 'null') return null;
    final channel = m['channel']?.toString() ?? '';

    Map<String, Object?> flat = {};
    final rawData = m['data'];
    if (rawData is Map) {
      flat = rawData.cast<String, Object?>();
    } else if (rawData is String) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map) flat = decoded.cast<String, Object?>();
      } catch (_) {}
    }

    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final content = _safeDecode(
        (flat['content'] ?? flat['text'] ?? m['content'])?.toString() ?? '');
    return DynamicsNotice(
      msgId: msgId,
      channel: channel,
      msgType: (m['msg_type'] ?? flat['msg_type'] ?? '').toString(),
      uin: i(flat['uin'] ?? m['uin'] ?? 0),
      nickname: (flat['nickname'] ?? m['nickname'] ?? '').toString(),
      content: content,
      pid: (flat['pid'] ?? '').toString(),
      time: i(flat['time'] ?? flat['create_time'] ?? m['ts'] ?? 0),
      data: flat,
    );
  }

  static String _safeDecode(String s) => _lenientDecode(s);
}

/// 写操作统一确认（like_posting / add_posting / delete_posting / set_top /
/// create_topic / create_vote / vote / add_comment 等）。
///
/// 服务端响应 `{ret|code, msg, data?}`：
/// - [code]：`ret` 优先、其次 `code`；缺省或非数值 → 0（宽松语义，视为成功）；
/// - [message]：`msg`/`message` 文案，缺省空串；
/// - [voteInfo]：仅 create_vote 的 `data.vote_info` 载荷，其它写接口为 null。
///
/// 与 player_home.dart 的 `SetTopFlagResult` 同款：小结果对象，解析不抛。
class DynamicsAck {
  /// 业务码（0 或缺省即成功）。
  final int code;

  /// 服务端文案（msg/message）；无则空串。
  final String message;

  /// 原始 data 载荷（非 Map 或缺失时为空 map）。
  final Map<String, Object?> _data;

  /// 响应 `data` 的**原值**（可能是 List / Map / 标量）。
  ///
  /// 实测：`get_topic_list` / `get_post` 类接口的 `data` 直接就是数组，
  /// 只靠 [_data]（仅保留 Map）会把整个载荷丢掉。
  final Object? _rawData;

  /// 完整响应 map（供红点等顶层字段兜底）；不外泄。
  final Map<String, Object?> _raw;

  const DynamicsAck({this.code = 0, this.message = ''})
      : _data = const {},
        _rawData = null,
        _raw = const {};

  const DynamicsAck._full(
    this.code,
    this.message,
    this._data,
    this._rawData,
    this._raw,
  );

  /// 业务码为 0（或缺失/非数值）即视为成功。
  bool get ok => code == 0;

  /// create_vote 返回的投票信息（`data.vote_info`）；其它写接口为 null。
  DynamicsVoteInfo? get voteInfo => DynamicsVoteInfo.fromMap(_data);

  /// share_posting 返回的新转发数（`data.share`）；其它写接口为 null。
  int? get shareCount {
    final n = _pickInt(_data, ['share', 'share_count']);
    return n == 0 ? null : n;
  }

  /// 响应 `data` 载荷（非 Map 或缺失时为空 map）；供投票 / 红点等 Map 型响应取用。
  Map<String, Object?> get data => _data;

  /// 响应 `data` 原值（保持 List / Map 形态）；供话题等列表型响应取用。
  Object? get rawData => _rawData;

  /// 从响应解码结果构造；脏/缺省数据降级，绝不抛。
  static DynamicsAck fromMap(Map<String, Object?> m) {
    final raw = m['ret'] ?? m['code'];
    final data = m['data'];
    final msg = m['msg'] ?? m['message'];
    return DynamicsAck._full(
      raw is num ? raw.toInt() : 0,
      msg?.toString() ?? '',
      data is Map ? data.cast<String, Object?>() : const {},
      data,
      m,
    );
  }
}

/// 话题条目（search_topic / get_topic_list / get_hot_topic2 响应的一项）。
///
/// [topicId] 是**字符串**（真实服务端形态：官方话题 `"o:21"`、玩家话题
/// `"u:<uin>:<ct>"`）—— 实测 `get_topic_list` 返回的就是字符串，不是数字。
class DynamicsTopic {
  /// 话题 id（`topic_id` / `topicId` / `id`）。
  final String topicId;

  /// 话题标题。
  final String title;

  const DynamicsTopic({this.topicId = '', this.title = ''});

  /// 解析 data 中的话题列表；候选形态三种：
  ///   - 直接就是数组（实测 `get_topic_list` 的 `data` 即 `[{topic_id,title}]`）；
  ///   - `{topic_list: [...]}` / `{list: [...]}`；
  ///   - `{<id>: {...}}` 映射。
  /// 脏条目跳过。
  static List<DynamicsTopic> parseList(Object? data) {
    final raw = data is Map ? (data['topic_list'] ?? data['list']) : data;
    final out = <DynamicsTopic>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final t = fromItem(e.cast<String, Object?>());
          if (t != null) out.add(t);
        } else if (e is String && e.trim().isNotEmpty) {
          out.add(DynamicsTopic(topicId: e.trim()));
        }
      }
    } else if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        final t = fromItem((e.value as Map).cast<String, Object?>());
        if (t != null) out.add(t);
      }
    }
    return out;
  }

  /// 单条话题；id 与标题皆空视为脏数据 → null。
  static DynamicsTopic? fromItem(Map<String, Object?> m) {
    final raw = m['topic_id'] ?? m['topicId'] ?? m['id'];
    final id = raw?.toString().trim() ?? '';
    final title = m['title']?.toString() ?? m['topic_name']?.toString() ?? '';
    if ((id.isEmpty || id == 'null' || id == '0') && title.isEmpty) return null;
    return DynamicsTopic(
      topicId: id == 'null' ? '' : id,
      title: title,
    );
  }
}

/// 投票选项（get_vote_info / create_vote 的选项）。
class DynamicsVoteOption {
  /// 1-based 序号。
  final int index;

  /// 选项文案。
  final String text;

  /// 得票数。
  final int count;

  const DynamicsVoteOption({this.index = 0, this.text = '', this.count = 0});

  /// 单条选项；[fallbackIndex] 为条目在列表中的 1-based 位置。
  static DynamicsVoteOption? fromItem(
    Map<String, Object?> m,
    int fallbackIndex,
  ) {
    final index = _pickInt(m, ['index', 'idx', 'op_index', 'id']);
    final text = m['text']?.toString() ??
        m['title']?.toString() ??
        m['name']?.toString() ??
        m['op']?.toString() ??
        '';
    final count = _pickInt(m, ['count', 'num', 'vote_num', 'prize', 'total']);
    if (text.isEmpty && count == 0) return null;
    return DynamicsVoteOption(
      index: index != 0 ? index : fallbackIndex,
      text: text,
      count: count,
    );
  }
}

/// 投票信息（get_vote_info 的 data / create_vote 的 data.vote_info）。
class DynamicsVoteInfo {
  final String voteId;
  final String title;
  /// 结束时间（秒）。
  final int endTime;
  /// 多选模式。
  final int multiMode;
  /// 0=公开。
  final int mode;
  final List<DynamicsVoteOption> options;

  const DynamicsVoteInfo({
    this.voteId = '',
    this.title = '',
    this.endTime = 0,
    this.multiMode = 0,
    this.mode = 0,
    this.options = const [],
  });

  /// 从响应 data 解出：优先 `data.vote_info`，否则 data 本身（get_vote_info
  /// 与 create_vote 两种包裹形态）。无有效信息 → null。
  static DynamicsVoteInfo? fromMap(Map<String, Object?> data) {
    if (data.isEmpty) return null;
    final vi = data['vote_info'];
    final m = vi is Map ? vi.cast<String, Object?>() : data;
    return fromItem(m);
  }

  /// 单条投票信息；无 vote_id 且无选项 → null。
  static DynamicsVoteInfo? fromItem(Map<String, Object?> m) {
    final voteId =
        (m['vote_id'] ?? m['voteId'] ?? m['id'])?.toString() ?? '';
    final raw = m['option_list'] ??
        m['opt_list'] ??
        m['options'] ??
        m['list'] ??
        m['opts'];
    final options = <DynamicsVoteOption>[];
    if (raw is List) {
      var i = 0;
      for (final e in raw) {
        i++;
        if (e is! Map) continue;
        final o =
            DynamicsVoteOption.fromItem(e.cast<String, Object?>(), i);
        if (o != null) options.add(o);
      }
    }
    if (voteId.isEmpty && options.isEmpty) return null;
    return DynamicsVoteInfo(
      voteId: voteId,
      title: m['title']?.toString() ?? '',
      endTime: _pickInt(m, ['end_time', 'endTime']),
      multiMode: _pickInt(m, ['multi_mode', 'multiMode']),
      mode: _pickInt(m, ['mode']),
      options: options,
    );
  }
}

/// 动态可见范围（对齐反编译 `DynamicConstant.AUTH`，dynamicsdatamanager.lua:94-100）。
class DynamicsAuth {
  /// 公开。
  static const int all = 0;

  /// 仅粉丝。
  static const int onlyFans = 1;

  /// 主页隐藏。
  static const int homeHide = 2;

  /// 仅自己。
  static const int onlySelf = 3;

  /// 仅家族。
  static const int onlyFamily = 4;

  /// 可见范围 id → 中文名（与发布页 / 详情页菜单一致）。
  static const Map<int, String> labels = {
    all: '公开',
    onlyFans: '仅粉丝',
    homeHide: '主页隐藏',
    onlySelf: '仅自己',
    onlyFamily: '仅家族',
  };

  /// `setPostingAuth` 的 `ptype`：可见范围 / 评论权限 / 主页展示。
  static const String ptypeSee = 'see';
  static const String ptypeRep = 'rep';
  static const String ptypeHome = 'home';

  /// 未知 id 回退「公开」（与游戏 `auth_see` 缺省 0 一致）。
  static String label(int v) => labels[v] ?? labels[all]!;
}

/// 动态权限（`get_redpoint_notice_info` 的 `posting_edit_info` 之外，评论
/// 权限 / 主页展示开关）；宽松解析，缺省 0。
class DynamicsLottery {
  /// 抽奖 id（`lottery_id`）。
  final String lotteryId;

  /// 奖品 id / 数量 / 类型（`item_id` / `item_num` / `item_type`）。
  final int itemId;
  final int itemNum;
  final int itemType;

  /// 开奖人数（`select_num`）与参与消耗（`cost_num`）。
  final int selectNum;
  final int costNum;

  /// 开奖时间（秒）。
  final int lotteryTime;

  /// 任务 id 串（`task`，逗号分隔）。
  final String task;

  /// 状态（`status`）：2/3 为可展示（进行中 / 已结束，见
  /// `dynamicsinfocardlottery.lua:34`）。
  final int status;

  /// 参与人数（`join_count` / `join_num`）。
  final int joinCount;

  /// 发起人 uin（`uin` / `author_uin`）。
  final int uin;

  /// 是否本人发起（`is_author`）。
  final bool isAuthor;

  const DynamicsLottery({
    this.lotteryId = '',
    this.itemId = 0,
    this.itemNum = 0,
    this.itemType = 0,
    this.selectNum = 0,
    this.costNum = 0,
    this.lotteryTime = 0,
    this.task = '',
    this.status = 0,
    this.joinCount = 0,
    this.uin = 0,
    this.isAuthor = false,
  });

  /// 进行中 / 已结束（可展示）。
  bool get displayable => status == 2 || status == 3;

  /// 解析 `posting_lottery_query_lottery` 的 `data.list` / 单条对象。
  ///
  /// 载荷可能是 `{lottery_id: {...}}` 映射、`[{...}]` 数组、或
  /// `{list: [...]}`；三种都接受，脏条目跳过。
  static List<DynamicsLottery> parseList(Object? data) {
    final raw = data is Map ? (data['list'] ?? data['lottery_list'] ?? data) : data;
    final out = <DynamicsLottery>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final l = fromItem(e.cast<String, Object?>());
        if (l != null) out.add(l);
      }
    } else if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        final l = fromItem((e.value as Map).cast<String, Object?>());
        if (l != null) out.add(l);
      }
    }
    return out;
  }

  /// 单条抽奖；无 lottery_id → null。
  static DynamicsLottery? fromItem(Map<String, Object?> m) {
    final id = _nonEmpty(m['lottery_id'] ?? m['lotteryId'] ?? m['id']);
    if (id == null) return null;
    final isAuthor = m['is_author'];
    return DynamicsLottery(
      lotteryId: id,
      itemId: _pickInt(m, ['item_id', 'itemId']),
      itemNum: _pickInt(m, ['item_num', 'itemNum']),
      itemType: _pickInt(m, ['item_type', 'itemType']),
      selectNum: _pickInt(m, ['select_num', 'selectNum']),
      costNum: _pickInt(m, ['cost_num', 'costNum']),
      lotteryTime: _pickInt(m, ['lottery_time', 'lotteryTime']),
      task: m['task']?.toString() ?? '',
      status: _pickInt(m, ['status', 'state']),
      joinCount: _pickInt(m, ['join_count', 'join_num', 'joinCount']),
      uin: _pickInt(m, ['uin', 'author_uin']),
      isAuthor: isAuthor == true || isAuthor == 1 || isAuthor == '1',
    );
  }
}

/// 动态红点（get_redpoint_notice_info）。
///
/// 字段可直接在响应顶层，也可包在 `data` 下；缺省 → 0。
class DynamicsRedpointNotice {
  /// 未读动态通知数（new_posting_notice）。
  final int newPostingNotice;

  /// 动态编辑信息（posting_edit_info）。
  final int postingEditInfo;

  const DynamicsRedpointNotice({
    this.newPostingNotice = 0,
    this.postingEditInfo = 0,
  });

  /// 从完整响应解出；脏/缺省数据降级为 0，绝不抛。
  static DynamicsRedpointNotice fromResponse(Map<String, Object?> m) {
    final data = m['data'];
    final src = data is Map ? data.cast<String, Object?>() : m;
    return DynamicsRedpointNotice(
      newPostingNotice:
          _pickInt(src, ['new_posting_notice', 'newPostingNotice']),
      postingEditInfo: _pickInt(src, ['posting_edit_info', 'postingEditInfo']),
    );
  }
}

/// 动态大厅分类标签（`act=get_posting_tag_list`）。
///
/// 服务端下发 `tag_id` / `title`；`ParseTabCfgs` 另外用 `editable` 标记允许
/// 用户自定义排序的分类（`dynamicsdatamanager.lua:6752-6800`）。内置的 1/2/3/4
/// 即 推荐/关注/同城/官方（`DynamicHallTabType`），其余为服务端配置的分类
/// （拉列表时走 `get_posting_by_tag`）。
class DynamicsTag {
  /// 分类 id（`tag_id`）。
  final int tagId;

  /// 分类标题（`title`）。
  final String title;

  const DynamicsTag({this.tagId = 0, this.title = ''});

  /// 解析响应：支持 `[{tag_id,title}]` / `{list|tag_list|data:[...]}` /
  /// `{<id>:{...}}` 三种形态；脏条目跳过，绝不抛。
  static List<DynamicsTag> parseList(Object? data) {
    Object? raw = data;
    if (raw is Map) {
      // 包裹形态取内层；都不是时把整个 Map 当 `{<id>: {...}}` 映射。
      raw = raw['tag_list'] ?? raw['list'] ?? raw['data'] ?? raw;
    }
    final out = <DynamicsTag>[];
    void add(int fallbackId, Object? e) {
      if (e is! Map) return;
      final m = e.cast<String, Object?>();
      final id = _pickInt(m, ['tag_id', 'tagId', 'id']);
      final tagId = id != 0 ? id : fallbackId;
      if (tagId == 0) return;
      final title = m['title']?.toString() ?? m['name']?.toString() ?? '';
      out.add(DynamicsTag(tagId: tagId, title: title));
    }

    if (raw is List) {
      for (final e in raw) {
        add(0, e);
      }
    } else if (raw is Map) {
      for (final e in raw.entries) {
        add(int.tryParse('${e.key}') ?? 0, e.value);
      }
    }
    return out;
  }
}

/// 动态客户端。
class DynamicsClient {
  final int uin;
  final String s2;
  final String s2t;
  final Dio _dio;
  final String baseUrl;

  DynamicsClient({
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
    // 通用鉴权参数（url_addParams 注入，同时进 md5 与 URL）
    final all = <String, String>{
      'act': act,
      'uin': '$uin',
      'apiid': kApiId,
      'ver': kClientVersionStr,
      'country': kCountry,
      'lang': kLang,
      ...params,
    };
    final md5 = httpGetParamMd5(all, timeVal: now, s2: s2, s2t: s2t, key: httpGetParamKey);
    // 对齐 Lua http_getParamMD5：md5 用 s2，但 URL query 不含 s2；
    // 需显式带上 time/s2t/encrypt_ver（供服务器复算 md5）。
    final parts = <String>[
      ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    return '$base/$kPostingPath?${parts.join('&')}&md5=$md5';
  }

  /// 自定义路径的签名 URL（posting_topic / customize_vote 等）。
  /// [path] 为相对路径（如 'posting_topic'）；path 尾随 '/' 时保留。
  String _url2(String path, String act, [Map<String, String> params = const {}]) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final all = <String, String>{
      'act': act,
      'uin': '$uin',
      'apiid': kApiId,
      'ver': kClientVersionStr,
      'country': kCountry,
      'lang': kLang,
      ...params,
    };
    final md5 = httpGetParamMd5(all, timeVal: now, s2: s2, s2t: s2t, key: httpGetParamKey);
    final parts = <String>[
      ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    final tag = path.startsWith('miniw/') ? path : 'miniw/$path';
    final p = tag.endsWith('/') ? tag : tag;
    return '$base/$p?${parts.join('&')}&md5=$md5';
  }

  /// 与 [_url2] 相同，但保证路径尾随 '/'（customize_vote/ 接口需要）。
  String _url3(String path, String act, [Map<String, String> params = const {}]) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final all = <String, String>{
      'act': act,
      'uin': '$uin',
      'apiid': kApiId,
      'ver': kClientVersionStr,
      'country': kCountry,
      'lang': kLang,
      ...params,
    };
    final md5 = httpGetParamMd5(all, timeVal: now, s2: s2, s2t: s2t, key: httpGetParamKey);
    final parts = <String>[
      ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    final tagged = path.startsWith('miniw/') ? path : 'miniw/$path';
    final p = tagged.endsWith('/') ? tagged : '$tagged/';
    return '$base/$p?${parts.join('&')}&md5=$md5';
  }

  /// 任意相对路径的签名 URL（msg_box 等，路径不含尾随斜杠）。
  String _url4(String path, String act, [Map<String, String> params = const {}]) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final all = <String, String>{
      'act': act,
      'uin': '$uin',
      'apiid': kApiId,
      'ver': kClientVersionStr,
      'country': kCountry,
      'lang': kLang,
      ...params,
    };
    final md5 = httpGetParamMd5(all, timeVal: now, s2: s2, s2t: s2t, key: httpGetParamKey);
    final parts = <String>[
      ...all.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}'),
      'time=$now',
      's2t=$s2t',
      'encrypt_ver=3',
    ];
    return '$base/$path?${parts.join('&')}&md5=$md5';
  }

  /// 拉动态列表。响应 `{ret:0, data:{list:[...], role_info_list:[...], ct:[游标]}}`。
  /// [tag] 非空时走分类标签接口 `get_posting_by_tag`（子分类 / 话题 tab 用）。
  Future<FeedResult> pullPostings(
    DynamicsFeedType type, {
    String from = 'null',
    int ct = 0,
    String? tag,
    int? opUin,
  }) async {
    final act = tag != null ? 'get_posting_by_tag' : type.act;
    final params = <String, String>{};
    if (tag != null) {
      // get_posting_by_tag: act, tag, from, ct（反编译 dynamicsdatamanager.lua:2129）。
      params['tag'] = tag;
      params['from'] = from;
      if (ct > 0) params['ct'] = '$ct';
    } else {
      switch (type) {
        case DynamicsFeedType.recommend:
        case DynamicsFeedType.mine:
          params['from'] = from;
          // 默认查自己的；传 opUin 可查指定玩家（他人主页的动态列表）。
          params['op_uin'] = '${opUin ?? uin}';
          if (ct > 0) params['ct'] = '$ct';
        case DynamicsFeedType.hot:
          if (ct > 0) params['ct'] = '$ct';
        case DynamicsFeedType.city:
          // 同城流：get_city_posting2 + from/ct（dynamicsdatamanager.lua:2051）。
          params['from'] = from;
          if (ct > 0) params['ct'] = '$ct';
        case DynamicsFeedType.official:
          params['from'] = from;
          if (ct > 0) params['ct'] = '$ct';
      }
    }
    final url = _url(act, params);

    log.debug('$act url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('$act RAW: $raw', tag: _logTag);

    // 原始响应是字符串 → 解码；否则已是结构。
    Object? decoded;
    if (raw is String) {
      decoded = decodeHttpResponse(raw);
    } else {
      decoded = raw;
    }
    reportIfFailed(url, decoded);

    if (decoded is! Map) {
      log.warn('$act decoded not Map: ${decoded.runtimeType}', tag: _logTag);
      return const FeedResult([], 0);
    }
    final m = decoded.cast<String, Object?>();

    final code = m['ret'] ?? m['code'];
    if (code is num && code != 0) {
      log.warn('$act error: ${m['msg']}', tag: _logTag);
      return const FeedResult([], 0);
    }

    Object? data = m['data'];
    List<DynamicsPost> posts = [];
    int nextCt = 0;

    if (data is Map) {
      // 游标：data.ct（下一页再传回）
      final ctVal = data['ct'];
      if (ctVal is num) {
        nextCt = ctVal.toInt();
      } else {
        nextCt = int.tryParse('$ctVal') ?? 0;
      }
      // role_info_list: { "<uin>": {NickName, PersonCenterHead:{diy_header:{pass_url}}} }
      final roleMap = <int, Map<String, Object?>>{};
      final rl = data['role_info_list'];
      if (rl is Map) {
        for (final e in rl.entries) {
          final u = int.tryParse('${e.key}');
          if (u != null && e.value is Map) {
            roleMap[u] = (e.value as Map).cast<String, Object?>();
          }
        }
      }
      final rawList = data['list'];
      if (rawList is List) {
        for (final e in rawList) {
          if (e is! Map) continue;
          final post = DynamicsPost.fromItem(e.cast<String, Object?>());
          if (post == null) continue;
          final info = roleMap[post.uin];
          String? avatar;
          if (info != null) {
            final pch = info['PersonCenterHead'];
            if (pch is Map) {
              // 对齐 `GetPlayerHeadPath`：只有 `use_diy == 1` 才用 DIY 头像
              // （有 pass_url 但未启用时游戏显示的是角色头像）。
              final diy = pch['diy_header'];
              if (pch['use_diy'] == 1 && diy is Map) {
                avatar = (diy)['pass_url']?.toString();
              }
            }
            posts.add(post.withProfile(
              nickname: info['NickName']?.toString(),
              avatar: avatar,
              headFrameId: _headFrameId(info),
            ));
          } else {
            posts.add(post);
          }
        }
      }
    } else if (data is List) {
      for (final e in data) {
        if (e is Map) {
          final p = DynamicsPost.fromItem(e.cast<String, Object?>());
          if (p != null) posts.add(p);
        }
      }
    } else {
      final l = m['list'];
      if (l is List) {
        for (final e in l) {
          if (e is Map) {
            final p = DynamicsPost.fromItem(e.cast<String, Object?>());
            if (p != null) posts.add(p);
          }
        }
      }
    }
    return FeedResult(posts, nextCt);
  }

  /// 动态大厅分类列表（`act=get_posting_tag_list`）。
  ///
  /// 路径是**带 act 的二级路径** `/miniw/posting_tag/act/get_posting_tag_list`
  /// （`dynamicsdatamanager.lua:6906`）。实测 2026-10-08：该路径在缺 `uin` 时回
  /// `{"code":1,"msg":"Unmarshal: field \"uin\" is not set"}`，补上后依次要求
  /// `time` / `s2t`；而 `/miniw/posting_tag?act=…` 直接 404。所以二级路径才对，
  /// 且 `uin/time/s2t` 正是 [_url2] 全局参数会补齐的字段。
  Future<List<DynamicsTag>> fetchPostingTags() async {
    final ack = await _getAck(
      _url2('posting_tag/act/get_posting_tag_list', 'get_posting_tag_list'),
    );
    return DynamicsTag.parseList(ack.rawData);
  }

  /// 分页拉取动态评论。
  ///
  /// [latest]=false（默认）：走 get_recommend_comment，按 [offset] 翻页
  /// （每页 20，offset = 已加载条数）；
  /// [latest]=true（最新）：走 get_comment，按 [ct]（上页最后一条的
  /// last_time）游标续拉。
  ///
  /// 对齐反编译 dynamics_detailsctrl.lua PullComments/RespPullComments：
  /// - 默认排序 offset = commentList.page * 20；
  /// - 最新排序 ct = 上页最后一条 last_time（curLastCommentCT）；
  /// - 本页为空 → 没有更多（num<1 → curLastCommentCT=-1）。
  Future<List<DynamicsComment>> fetchComments(
    String pid, {
    required bool latest,
    int offset = 0,
    int ct = 0,
  }) async {
    final params = <String, String>{
      'pid': pid,
      if (latest) ...{
        if (ct > 0) 'ct': '$ct',
      } else ...{
        'offset': '$offset',
      },
    };
    final url = _url(latest ? 'get_comment' : 'get_recommend_comment', params);
    log.debug('comment url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('comment RAW: $raw', tag: _logTag);

    Object? decoded = raw is String ? decodeHttpResponse(raw) : raw;
    reportIfFailed(url, decoded);
    if (decoded is! Map) return [];
    final m = decoded.cast<String, Object?>();
    final ret = m['ret'] ?? m['code'];
    if (ret is num && ret != 0) return [];

    Object? data = m['data'];
    final roleMap = <int, Map<String, Object?>>{};
    if (data is Map) {
      final rl = data['role_info_list'];
      if (rl is Map) {
        for (final e in rl.entries) {
          final u = int.tryParse('${e.key}');
          if (u != null && e.value is Map) {
            roleMap[u] = (e.value as Map).cast<String, Object?>();
          }
        }
      }
      data = data['list'];
    }
    if (data is! List) data = m['list'];
    if (data is! List) return [];

    final out = <DynamicsComment>[];
    for (final e in data) {
      if (e is! Map) continue;
      final c = DynamicsComment.fromItem(e.cast<String, Object?>());
      if (c == null) continue;
      final info = roleMap[c.uin];
      String? avatar;
      if (info != null) {
        final pch = info['PersonCenterHead'];
        if (pch is Map) {
          final diy = pch['diy_header'];
          if (diy is Map) avatar = diy['pass_url']?.toString();
        }
        out.add(c.withProfile(
          nickname: info['NickName']?.toString(),
          avatar: avatar,
          headFrameId: _headFrameId(info),
        ));
      } else {
        out.add(c);
      }
    }
    return out;
  }

  /// 点赞 / 取消点赞（act=like_posting；取消时带 `unprize=1`）。
  ///
  /// 对齐 `dynamicsdatamanager.lua:1531-1557` ReqPrise。
  Future<DynamicsAck> likePosting(String pid, {bool unpraise = false}) =>
      _getAck(_url('like_posting', {
        'pid': pid,
        'from': '0',
        if (unpraise) 'unprize': '1',
      }));

  /// 按 pid 拉单条动态（act=get_posting）。返回 null 表示失败/不存在。
  /// 对齐反编译 dynamicsdatamanager.lua ReqPostingInfo (act="get_posting")。
  Future<DynamicsPost?> fetchPost(String pid) async {
    final url = _url('get_posting', {'pid': pid});
    log.debug('get_posting url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    reportIfFailed(url, decoded);
    if (decoded is! Map) return null;
    final m = decoded.cast<String, Object?>();
    final ret = m['ret'] ?? m['code'];
    if (ret is num && ret != 0) return null;
    Object? data = m['data'] ?? m['posting'] ?? m;
    if (data is Map) {
      final dm = data.cast<String, Object?>();
      // 实测 get_posting 的载荷是 {ret:0, data:{posting:{...}}} —— 多包了一层
      // `posting`（raw 实测：data.posting.pid/content/...）。
      final inner = dm['posting'] ?? dm['posting_data'];
      final item = inner is Map ? inner.cast<String, Object?>() : dm;
      return DynamicsPost.fromItem(item);
    }
    return null;
  }

  // ── 发布 / 删除 / 置顶（对齐 dynamicsdatamanager.lua AddPosting / DeletePosting / SetTop）

  /// 发布文字动态（act=add_posting）。
  ///
  /// [content] 正文；[topicId]/[topicName] 选填话题；[question]=true 发布为
  /// 问答动态。对齐 AddPosting：content url_encode 参与签名（content 在
  /// md5 exclude list 中，实际不参与），from 默认 0。
  /// 发表文字动态（act=add_posting）。
  ///
  /// [content] 传**原文**：`_url` 会统一做一次查询串编码（对齐游戏
  /// `AddPosting` 中 `reqParams.content = url_encode(content)` 的单次编码）。
  Future<DynamicsAck> addPosting(
    String content, {
    int? topicId,
    String? topicName,
    bool question = false,
    int from = 0,
  }) {
    final params = <String, String>{
      'content': content,
      'from': '$from',
      'homepage_hide': '0',
    };
    if (topicId != null && topicName != null) {
      params['topic_list'] = jsonEncode([
        {'topic_id': topicId, 'title': topicName},
      ]);
    }
    if (question) params['question'] = '1';
    return _getAck(_url('add_posting', params));
  }

  /// 删除动态（act=delete_posting）。
  Future<DynamicsAck> deletePosting(String pid) =>
      _getAck(_url('delete_posting', {'pid': pid}));

  /// 用原始参数发布动态（act=add_posting）。供发布页组合
  /// content/topic_list/vote_id/question 等字段。
  Future<DynamicsAck> addPostingRaw(Map<String, Object?> params) =>
      _getAck(_url('add_posting', params.map((k, v) => MapEntry(k, '$v'))));

  /// 置顶/取消置顶动态（act=set_top）。[top]=true 置顶。
  Future<DynamicsAck> setTop(String pid, {bool top = true}) =>
      _getAck(_url('set_top', {'pid': pid, 'top': top ? '1' : '0'}));

  // ── 话题（对齐 posting_topic 接口）─────────────────────────────────────

  /// 搜索话题（act=search_topic，路径 /miniw/posting_topic）。失败/空载荷 → 空列表。
  Future<List<DynamicsTopic>> searchTopic(String title, {int offset = 0}) async {
    final ack = await _getAck(_url2('posting_topic', 'search_topic', {
      'title': title,
      'offset': '$offset',
    }));
    return DynamicsTopic.parseList(ack.rawData);
  }

  /// 创建话题（act=create_topic，路径 /miniw/posting_topic）。
  Future<DynamicsAck> createTopic(String title) =>
      _getAck(_url2('posting_topic', 'create_topic', {
        'title': title,
      }));

  // ── 投票（对齐 /miniw/customize_vote）──────────────────────────────────

  /// 创建投票（act=create_vote）。[opts] 选项文本（≤4）；[multiMode] 多选；
  /// [voteMode] 0=公开。返回响应（含 data.vote_info.vote_id）。
  Future<DynamicsAck> createVote({
    required String title,
    required int endTime,
    required List<String> opts,
    int multiMode = 0,
    int voteMode = 0,
  }) {
    final params = <String, String>{
      'uin': '$uin',
      'title': title,
      'end_time': '$endTime',
      'opt_num': '${opts.length}',
      'multi_mode': '$multiMode',
      'mode': '$voteMode',
      'name': '',
      'from': '0',
    };
    for (var i = 0; i < opts.length; i++) {
      params['op${i + 1}'] = opts[i];
    }
    return _getAck(_url3('customize_vote/', 'create_vote', params));
  }

  /// 投票（act=vote）。[opts] 逗号分隔选项序号（如 "1,3"）。
  Future<DynamicsAck> vote({
    required String voteId,
    required String opts,
    String? pid,
    String share = '0',
  }) {
    final params = <String, String>{
      'from_type': '1',
      'vote_id': voteId,
      'opts': opts,
      'share': share,
      'uin': '$uin',
      'from': '0',
    };
    if (pid != null) params['from_id'] = pid;
    return _getAck(_url3('customize_vote/', 'vote', params));
  }

  /// 查询投票信息（act=get_vote_info）。无有效数据 → null。
  ///
  /// 对齐游戏 `dynamicsdatamanager.lua:4639-4656`：`code != 0` 时**只在动态作者
  /// 是本人时才提示 `ret.msg`**（`bolMine`），否则静默；两种情况都把 `ret.data`
  /// 交给回调。所以这里**不走 `reportIfFailed`** —— 那会把服务端业务提示
  /// （例如「审核中」）弹成全局错误条，而游戏里别人的投票照常显示。
  Future<DynamicsVoteInfo?> getVoteInfo(
    String voteId, {
    void Function(String msg)? onMessage,
  }) async {
    final url = _url3('customize_vote/', 'get_vote_info', {
      'vote_id': voteId,
    });
    final resp = await _dio.get(url);
    final raw = resp.data;
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is! Map) return null;
    final m = decoded.cast<String, Object?>();
    final code = m['code'] ?? m['ret'];
    if (code is num && code != 0) {
      final msg = m['msg']?.toString() ?? '';
      if (msg.isNotEmpty) onMessage?.call(msg);
    }
    final data = m['data'];
    if (data is Map) return DynamicsVoteInfo.fromMap(data.cast<String, Object?>());
    return DynamicsVoteInfo.fromMap(m);
  }

  // ── 动态通知（对齐 /miniw/msg_box get_channel_msg_list）─────────────────

  /// 拉取某频道（post_rep/post_prize/post_at/fans_change/post_sys）通知列表。
  /// 返回 `(通知列表, next_offset)`；每个条目含 msg_id/msg_type + data(JSON)。
  Future<(List<DynamicsNotice>, int)> fetchChannelNotice(
    String channel, {
    int offset = 0,
  }) async {
    final ret = await _getAck(_url4('miniw/msg_box', 'get_channel_msg_list', {
      'uin': '$uin',
      'channel': channel,
      'offset': '$offset',
    }));
    final code = ret._raw['code'] ?? ret._raw['ret'];
    if (code is num && code != 0) {
      return (<DynamicsNotice>[], 0);
    }
    final dm = ret._data;
    final nextOffset = (dm['next_offset'] is num
            ? (dm['next_offset'] as num)
            : int.tryParse('${dm['next_offset']}') ?? 0)
        .toInt();
    final out = <DynamicsNotice>[];
    final rawList = dm['msg_list'];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is! Map) continue;
        final m = e.cast<String, Object?>();
        final notice = DynamicsNotice.fromItem(m);
        if (notice != null) out.add(notice);
      }
    }
    return (out, nextOffset);
  }

  /// 标记频道通知已读（act=read_channel_msg）。
  Future<bool> readChannelNotice(String channel, List<String> msgIds) async {
    if (msgIds.isEmpty) return true;
    final ret = await _getAck(_url4('miniw/msg_box', 'read_channel_msg', {
      'uin': '$uin',
      'channel': channel,
      'msg_id_list': msgIds.join(','),
    }));
    final code = ret._raw['code'] ?? ret._raw['ret'];
    return code is num && code == 0;
  }

  /// 动态红点（act=get_redpoint_notice_info，/miniw/posting）。
  /// 返回 {new_posting_notice, posting_edit_info}（顶层或 data 下均可）。
  Future<DynamicsRedpointNotice> fetchRedpointNotice(String source) async {
    final ack =
        await _getAck(_url('get_redpoint_notice_info', {'source': source}));
    return DynamicsRedpointNotice.fromResponse(ack._raw);
  }

  /// 发表评论（act=add_comment）。
  Future<DynamicsAck> addComment(String pid, String content) =>
      _getAck(_url('add_comment', {'pid': pid, 'content': content}));

  /// 拉取某条评论的回复（act=get_comment_rep）。
  ///
  /// 请求参数对齐反编译 dynamicsdatamanager.lua ReqCommentReply：
  /// `com_pid_uin, com_pid_ct, com_uin, com_op_uin, com_last_time` 是父评论
  /// 的定位字段（来自评论条目本身），**不是**动态 pid / 评论作者 uin。
  /// 回复条目结构：{rep_id, rep_uin(回复者), op_uin(被回复者), content,
  /// rep_time, prize, stat}，昵称/头像在 role_info_list（keyed by rep_uin）。
  Future<List<DynamicsComment>> fetchCommentReplies(DynamicsComment comment) async {
    final params = <String, String>{
      'com_pid_uin': '${comment.pidUin}',
      'com_pid_ct': '${comment.pidCt}',
      'com_uin': '${comment.uin}',
      'com_op_uin': '${comment.opUin}',
      'com_last_time': '${comment.lastTime}',
    };
    final url = _url('get_comment_rep', params);
    log.debug('get_comment_rep url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    log.debug('get_comment_rep RAW: $raw', tag: _logTag);
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    reportIfFailed(url, decoded);
    if (decoded is! Map) return [];
    final m = decoded.cast<String, Object?>();
    final ret = m['ret'] ?? m['code'];
    if (ret is num && ret != 0) return [];
    Object? data = m['data'];
    final roleMap = <int, Map<String, Object?>>{};
    if (data is Map) {
      final rl = data['role_info_list'];
      if (rl is Map) {
        for (final e in rl.entries) {
          final u = int.tryParse('${e.key}');
          if (u != null && e.value is Map) {
            roleMap[u] = (e.value as Map).cast<String, Object?>();
          }
        }
      }
      data = data['list'];
    }
    if (data is! List) data = m['list'];
    if (data is! List) return [];

    final out = <DynamicsComment>[];
    for (final e in data) {
      if (e is! Map) continue;
      final c = DynamicsComment.fromItem(e.cast<String, Object?>());
      if (c == null) continue;
      final info = roleMap[c.uin];
      String? avatar;
      if (info != null) {
        final pch = info['PersonCenterHead'];
        if (pch is Map) {
          final diy = pch['diy_header'];
          if (diy is Map) avatar = diy['pass_url']?.toString();
        }
        out.add(c.withProfile(
          nickname: info['NickName']?.toString(),
          avatar: avatar,
          headFrameId: _headFrameId(info),
        ));
      } else {
        out.add(c);
      }
    }
    return out;
  }

  // ── 图片（对齐 posting add_posting_pic / delete_posting_pic）──────────────

  /// 预上传动态图片：GET `miniw/profile?act=upload_pre_photo`。
  ///
  /// 与 DIY 头像同一预上传口（`http.lua:1771-1783` `upload_md5_file_pre`，
  /// 返回字符串 `ok:<直传地址>`）。
  ///
  /// 注意：游戏走的是 `ns_http.func.rpc_string`，它会把 URL 再过一遍
  /// `url_addParams`（`http.lua:891`）——所以真实请求里**必须带**
  /// `uin/apiid/ver/country/lang`。实测缺这些参数时服务端回 **空 body**（http 200），
  /// 补上后才回 `ok:<url>`。
  Future<String?> preUploadPhoto() async {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sign = httpGetS1Map(now, s2, uin, s2t);
    final url = '$base/miniw/profile?act=upload_pre_photo&uin=$uin'
        '&apiid=$kApiId&ver=$kClientVersionStr&country=$kCountry&lang=$kLang&$sign';
    final resp = await _dio.get(url);
    final t = '${resp.data}'.trim();
    if (!t.startsWith('ok:')) return null;
    final u = t.substring(3).trim();
    return u.isEmpty ? null : u;
  }

  /// 直传图片字节到 [uploadUrl]，返回去掉 `ok:` 前缀的 sub_token。
  ///
  /// 线格式按真实抓包（2026-10-06）复刻，见 [uploadPresignedFile]：
  /// `act=info` → `upload_begin` → `upload_step`×N（每片 128 KiB 的 multipart，
  /// 字段名 `fileUpload`、filename = 文件 md5）→ `upload_end`，回包
  /// `ok:token=..&node=..&dir=..` 去掉前缀即 sub_token。
  Future<String?> uploadPhotoBytes(
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

  /// 登记一张已直传的图片：`act=add_posting_pic`。
  ///
  /// 对齐 `dynamicsdatamanager.lua:7727-7778` AddPostPic：URL 形如
  /// `?act=add_posting_pic&seq=N&md5=文件md5&ext=ext[&show_idx=N]&sub_token&s2act`，
  /// 其中 sub_token 来自上传响应、s2act 来自 `http_getS2Act('posting')`；
  /// **不是** http_getParamMD5 签名。成功返回 `data.url`；失败 → null。
  Future<String?> addPostingPic({
    required int seq,
    required String fileMd5,
    required String ext,
    required String subToken,
    int? showIdx,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final parts = <String>[
      'act=add_posting_pic',
      // 游戏走 ns_http.func.rpc，内部 url_addParams 会补这些通用参数；
      // 缺了服务端会回空表 `{}`（实测：补上即回 url+ret:0）。
      'uin=$uin',
      'apiid=$kApiId',
      'ver=$kClientVersionStr',
      'country=$kCountry',
      'lang=$kLang',
      'seq=$seq',
      'md5=$fileMd5',
      'ext=$ext',
      if (showIdx != null) 'show_idx=$showIdx',
      subToken,
      httpGetS2Act('posting', now, s2, uin, s2t),
    ];
    final url = '$base/$kPostingPath?${parts.join('&')}';
    log.debug('add_posting_pic url（已脱敏）: ${redactUrl(url)}', tag: _logTag);
    final resp = await _dio.get(url);
    final raw = resp.data;
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    reportIfFailed(url, decoded);
    if (decoded is! Map) return null;
    final m = decoded.cast<String, Object?>();
    final ret = m['ret'] ?? m['code'];
    if (ret is num && ret != 0) return null;
    // 实测回包是**平铺**的：{"seq":1,"url":"http://.../xxx.png","ret":0,"msg":"ok"}
    // （url 不在 data 下），两种形态都兼容。
    final data = m['data'];
    final flat = _nonEmpty(m['url'] ?? m['pic_url']);
    if (flat != null) return flat;
    if (data is Map) {
      final u = _nonEmpty(data['url'] ?? data['pic_url']);
      if (u != null) return u;
    }
    return null;
  }

  /// 删除已登记的图片（act=delete_posting_pic&seq=N）。
  Future<DynamicsAck> deletePostingPic(int seq) =>
      _getAck(_url('delete_posting_pic', {'seq': '$seq'}));

  /// 一步直传图片：预上传 → 上传字节 → 登记，返回图片 url。
  ///
  /// 任一步失败 → null。文件 md5 由调用方传入（与直传的 md5 必须一致）。
  Future<String?> uploadPostingPic({
    required int seq,
    required List<int> bytes,
    required String fileMd5,
    required String ext,
    int? showIdx,
  }) async {
    final uploadUrl = await preUploadPhoto();
    if (uploadUrl == null) return null;
    final subToken =
        await uploadPhotoBytes(uploadUrl, bytes, fileMd5: fileMd5, ext: ext);
    if (subToken == null) return null;
    return addPostingPic(
      seq: seq,
      fileMd5: fileMd5,
      ext: ext,
      subToken: subToken,
      showIdx: showIdx,
    );
  }

  // ── 可见范围 / 权限（act=setPostingAuth）────────────────────────────────

  /// 修改动态权限：`act=setPostingAuth&pid=&ptype=&pauth=`。
  ///
  /// [ptype] 取 [DynamicsAuth.ptypeSee] / [DynamicsAuth.ptypeRep] /
  /// [DynamicsAuth.ptypeHome]（对齐玩家中心 `dynamics_frame_playercenterctrl.lua:536/573/617`）。
  Future<DynamicsAck> setPostingAuth(
    String pid, {
    required String ptype,
    required int pauth,
  }) =>
      _getAck(_url('setPostingAuth', {
        'pid': pid,
        'ptype': ptype,
        'pauth': '$pauth',
      }));

  // ── 转发计数（act=share_posting）───────────────────────────────────────

  /// 上报一次动态分享给 [target]（act=share_posting&pid=&target=）。
  /// 返回服务端回传的新转发数；无则 null。对齐 `dynamicsdatamanager.lua:3724`。
  Future<int?> sharePosting(String pid, {required int target}) async {
    final ack = await _getAck(
      _url('share_posting', {'pid': pid, 'target': '$target'}),
    );
    return ack.shareCount;
  }

  // ── 评论操作（赞 / 置顶 / 删除）─────────────────────────────────────────

  /// 评论点赞 / 取消（act=prize_comment；`op_type=prize|cai`）。
  /// 对齐 `dynamicsdatamanager.lua:3453-3476`。
  Future<DynamicsAck> prizeComment(DynamicsComment c, {bool prize = true}) =>
      _getAck(_url('prize_comment', {
        'op_type': prize ? 'prize' : 'cai',
        'com_pid_uin': '${c.pidUin}',
        'com_pid_ct': '${c.pidCt}',
        'com_uin': '${c.uin}',
        'com_op_uin': '${c.opUin}',
        'com_last_time': '${c.lastTime}',
        'from': '0',
      }));

  /// 置顶评论（act=set_top_comment）。对齐 `dynamicsdatamanager.lua:3477-3497`。
  Future<DynamicsAck> setTopComment(DynamicsComment c) =>
      _getAck(_url('set_top_comment', {
        'com_pid_ct': '${c.pidCt}',
        'com_uin': '${c.uin}',
        'com_op_uin': '${c.opUin}',
        'com_last_time': '${c.lastTime}',
      }));

  /// 取消评论置顶（act=delete_top_comment&pid=）。
  Future<DynamicsAck> deleteTopComment(String pid) =>
      _getAck(_url('delete_top_comment', {'pid': pid}));

  /// 删除评论。
  ///
  /// [authorOnly]=false → `delete_single_comment`，pid 拼成
  /// `<动态 pid>_<评论作者 uin>_<last_time>` 并带 `op_uin`；
  /// [authorOnly]=true → `delete_player_comment`，pid 拼成
  /// `<动态 pid>_<评论作者 uin>`，删该作者在该动态下的全部评论。
  /// 对齐 `dynamicsdatamanager.lua:1335-1362` DeleteComment。
  Future<DynamicsAck> deleteComment(
    String pid,
    DynamicsComment c, {
    bool authorOnly = false,
  }) =>
      _getAck(_url(
        authorOnly ? 'delete_player_comment' : 'delete_single_comment',
        authorOnly
            ? {'pid': '${pid}_${c.uin}'}
            : {
                'pid': '${pid}_${c.uin}_${c.lastTime}',
                'op_uin': '${c.opUin}',
              },
      ));

  // ── 回复（二级评论）读写 ────────────────────────────────────────────────

  /// 发表回复（act=add_comment_rep）。[opUin] 为被回复者；对齐
  /// `dynamicsdatamanager.lua:4935-4985` AddCommentReply。
  Future<DynamicsAck> addCommentReply(
    DynamicsComment parent, {
    required int opUin,
    required String content,
  }) =>
      _getAck(_url('add_comment_rep', {
        'com_pid_uin': '${parent.pidUin}',
        'com_pid_ct': '${parent.pidCt}',
        'com_uin': '${parent.uin}',
        'com_op_uin': '${parent.opUin}',
        'com_last_time': '${parent.lastTime}',
        'op_uin': '$opUin',
        'content': content,
        'from': '0',
      }));

  /// 回复点赞 / 取消（act=prize_comment_rep&rep_id=&op_type=）。
  Future<DynamicsAck> prizeCommentReply(
    String repId, {
    bool prize = true,
  }) =>
      _getAck(_url('prize_comment_rep', {
        'rep_id': repId,
        'op_type': prize ? 'prize' : 'cai',
      }));

  /// 删除自己发出的回复（act=delete_player_comment_rep&rep_id=）。
  Future<DynamicsAck> deletePlayerCommentReply(String repId) =>
      _getAck(_url('delete_player_comment_rep', {'rep_id': repId}));

  /// 删除动态作者可见的回复（act=delete_comment_rep&rep_id=）。
  Future<DynamicsAck> deleteCommentReply(String repId) =>
      _getAck(_url('delete_comment_rep', {'rep_id': repId}));

  /// 按父评论定位拉单条评论（act=get_single_comment）。
  Future<DynamicsComment?> fetchSingleComment(DynamicsComment parent) async {
    final ack = await _getAck(_url('get_single_comment', {
      'com_pid_uin': '${parent.pidUin}',
      'com_pid_ct': '${parent.pidCt}',
      'com_uin': '${parent.uin}',
      'com_op_uin': '${parent.opUin}',
      'com_last_time': '${parent.lastTime}',
    }));
    final data = ack.data;
    final list = data['list'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) {
        return DynamicsComment.fromItem(first.cast<String, Object?>());
      }
    }
    return null;
  }

  // ── 话题（/miniw/posting_topic）─────────────────────────────────────────

  /// 话题列表（act=get_topic_list&sort_type=&offset=）。
  /// [sortType] 对齐 `dynamicsdatamanager.lua:3750` PullTopicList。
  Future<List<DynamicsTopic>> fetchTopicList({
    int sortType = 0,
    int offset = 0,
  }) async {
    final ack = await _getAck(_url2('posting_topic', 'get_topic_list', {
      'sort_type': '$sortType',
      'offset': '$offset',
    }));
    return DynamicsTopic.parseList(ack.rawData);
  }

  /// 官方话题列表（act=get_official_topic_list）。
  Future<List<DynamicsTopic>> fetchOfficialTopicList({
    int sortType = 0,
    int offset = 0,
  }) async {
    final ack = await _getAck(_url2('posting_topic', 'get_official_topic_list', {
      'sort_type': '$sortType',
      'offset': '$offset',
    }));
    return DynamicsTopic.parseList(ack.rawData);
  }

  /// 我关注的话题（act=get_follow_topic_list）。
  Future<List<DynamicsTopic>> fetchFollowTopicList({int offset = 0}) async {
    final ack = await _getAck(_url2('posting_topic', 'get_follow_topic_list', {
      'offset': '$offset',
    }));
    return DynamicsTopic.parseList(ack.rawData);
  }

  /// 热门话题（act=get_hot_topic2；路径带尾随 `/`，对齐
  /// `dynamicsdatamanager.lua:4781` ReqGetHotTopic）。
  Future<List<DynamicsTopic>> fetchHotTopics({int offset = 0, int limit = 10}) async {
    final ack = await _getAck(_url3('posting_topic', 'get_hot_topic2', {
      'offset': '$offset',
      'limit': '$limit',
    }));
    return DynamicsTopic.parseList(ack.rawData);
  }

  // ── 我收到的评论 / 回复（act=get_reps_list）─────────────────────────────

  /// 拉取某玩家最近的评论/回复（act=get_reps_list&op_uin=）。
  /// 对齐 `dynamicsdatamanager.lua:1152` GetRepsList（用于动态消息「评论我的」）。
  Future<List<DynamicsComment>> fetchRepsList({int? opUin}) async {
    final ack = await _getAck(_url('get_reps_list', {
      'op_uin': '${opUin ?? uin}',
    }));
    final data = ack.data;
    final list = data['list'];
    if (list is! List) return const [];
    final out = <DynamicsComment>[];
    for (final e in list) {
      if (e is! Map) continue;
      final c = DynamicsComment.fromItem(e.cast<String, Object?>());
      if (c != null) out.add(c);
    }
    return out;
  }

  // ── 抽奖（/miniw/red_packet）──────────────────────────────────────────

  /// 创建抽奖种子（act=post_lottery_gen_seed）。
  ///
  /// 对齐 `dynamicsdatamanager.lua:5720` LotteryCreateSeed；成功返回服务端
  /// 生成的 `lottery_id`（`data.lottery_id` / `data` 直接是 id 串），失败 → null。
  Future<String?> createLotterySeed({
    required int itemId,
    required int itemNum,
    required int itemType,
    required int selectNum,
    required int costNum,
    required int lotteryTime,
    String task = '',
    int isAuthor = 1,
  }) async {
    final ack = await _getAck(_url2('red_packet', 'post_lottery_gen_seed', {
      'item_id': '$itemId',
      'item_num': '$itemNum',
      'item_type': '$itemType',
      'select_num': '$selectNum',
      'cost_num': '$costNum',
      'lottery_time': '$lotteryTime',
      'task': task,
      'is_author': '$isAuthor',
    }));
    final data = ack.data;
    return _nonEmpty(data['lottery_id'] ?? data['id']);
  }

  /// 查询抽奖信息（act=posting_lottery_query_lottery&lottery_ids=a,b）。
  /// 对齐 `dynamicsdatamanager.lua:5741` LotteryQueryCfg。
  Future<List<DynamicsLottery>> queryLotteries(List<String> lotteryIds) async {
    if (lotteryIds.isEmpty) return const [];
    final ack = await _getAck(_url2('red_packet', 'posting_lottery_query_lottery', {
      'lottery_ids': lotteryIds.join(','),
    }));
    return DynamicsLottery.parseList(ack.rawData);
  }

  /// 批量补齐动态里的抽奖信息（按 `lottery_id` 去重）。
  Future<Map<String, DynamicsLottery>> fetchLotteriesFor(
    List<DynamicsPost> posts,
  ) async {
    final ids = <String>{ for (final p in posts) if (p.lotteryId != null) p.lotteryId! };
    if (ids.isEmpty) return const {};
    final list = await queryLotteries(ids.toList());
    return { for (final l in list) l.lotteryId: l };
  }

  // ── 作品动态（/miniw/map_posting）──────────────────────────────────────

  /// 作品动态列表（act=get_list_by_hot / get_list_by_time / get_list_by_tag）。
  ///
  /// 对齐 `dynamicsdatamanager.lua:5256-5340` GetMapDynamicByHot/ByTime/ByTag。
  /// [act] 取 `get_list_by_hot` / `get_list_by_time` / `get_list_by_tag`。
  Future<FeedResult> pullMapPostings({
    required String act,
    required int mapId,
    int mapCtype = 0,
    int offset = 0,
    int ct = 0,
    int? uinOfMap,
    int tag = 1000,
    int sortType = 1,
    int orderType = 1,
    String from = 'null',
  }) async {
    final params = <String, String>{
      'uin': '${uinOfMap ?? uin}',
      'map_id': '$mapId',
      'map_ctype': '$mapCtype',
    };
    if (act == 'get_list_by_tag') {
      params['offset'] = '$offset';
      if (ct > 0) params['ct'] = '$ct';
      params['tag'] = '$tag';
      params['sort_type'] = '$sortType';
      params['order_type'] = '$orderType';
    } else {
      params['offset'] = '$offset';
      if (ct > 0) params['ct'] = '$ct';
      if (act == 'get_list_by_hot') params['from'] = from;
    }
    final ack = await _getAck(_url2('map_posting', act, params));
    final data = ack.data;
    final list = data['list'];
    final out = <DynamicsPost>[];
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final p = DynamicsPost.fromItem(e.cast<String, Object?>());
        if (p != null) out.add(p);
      }
    }
    return FeedResult(out, _pickInt(data, ['ct', 'next_ct']));
  }

  // ── 内部 ──────────────────────────────────────────────────────────────

  Future<DynamicsAck> _getAck(String url) async {
    final resp = await _dio.get(url);
    final raw = resp.data;
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    reportIfFailed(url, decoded);
    if (decoded is Map) return DynamicsAck.fromMap(decoded.cast<String, Object?>());
    return const DynamicsAck();
  }
}
