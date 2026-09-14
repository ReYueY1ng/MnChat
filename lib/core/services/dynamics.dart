/// 动态(Posting)服务客户端 —— /miniw/posting 与 /miniw/com_posting。
/// 移植自反编译源码 dynamicsdatamanager.lua：
///   - 好友 feed: POSTING + get_friend_posting (+ from)
///   - 热门/时间: COM_POSTING + get_list_by_hot / get_list_by_time (+ offset)
/// URL 用 act + http_getParamMD5 签名。
library;

import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../crypto/md5_sign.dart' show httpGetParamKey, httpGetParamMd5;
import '../net/config.dart' show backendShequ, kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;

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
  official('官方', 'get_official_posting'),
  mine('我的', 'get_posting_list');

  const DynamicsFeedType(this.label, this.act);
  final String label;
  final String act;
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
      );
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
    // content 是 URL 编码（UTF-8），需解码。
    final content = Uri.decodeComponent(m['content']?.toString() ?? '');
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
      // 回复/评论接口的 com_op_uin 通常=评论作者；缺省用作者 uin 兜底
      opUin: opUin != 0 ? opUin : authorUin,
      lastTime: _int(m, ['last_time', 'com_last_time']),
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

  static String _safeDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
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
        baseUrl = baseUrl ??
            (kIsWeb ? backendShequ() : (kDefaultUrls['HttpCommon'] ?? kDefaultBase));

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
    final p = path.endsWith('/') ? path : path;
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
    final p = path.endsWith('/') ? path : '$path/';
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
  /// [tag] 非空时走分类标签接口 `get_posting_by_tag`（子分类 tab 用）。
  Future<FeedResult> pullPostings(
    DynamicsFeedType type, {
    String from = 'null',
    int ct = 0,
    int? tag,
  }) async {
    final act = tag != null ? 'get_posting_by_tag' : type.act;
    final params = <String, String>{};
    if (tag != null) {
      // get_posting_by_tag: act, tag, from, ct（反编译 dynamicsdatamanager.lua:1830）
      params['tag'] = '$tag';
      params['from'] = from;
      if (ct > 0) params['ct'] = '$ct';
    } else {
      switch (type) {
        case DynamicsFeedType.recommend:
        case DynamicsFeedType.mine:
          params['from'] = from;
          params['op_uin'] = '$uin';
          if (ct > 0) params['ct'] = '$ct';
        case DynamicsFeedType.hot:
          if (ct > 0) params['ct'] = '$ct';
        case DynamicsFeedType.official:
          params['from'] = from;
          if (ct > 0) params['ct'] = '$ct';
      }
    }
    final url = _url(act, params);

    debugPrint('[Dynamics $act] url: $url');
    final resp = await _dio.get(url);
    final raw = resp.data;
    debugPrint('[Dynamics $act] RAW: $raw');

    // 原始响应是字符串 → 解码；否则已是结构。
    Object? decoded;
    if (raw is String) {
      decoded = decodeHttpResponse(raw);
    } else {
      decoded = raw;
    }

    if (decoded is! Map) {
      debugPrint('[Dynamics $act] decoded not Map: ${decoded.runtimeType}');
      return const FeedResult([], 0);
    }
    final m = decoded.cast<String, Object?>();

    final code = m['ret'] ?? m['code'];
    if (code is num && code != 0) {
      debugPrint('[Dynamics $act] error: ${m['msg']}');
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
              final diy = (pch)['diy_header'];
              if (diy is Map) avatar = (diy)['pass_url']?.toString();
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
    debugPrint('[Dynamics comment] url: $url');
    final resp = await _dio.get(url);
    final raw = resp.data;
    debugPrint('[Dynamics comment] RAW: $raw');

    Object? decoded = raw is String ? decodeHttpResponse(raw) : raw;
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

  /// 点赞（act=like_posting）。返回服务器原始 map（含 ret）。
  Future<Map<String, Object?>> likePosting(String pid) =>
      _getMap(_url('like_posting', {'pid': pid}));

  /// 按 pid 拉单条动态（act=get_posting）。返回 null 表示失败/不存在。
  /// 对齐反编译 dynamicsdatamanager.lua ReqPostingInfo (act="get_posting")。
  Future<DynamicsPost?> fetchPost(String pid) async {
    final url = _url('get_posting', {'pid': pid});
    debugPrint('[Dynamics get_posting] url: $url');
    final resp = await _dio.get(url);
    final raw = resp.data;
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is! Map) return null;
    final m = decoded.cast<String, Object?>();
    final ret = m['ret'] ?? m['code'];
    if (ret is num && ret != 0) return null;
    Object? data = m['data'] ?? m['posting'] ?? m;
    if (data is Map) {
      return DynamicsPost.fromItem(data.cast<String, Object?>());
    }
    return null;
  }

  // ── 发布 / 删除 / 置顶（对齐 dynamicsdatamanager.lua AddPosting / DeletePosting / SetTop）

  /// 发布文字动态（act=add_posting）。
  ///
  /// [content] 正文；[topicId]/[topicName] 选填话题；[question]=true 发布为
  /// 问答动态。对齐 AddPosting：content url_encode 参与签名（content 在
  /// md5 exclude list 中，实际不参与），from 默认 0。
  Future<Map<String, Object?>> addPosting(
    String content, {
    int? topicId,
    String? topicName,
    bool question = false,
    int from = 0,
  }) {
    final params = <String, String>{
      'content': Uri.encodeQueryComponent(content),
      'from': '$from',
      'homepage_hide': '0',
    };
    if (topicId != null && topicName != null) {
      params['topic_list'] = jsonEncode([
        {'topic_id': topicId, 'title': topicName},
      ]);
    }
    if (question) params['question'] = '1';
    return _getMap(_url('add_posting', params));
  }

  /// 删除动态（act=delete_posting）。
  Future<Map<String, Object?>> deletePosting(String pid) =>
      _getMap(_url('delete_posting', {'pid': pid}));

  /// 用原始参数发布动态（act=add_posting）。供发布页组合
  /// content/topic_list/vote_id/question 等字段。
  Future<Map<String, Object?>> addPostingRaw(Map<String, Object?> params) =>
      _getMap(_url('add_posting', params.map((k, v) => MapEntry(k, '$v'))));

  /// 置顶/取消置顶动态（act=set_top）。[top]=true 置顶。
  Future<Map<String, Object?>> setTop(String pid, {bool top = true}) =>
      _getMap(_url('set_top', {'pid': pid, 'top': top ? '1' : '0'}));

  // ── 话题（对齐 posting_topic 接口）─────────────────────────────────────

  /// 搜索话题（act=search_topic，路径 /miniw/posting_topic）。
  Future<Map<String, Object?>> searchTopic(String title, {int offset = 0}) =>
      _getMap(_url2('posting_topic', 'search_topic', {
        'title': Uri.encodeQueryComponent(title),
        'offset': '$offset',
      }));

  /// 创建话题（act=create_topic，路径 /miniw/posting_topic）。
  Future<Map<String, Object?>> createTopic(String title) =>
      _getMap(_url2('posting_topic', 'create_topic', {
        'title': Uri.encodeQueryComponent(title),
      }));

  // ── 投票（对齐 /miniw/customize_vote）──────────────────────────────────

  /// 创建投票（act=create_vote）。[opts] 选项文本（≤4）；[multiMode] 多选；
  /// [voteMode] 0=公开。返回响应（含 data.vote_info.vote_id）。
  Future<Map<String, Object?>> createVote({
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
      'name': Uri.encodeQueryComponent(''),
      'from': '0',
    };
    for (var i = 0; i < opts.length; i++) {
      params['op${i + 1}'] = Uri.encodeQueryComponent(opts[i]);
    }
    return _getMap(_url3('customize_vote/', 'create_vote', params));
  }

  /// 投票（act=vote）。[opts] 逗号分隔选项序号（如 "1,3"）。
  Future<Map<String, Object?>> vote({
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
    return _getMap(_url3('customize_vote/', 'vote', params));
  }

  /// 查询投票信息（act=get_vote_info）。
  Future<Map<String, Object?>> getVoteInfo(String voteId) =>
      _getMap(_url3('customize_vote/', 'get_vote_info', {'vote_id': voteId}));

  // ── 动态通知（对齐 /miniw/msg_box get_channel_msg_list）─────────────────

  /// 拉取某频道（post_rep/post_prize/post_at/fans_change/post_sys）通知列表。
  /// 返回 `(通知列表, next_offset)`；每个条目含 msg_id/msg_type + data(JSON)。
  Future<(List<DynamicsNotice>, int)> fetchChannelNotice(
    String channel, {
    int offset = 0,
  }) async {
    final ret = await _getMap(_url4('miniw/msg_box', 'get_channel_msg_list', {
      'uin': '$uin',
      'channel': channel,
      'offset': '$offset',
    }));
    if ((ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) != 0) {
      return (<DynamicsNotice>[], 0);
    }
    final data = ret['data'];
    if (data is! Map) return (<DynamicsNotice>[], 0);
    final dm = data.cast<String, Object?>();
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
    final ret = await _getMap(_url4('miniw/msg_box', 'read_channel_msg', {
      'uin': '$uin',
      'channel': channel,
      'msg_id_list': msgIds.join(','),
    }));
    return (ret['code'] ?? ret['ret']) is num &&
        (ret['code'] ?? ret['ret']) == 0;
  }

  /// 动态红点（act=get_redpoint_notice_info，/miniw/posting）。
  /// 返回 {new_posting_notice, posting_edit_info}。
  Future<Map<String, Object?>> fetchRedpointNotice(String source) =>
      _getMap(_url('get_redpoint_notice_info', {'source': source}));

  /// 发表评论（act=add_comment）。
  Future<Map<String, Object?>> addComment(String pid, String content) =>
      _getMap(_url('add_comment', {'pid': pid, 'content': content}));

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
    debugPrint('[Dynamics get_comment_rep] url: $url');
    final resp = await _dio.get(url);
    final raw = resp.data;
    debugPrint('[Dynamics get_comment_rep] RAW: $raw');
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
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

  // ── 内部 ──────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _getMap(String url) async {
    final resp = await _dio.get(url);
    final raw = resp.data;
    final decoded = raw is String ? decodeHttpResponse(raw) : raw;
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }
}
