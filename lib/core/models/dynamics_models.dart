/// 动态(Posting)数据模型与宽松解析 —— /miniw/posting 与 /miniw/com_posting
/// 的响应形状，移植自反编译源码 dynamicsdatamanager.lua。
///
/// 纯数据/解析层：无 Dio、无 Flutter；脏/缺省数据一律降级，绝不抛。
/// 客户端见 services/dynamics.dart（该文件 export 本库，既有调用点无需改动）。
library;

import 'dart:convert' show jsonDecode;

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
int parseDynamicsInt(Map<String, Object?> m, List<String> keys) {
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

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）。
  ///
  /// 动态接口本身不下发它（只有 DIY 头像与头像框），由页面用
  /// `ProfileClient.fetchAvatarProfiles` 批量补齐后经 [withAvatar] 填上；
  /// `AvatarView` 靠它去查本机角色头像图标（`headIconAsset`）。
  final int? headType;
  final int? headId;

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
    this.headType,
    this.headId,
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
      authSee: parseDynamicsInt(m, ['auth_see', 'authSee']),
      videoResId:
          parseDynamicsNonEmptyString(m['video_res_id'] ?? m['videoResId']),
      topics: _parseTopicList(m['topic_list']),
      lotteryId: parseDynamicsNonEmptyString(m['lottery_id'] ?? m['lotteryId']),
      voteId: parseDynamicsNonEmptyString(
          m['vote_id'] ?? m['share_vote'] ?? m['voteId']),
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
        headType: headType,
        headId: headId,
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

  /// 换一份头像展示信息（页面批量补资料后重建）。
  ///
  /// 与 [withProfile] 的区别：[url] 是**最终值** —— 传 null 表示清掉列表自带的
  /// 头像 URL，让角色头像本体（[headType]/[headId]）生效；`withProfile` 对 null
  /// 是「保留原值」，清不掉。
  DynamicsPost withAvatar({
    required String? url,
    int? headType,
    int? headId,
    int? headFrameId,
  }) =>
      DynamicsPost(
        pid: pid,
        uin: uin,
        content: content,
        createTime: createTime,
        ctype: ctype,
        nickname: nickname,
        avatar: url,
        headFrameId: headFrameId ?? this.headFrameId,
        headType: headType,
        headId: headId,
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
String? parseDynamicsNonEmptyString(Object? v) {
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

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）；评论接口不下发，由页面用
  /// `ProfileClient.fetchAvatarProfiles` 批量补齐后经 [withAvatar] 填上。
  final int? headType;
  final int? headId;
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
    this.headType,
    this.headId,
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
        headType: headType,
        headId: headId,
        likeCount: likeCount,
        replyCount: replyCount,
        location: location,
        pidUin: pidUin,
        pidCt: pidCt,
        opUin: opUin,
        lastTime: lastTime,
        repId: repId,
      );

  /// 换一份头像展示信息（见 [DynamicsPost.withAvatar]：`url` 是最终值）。
  DynamicsComment withAvatar({
    required String? url,
    int? headType,
    int? headId,
    int? headFrameId,
  }) =>
      DynamicsComment(
        uin: uin,
        content: content,
        createTime: createTime,
        nickname: nickname,
        avatar: url,
        headFrameId: headFrameId ?? this.headFrameId,
        headType: headType,
        headId: headId,
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

  /// 完整响应 map（供红点等顶层字段兜底）；对外只读，见 [raw]。
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
    final n = parseDynamicsInt(_data, ['share', 'share_count']);
    return n == 0 ? null : n;
  }

  /// 响应 `data` 载荷（非 Map 或缺失时为空 map）；供投票 / 红点等 Map 型响应取用。
  Map<String, Object?> get data => _data;

  /// 响应 `data` 原值（保持 List / Map 形态）；供话题等列表型响应取用。
  Object? get rawData => _rawData;

  /// 完整响应 map（顶层 `code`/`ret` 兜底用）；只读。
  Map<String, Object?> get raw => _raw;

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
    final index = parseDynamicsInt(m, ['index', 'idx', 'op_index', 'id']);
    final text = m['text']?.toString() ??
        m['title']?.toString() ??
        m['name']?.toString() ??
        m['op']?.toString() ??
        '';
    final count =
        parseDynamicsInt(m, ['count', 'num', 'vote_num', 'prize', 'total']);
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
      endTime: parseDynamicsInt(m, ['end_time', 'endTime']),
      multiMode: parseDynamicsInt(m, ['multi_mode', 'multiMode']),
      mode: parseDynamicsInt(m, ['mode']),
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
    final id = parseDynamicsNonEmptyString(
        m['lottery_id'] ?? m['lotteryId'] ?? m['id']);
    if (id == null) return null;
    final isAuthor = m['is_author'];
    return DynamicsLottery(
      lotteryId: id,
      itemId: parseDynamicsInt(m, ['item_id', 'itemId']),
      itemNum: parseDynamicsInt(m, ['item_num', 'itemNum']),
      itemType: parseDynamicsInt(m, ['item_type', 'itemType']),
      selectNum: parseDynamicsInt(m, ['select_num', 'selectNum']),
      costNum: parseDynamicsInt(m, ['cost_num', 'costNum']),
      lotteryTime: parseDynamicsInt(m, ['lottery_time', 'lotteryTime']),
      task: m['task']?.toString() ?? '',
      status: parseDynamicsInt(m, ['status', 'state']),
      joinCount: parseDynamicsInt(m, ['join_count', 'join_num', 'joinCount']),
      uin: parseDynamicsInt(m, ['uin', 'author_uin']),
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
          parseDynamicsInt(src, ['new_posting_notice', 'newPostingNotice']),
      postingEditInfo:
          parseDynamicsInt(src, ['posting_edit_info', 'postingEditInfo']),
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
      final id = parseDynamicsInt(m, ['tag_id', 'tagId', 'id']);
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
