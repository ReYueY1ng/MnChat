import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/dynamics.dart';

/// dynamics.dart 新增结果类型的解析单元测试。
///
/// [DynamicsAck.fromMap] / [DynamicsTopic.parseList] / [DynamicsVoteInfo] /
/// [DynamicsRedpointNotice.fromResponse] 的宽松解析契约：
/// 合法载荷 / 脏缺数据 / 空载荷 → 文档化结果，绝不抛异常。
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
      expect(topics[0].topicId, 11);
      expect(topics[0].title, 'a');
      expect(topics[1].topicId, 12);
      expect(topics[1].title, 'b');
    });

    test('list 别名与脏条目跳过', () {
      final topics = DynamicsTopic.parseList(const {
        'list': [
          'oops',
          {'title': ''},
          {'topic_id': 0, 'title': 'kept'},
        ],
      });
      expect(topics.length, 1);
      expect(topics.single.title, 'kept');
      expect(topics.single.topicId, 0);
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
}
