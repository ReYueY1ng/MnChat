import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/dynamics.dart';

/// dynamics.dart 新增结果类型的解析单元测试。
///
/// [DynamicsPost.fromItem] / [DynamicsComment.fromItem] / [DynamicsAuth] /
/// [DynamicsAck] / [DynamicsTopic] / [DynamicsVoteInfo] /
/// [DynamicsRedpointNotice.fromResponse] 的宽松解析契约：
/// 合法载荷 / 脏缺数据 / 空载荷 → 文档化结果，绝不抛异常。
///
/// [DynamicsLottery] 的解析覆盖见 dynamics_lottery_parse_test.dart。
void main() {
  group('DynamicsAck.fromMap', () {
    test('合法载荷：ret=0 + msg + data.vote_info', () {
      final ack = DynamicsAck.fromMap(const {
        'ret': 0,
        'msg': 'ok',
        'data': {
          'vote_info': {'vote_id': 'v1', 'title': 't'},
        },
      });
      expect(ack.code, 0);
      expect(ack.ok, isTrue);
      expect(ack.message, 'ok');
      expect(ack.voteInfo?.voteId, 'v1');
      expect(ack.voteInfo?.title, 't');
    });

    test('code 兜底：ret 缺失时读 code；非零即失败', () {
      final ack = DynamicsAck.fromMap(const {'code': 5, 'message': 'boom'});
      expect(ack.code, 5);
      expect(ack.ok, isFalse);
      expect(ack.message, 'boom');
      expect(ack.voteInfo, isNull);
    });

    test('脏数据：非数值 code → 0（宽松语义，视为成功）', () {
      expect(DynamicsAck.fromMap(const {'code': 'boom'}).code, 0);
      expect(DynamicsAck.fromMap(const {'ret': 'x'}).ok, isTrue);
      expect(DynamicsAck.fromMap(const {'data': 'not-a-map'}).voteInfo, isNull);
    });

    test('空载荷 → code 0 / 空文案 / 无投票信息', () {
      final ack = DynamicsAck.fromMap(const {});
      expect(ack.code, 0);
      expect(ack.message, '');
      expect(ack.voteInfo, isNull);
    });
  });

  group('DynamicsTopic.parseList', () {
    test('合法载荷：topic_list 数字与字符串 id 混合', () {
      final topics = DynamicsTopic.parseList(const {
        'topic_list': [
          {'topic_id': 11, 'title': 'a'},
          {'topic_id': '12', 'title': 'b'},
        ],
      });
      expect(topics.length, 2);
      expect(topics[0].topicId, '11');
      expect(topics[0].title, 'a');
      expect(topics[1].topicId, '12');
      expect(topics[1].title, 'b');
    });

    test('list 别名与脏条目跳过', () {
      final topics = DynamicsTopic.parseList(const {
        'list': [
          42, // 非 Map / 非字符串 → 脏，跳过
          {'title': ''},
          {'topic_id': 0, 'title': 'kept'},
        ],
      });
      expect(topics.length, 1);
      expect(topics.single.title, 'kept');
      expect(topics.single.topicId, '0');
    });

    test('裸数组 + 字符串条目（实测 get_topic_list / 动态 topic_list）', () {
      final topics = DynamicsTopic.parseList(const <Object?>[
        'u:1813749331:1704717010',
        {'topic_id': 'o:21', 'title': '官方'},
        '   ',
        7,
      ]);
      expect(topics.length, 2);
      expect(topics[0].topicId, 'u:1813749331:1704717010');
      expect(topics[0].title, '');
      expect(topics[1].topicId, 'o:21');
      expect(topics[1].title, '官方');
    });

    test('空 / 缺键 / 错类型 → 空列表', () {
      expect(DynamicsTopic.parseList(const {}), isEmpty);
      expect(DynamicsTopic.parseList(const {'topic_list': 'x'}), isEmpty);
      expect(DynamicsTopic.parseList(const {'topic_list': []}), isEmpty);
    });
  });

  group('DynamicsVoteInfo', () {
    test('合法载荷：vote_info 包裹 + 选项计数', () {
      final info = DynamicsVoteInfo.fromMap(const {
        'vote_info': {
          'vote_id': 'v9',
          'title': '选哪个',
          'end_time': 123,
          'multi_mode': 1,
          'mode': 0,
          'option_list': [
            {'text': 'A', 'count': 2},
            {'index': 2, 'text': 'B', 'num': '3'},
          ],
        },
      });
      expect(info?.voteId, 'v9');
      expect(info?.title, '选哪个');
      expect(info?.endTime, 123);
      expect(info?.multiMode, 1);
      expect(info?.options.length, 2);
      expect(info?.options[0].index, 1);
      expect(info?.options[0].count, 2);
      expect(info?.options[1].index, 2);
      expect(info?.options[1].count, 3);
    });

    test('未包裹（get_vote_info 直接 data）：数字 vote_id 与脏选项', () {
      final info = DynamicsVoteInfo.fromMap(const {
        'vote_id': 7788,
        'options': [
          'bad',
          {'text': 'only-text'},
        ],
      });
      expect(info?.voteId, '7788');
      expect(info?.options.length, 1);
      expect(info?.options.single.text, 'only-text');
      expect(info?.options.single.count, 0);
    });

    test('空 / 无有效字段 → null', () {
      expect(DynamicsVoteInfo.fromMap(const {}), isNull);
      expect(DynamicsVoteInfo.fromMap(const {'vote_info': {}}), isNull);
      expect(DynamicsVoteInfo.fromMap(const {'other': 1}), isNull);
    });
  });

  group('DynamicsRedpointNotice.fromResponse', () {
    test('合法载荷：顶层字段', () {
      final n = DynamicsRedpointNotice.fromResponse(const {
        'ret': 0,
        'new_posting_notice': 3,
        'posting_edit_info': 1,
      });
      expect(n.newPostingNotice, 3);
      expect(n.postingEditInfo, 1);
    });

    test('data 包裹 + 数字字符串', () {
      final n = DynamicsRedpointNotice.fromResponse(const {
        'ret': 0,
        'data': {'new_posting_notice': '2'},
      });
      expect(n.newPostingNotice, 2);
      expect(n.postingEditInfo, 0);
    });

    test('空 / 脏 → 0', () {
      expect(DynamicsRedpointNotice.fromResponse(const {}).newPostingNotice, 0);
      expect(
        DynamicsRedpointNotice.fromResponse(
          const {'new_posting_notice': 'x'},
        ).newPostingNotice,
        0,
      );
    });
  });

  group('DynamicsPost.fromItem 新字段', () {
    test('完整真实条目：auth_see / video_res_id / lottery_id / vote_id / topic_list / pics', () {
      final p = DynamicsPost.fromItem(const <String, Object?>{
        'pid': '273640665_1787757890',
        'content': '今天的迷你世界真好看',
        'create_time': 1787757890,
        'ctype': 1,
        'nickname': '小迷你',
        'header': 'https://img.example/head.png',
        'cai': 12,
        'comment_count': 3,
        'share': 4,
        'auth_see': 2,
        'video_res_id': 'vid_abcdef',
        'lottery_id': 'L20261006',
        'vote_id': 'V7788',
        'topic_list': [
          {'topic_id': 111, 'title': '迷你世界'},
        ],
        'pic_list': [
          {'url': 'https://img.example/a.jpg', 'width': 1080, 'height': 720},
        ],
      });
      expect(p, isNotNull);
      final post = p!;
      expect(post.pid, '273640665_1787757890');
      expect(post.uin, 273640665); // 由 pid 拆分兜底
      expect(post.createTime, 1787757890);
      expect(post.nickname, '小迷你');
      expect(post.likeCount, 12);
      expect(post.commentCount, 3);
      expect(post.shareCount, 4);
      // ── 新增字段 ──
      expect(post.authSee, 2);
      expect(post.videoResId, 'vid_abcdef');
      expect(post.lotteryId, 'L20261006');
      expect(post.voteId, 'V7788');
      expect(post.isLottery, isTrue);
      expect(post.topics.length, 1);
      expect(post.topics.single.topicId, '111');
      expect(post.topics.single.title, '迷你世界');
      expect(post.pics.single.width, 1080);
      expect(post.pics.single.height, 720);
    });

    test('数字 pid：字符串化并回填 uin；缺省字段降级为 0/空/null', () {
      final p = DynamicsPost.fromItem(const {'pid': 273640665, 'content': 'hi'});
      final post = p!;
      expect(post.pid, '273640665');
      expect(post.uin, 273640665);
      expect(post.content, 'hi');
      expect(post.authSee, 0);
      expect(post.videoResId, isNull);
      expect(post.lotteryId, isNull);
      expect(post.voteId, isNull);
      expect(post.isLottery, isFalse);
      expect(post.topics, isEmpty);
    });

    test('缺 pid → null；posting_id 别名可解析', () {
      expect(DynamicsPost.fromItem(const {}), isNull);
      expect(DynamicsPost.fromItem(const {'content': 'x'}), isNull);
      final p = DynamicsPost.fromItem(const {'posting_id': '5_6'});
      expect(p?.pid, '5_6');
      expect(p?.uin, 5);
      expect(p?.createTime, 6);
    });

    test('vote_id 优先于 share_vote；无 vote_id 时用 share_vote 兜底', () {
      final withVote = DynamicsPost.fromItem(
        const {'pid': '1_2', 'vote_id': 'v1', 'share_vote': 'sv1'},
      );
      expect(withVote?.voteId, 'v1'); // 显式 vote_id 胜出
      final shareOnly = DynamicsPost.fromItem(
        const {'pid': '1_2', 'share_vote': 'sv1'},
      );
      expect(shareOnly?.voteId, 'sv1');
      expect(DynamicsPost.fromItem(const {'pid': '1_2'})?.voteId, isNull);
    });

    test('topic_list 为 {id: {...}} 映射形态：取每条 value，脏值跳过', () {
      final p = DynamicsPost.fromItem(const <String, Object?>{
        'pid': '1_2',
        'topic_list': <String, Object?>{
          '111': {'topic_id': 111, 'title': 'a'},
          'dirty': 'not-a-map',
        },
      });
      expect(p?.topics.length, 1);
      expect(p?.topics.single.topicId, '111');
      expect(p?.topics.single.title, 'a');
    });

    test('topic_list 为字符串数组形态（实测动态条目形态）：非字符串/空串跳过', () {
      final p = DynamicsPost.fromItem(const <String, Object?>{
        'pid': '1_2',
        'topic_list': <Object?>['u:1813749331:1704717010', '', '   ', 42],
      });
      expect(p?.topics.length, 1);
      expect(p?.topics.single.topicId, 'u:1813749331:1704717010');
      expect(p?.topics.single.title, '');
    });

    test('脏数据：非 Map 话题条目 + 数值字符串 + 空白/字面 null 字段，不抛且降级', () {
      final p = DynamicsPost.fromItem(const <String, Object?>{
        'pid': '9_8',
        'uin': 'oops', // 字符串 uin 不被 _int 接受 → 0，由 pid 兜底
        'auth_see': '3', // 数值字符串被 _pickInt 接受
        'video_res_id': 'null', // 字面 'null' → null
        'topic_list': <Object?>[42, true, <String, Object?>{}],
      });
      expect(p, isNotNull);
      final post = p!;
      expect(post.uin, 9); // pid 拆分兜底
      expect(post.createTime, 8);
      expect(post.authSee, 3);
      expect(post.videoResId, isNull);
      expect(post.lotteryId, isNull);
      expect(post.voteId, isNull);
      expect(post.isLottery, isFalse);
      expect(post.topics, isEmpty);
      expect(post.content, '');
    });

    test('withProfile 覆盖画像字段并保留新字段', () {
      final base = DynamicsPost.fromItem(const {
        'pid': '273640665_1787757890',
        'nickname': '旧名',
        'auth_see': 2,
        'video_res_id': 'vid1',
        'lottery_id': 'L1',
        'vote_id': 'V1',
        'topic_list': [
          {'topic_id': 7, 'title': 't7'},
        ],
      })!;
      final merged =
          base.withProfile(nickname: '新名', avatar: 'av', headFrameId: 9);
      expect(merged.nickname, '新名');
      expect(merged.avatar, 'av');
      expect(merged.headFrameId, 9);
      expect(merged.authSee, 2);
      expect(merged.videoResId, 'vid1');
      expect(merged.lotteryId, 'L1');
      expect(merged.voteId, 'V1');
      expect(merged.topics.single.topicId, '7');
      expect(merged.isLottery, isTrue);
      // 无参调用保留原画像
      final kept = base.withProfile();
      expect(kept.nickname, '旧名');
      expect(kept.headFrameId, isNull);
    });
  });

  group('DynamicsAuth', () {
    test('五个可见范围 id → 中文标签', () {
      expect(DynamicsAuth.labels[DynamicsAuth.all], '公开');
      expect(DynamicsAuth.labels[DynamicsAuth.onlyFans], '仅粉丝');
      expect(DynamicsAuth.labels[DynamicsAuth.homeHide], '主页隐藏');
      expect(DynamicsAuth.labels[DynamicsAuth.onlySelf], '仅自己');
      expect(DynamicsAuth.labels[DynamicsAuth.onlyFamily], '仅家族');
    });

    test('label() 覆盖五个 id，未知回退「公开」', () {
      expect(DynamicsAuth.label(0), '公开');
      expect(DynamicsAuth.label(1), '仅粉丝');
      expect(DynamicsAuth.label(2), '主页隐藏');
      expect(DynamicsAuth.label(3), '仅自己');
      expect(DynamicsAuth.label(4), '仅家族');
      expect(DynamicsAuth.label(99), '公开');
      expect(DynamicsAuth.label(-1), '公开');
    });

    test('ptype 常量与协议对齐', () {
      expect(DynamicsAuth.ptypeSee, 'see');
      expect(DynamicsAuth.ptypeRep, 'rep');
      expect(DynamicsAuth.ptypeHome, 'home');
    });
  });

  group('DynamicsComment.fromItem', () {
    test('一级评论：无 rep_uin → 作者取 uin，content URL 解码', () {
      final c = DynamicsComment.fromItem(const {
        'uin': 273640665,
        'content': 'hello%20world',
        'last_time': 1700000000,
        'cai': 5,
        'com_cnt': 2,
        'location': '北京',
        'rep_id': 'rep_1',
        'nickname': '小明',
      });
      expect(c, isNotNull);
      final cm = c!;
      expect(cm.uin, 273640665);
      expect(cm.content, 'hello world');
      expect(cm.createTime, 1700000000);
      expect(cm.lastTime, 1700000000);
      expect(cm.likeCount, 5);
      expect(cm.replyCount, 2);
      expect(cm.location, '北京');
      expect(cm.nickname, '小明');
      expect(cm.repId, 'rep_1');
      expect(cm.opUin, 0); // 一级评论服务端下发 op_uin=0，不做作者兜底（live 探针）
      expect(cm.pidUin, 0);
      expect(cm.pidCt, 0);
    });

    test('回复条目：rep_uin 存在 → 作者取回复者，op_uin 为被回复者', () {
      final r = DynamicsComment.fromItem(const {
        'uin': 111, // 原评论作者
        'rep_uin': 222, // 回复者
        'op_uin': 333, // 被回复者
        'content': '%E5%9B%9E%E5%A4%8D', // 「回复」
        'rep_time': 1700000001,
        'rep_id': 'rep_99',
      })!;
      expect(r.uin, 222);
      expect(r.opUin, 333);
      expect(r.content, '回复');
      expect(r.createTime, 1700000001); // 取 rep_time
      expect(r.repId, 'rep_99');
      expect(r.lastTime, 0);
    });

    test('rep_uin 字符串容忍；rep_uin=0 回退 uin', () {
      final byStr = DynamicsComment.fromItem(
        const {'uin': 111, 'rep_uin': '222', 'content': 'x'},
      )!;
      expect(byStr.uin, 222);
      final byZero = DynamicsComment.fromItem(
        const {'uin': 111, 'rep_uin': 0, 'content': 'x'},
      )!;
      expect(byZero.uin, 111);
    });

    test('pid 拆分回填 pidUin/pidCt（显式键缺失时）', () {
      final split = DynamicsComment.fromItem(const {
        'uin': 555,
        'content': 'c',
        'pid': '273640665_1787757890',
      })!;
      expect(split.pidUin, 273640665);
      expect(split.pidCt, 1787757890);
    });

    test('显式 pid_uin/pid_ct 优先；部分缺失时仅补缺的一侧', () {
      final explicit = DynamicsComment.fromItem(const {
        'uin': 555,
        'content': 'c',
        'pid': '9_8',
        'pid_uin': 111,
        'pid_ct': 222,
      })!;
      expect(explicit.pidUin, 111);
      expect(explicit.pidCt, 222);
      final partial = DynamicsComment.fromItem(const {
        'uin': 555,
        'content': 'c',
        'pid': '7_8',
        'pid_uin': 5,
      })!;
      expect(partial.pidUin, 5);
      expect(partial.pidCt, 8); // 由 pid 拆分补齐
    });

    test('repId 缺省 → 空串；last_time 数值字符串容忍', () {
      final c = DynamicsComment.fromItem(
        const {'uin': 1, 'content': 'x', 'last_time': '1700000000'},
      )!;
      expect(c.repId, '');
      expect(c.lastTime, 1700000000);
    });

    test('content 缺失或空串 → null；空白字符按原样保留', () {
      expect(DynamicsComment.fromItem(const {}), isNull);
      expect(DynamicsComment.fromItem(const {'uin': 1}), isNull);
      expect(DynamicsComment.fromItem(const {'uin': 1, 'content': ''}), isNull);
      final ws = DynamicsComment.fromItem(const {'uin': 1, 'content': ' '});
      expect(ws, isNotNull);
      expect(ws!.content, ' ');
    });
  });

  group('DynamicsAck.shareCount / data', () {
    test('shareCount：data.share 存在且非 0 → 数值（含别名与字符串）', () {
      expect(
        DynamicsAck.fromMap(const {
          'ret': 0,
          'data': {'share': 7},
        }).shareCount,
        7,
      );
      expect(
        DynamicsAck.fromMap(const {
          'ret': 0,
          'data': {'share': '7'},
        }).shareCount,
        7,
      );
      expect(
        DynamicsAck.fromMap(const {
          'ret': 0,
          'data': {'share_count': 3},
        }).shareCount,
        3,
      );
    });

    test('shareCount：share 缺失或 0 → null', () {
      expect(
        DynamicsAck.fromMap(const {
          'ret': 0,
          'data': <String, Object?>{},
        }).shareCount,
        isNull,
      );
      expect(
        DynamicsAck.fromMap(const {
          'ret': 0,
          'data': {'share': 0},
        }).shareCount,
        isNull,
      );
      expect(DynamicsAck.fromMap(const {'ret': 0}).shareCount, isNull);
      expect(const DynamicsAck().shareCount, isNull);
    });

    test('data getter：缺失/非 Map → 空 map；rawData 保留原值', () {
      expect(DynamicsAck.fromMap(const {}).data, isEmpty);
      expect(DynamicsAck.fromMap(const {}).rawData, isNull);
      expect(DynamicsAck.fromMap(const {'data': 'nope'}).data, isEmpty);
      expect(DynamicsAck.fromMap(const {'data': 'nope'}).rawData, 'nope');
      expect(DynamicsAck.fromMap(const {'data': [1, 2]}).data, isEmpty);
      expect(DynamicsAck.fromMap(const {'data': [1, 2]}).rawData, [1, 2]);
      expect(const DynamicsAck().data, isEmpty);
      expect(const DynamicsAck().rawData, isNull);
      final d = DynamicsAck.fromMap(const {
        'data': {'share': 2, 'x': 'y'},
      });
      expect(d.data['share'], 2);
      expect(d.data['x'], 'y');
      expect(d.rawData, {'share': 2, 'x': 'y'});
    });
  });

  group('DynamicsVoteInfo.fromItem', () {
    test('选项缺 index 时按 1-based 位置兜底', () {
      final info = DynamicsVoteInfo.fromItem(const {
        'vote_id': 'v1',
        'option_list': [
          {'text': 'A'},
          {'text': 'B'},
        ],
      });
      expect(info?.options.length, 2);
      expect(info?.options[0].index, 1);
      expect(info?.options[1].index, 2);
    });

    test('仅有选项、无 vote_id 仍保留；皆空 → null', () {
      final info = DynamicsVoteInfo.fromItem(const {
        'options': [
          {'text': 'A', 'count': '2'},
        ],
      });
      expect(info?.voteId, '');
      expect(info?.options.single.count, 2);
      expect(DynamicsVoteInfo.fromItem(const {}), isNull);
      expect(DynamicsVoteInfo.fromItem(const {'title': 'x'}), isNull);
    });

    test('fromMap：vote_info 包裹与裸 data 两种形态均可', () {
      final wrapped = DynamicsVoteInfo.fromMap(const {
        'vote_info': {
          'vote_id': 'v2',
          'option_list': [
            {'text': 'A'},
          ],
        },
      });
      expect(wrapped?.voteId, 'v2');
      final bare = DynamicsVoteInfo.fromMap(const {
        'vote_id': 'v3',
        'end_time': 100,
      });
      expect(bare?.voteId, 'v3');
      expect(bare?.endTime, 100);
    });
  });

  group('DynamicsTopic.fromItem', () {
    test('id 与标题皆空（或 id 为 0/null）→ null', () {
      expect(DynamicsTopic.fromItem(const {}), isNull);
      expect(DynamicsTopic.fromItem(const {'topic_id': 0}), isNull);
      expect(DynamicsTopic.fromItem(const {'topic_id': 'null'}), isNull);
      expect(DynamicsTopic.fromItem(const {'topic_id': ''}), isNull);
    });

    test('topicId 为字符串：数字 / 官方 o: / 玩家 u: 形态', () {
      final byTitle = DynamicsTopic.fromItem(const {'title': 'kept'});
      expect(byTitle?.topicId, '');
      expect(byTitle?.title, 'kept');
      expect(DynamicsTopic.fromItem(const {'topic_id': 9})?.topicId, '9');
      expect(DynamicsTopic.fromItem(const {'id': 'o:21'})?.topicId, 'o:21');
      final player = DynamicsTopic.fromItem(
        const {'topic_id': 'u:1813749331:1704717010'},
      );
      expect(player?.topicId, 'u:1813749331:1704717010');
      expect(player?.title, '');
    });
  });
}
