/// 动态(Posting)服务客户端 —— /miniw/posting 与 /miniw/com_posting。
/// 移植自反编译源码 dynamicsdatamanager.lua：
///   - 好友 feed: POSTING + get_friend_posting (+ from)
///   - 热门/时间: COM_POSTING + get_list_by_hot / get_list_by_time (+ offset)
/// URL 用 act + http_getParamMD5 签名。
library;

import 'dart:convert' show jsonEncode;

import 'package:dio/dio.dart';

import '../crypto/md5_sign.dart'
    show httpGetParamKey, httpGetParamMd5, httpGetS1Map, httpGetS2Act;
import '../models/dynamics_models.dart';
import '../net/config.dart' show kApiId, kClientVersionStr, kDefaultBase, kDefaultUrls;
import '../net/http_factory.dart' show createDio;
import '../net/photo_upload.dart' show uploadPresignedFile;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';
import 'request_errors.dart' show reportIfFailed;

/// 既有 `import '.../services/dynamics.dart'` 调用点（含 `show` 形式）照旧可用：
/// 模型与解析已迁到 models/dynamics_models.dart，这里原样转发。
export '../models/dynamics_models.dart';

/// 本模块日志标签。
const String _logTag = 'Dynamics';

const String kCountry = 'CN';
const String kLang = '0';

const String kPostingPath = 'miniw/posting';
const String kComPostingPath = 'miniw/com_posting';

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
    final code = ret.raw['code'] ?? ret.raw['ret'];
    if (code is num && code != 0) {
      return (<DynamicsNotice>[], 0);
    }
    final dm = ret.data;
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
    final code = ret.raw['code'] ?? ret.raw['ret'];
    return code is num && code == 0;
  }

  /// 动态红点（act=get_redpoint_notice_info，/miniw/posting）。
  /// 返回 {new_posting_notice, posting_edit_info}（顶层或 data 下均可）。
  Future<DynamicsRedpointNotice> fetchRedpointNotice(String source) async {
    final ack =
        await _getAck(_url('get_redpoint_notice_info', {'source': source}));
    return DynamicsRedpointNotice.fromResponse(ack.raw);
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
    final flat = parseDynamicsNonEmptyString(m['url'] ?? m['pic_url']);
    if (flat != null) return flat;
    if (data is Map) {
      final u = parseDynamicsNonEmptyString(data['url'] ?? data['pic_url']);
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
    return parseDynamicsNonEmptyString(data['lottery_id'] ?? data['id']);
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
    return FeedResult(out, parseDynamicsInt(data, ['ct', 'next_ct']));
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
