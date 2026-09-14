import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/msg_box.dart';

/// /miniw/msg_box 解析器单元测试。
///
/// 每个解析器覆盖：合法载荷 / 缺键 / 错类型 / 空 / 非零 code·ret →
/// 文档化结果（空结果或 0），且绝不抛异常。
void main() {
  group('parseChannelMsgList', () {
    test('合法载荷：解析 msg_list 字段与 next_offset', () {
      final decoded = {
        'code': 0,
        'data': {
          'msg_list': [
            {
              'msg_id': 'r1',
              'msg_type': 'commented',
              'uin': 20002,
              'time': 1700000000,
              'location': '广东',
              'color': 'ignored',
              'data': jsonEncode({
                'content': '好棒',
                'pid_content': '我的第一条动态',
                'pid': '20002_1700000000',
                'pic_url': 'https://img/x.png',
              }),
            },
            {
              'msg_id': 'r2',
              'msg_type': 'prized',
              'state': 1,
              'time': '1700000001',
              'uin': '20003',
              'data': '{"content":"%E8%B5%9E"}',
            },
          ],
          'next_offset': 20,
        },
      };
      final page = parseChannelMsgList(decoded, channel: MsgBoxChannel.rep);
      expect(page.nextOffset, 20);
      expect(page.items, hasLength(2));

      final a = page.items.first;
      expect(a.msgId, 'r1');
      expect(a.channel, MsgBoxChannel.rep);
      expect(a.msgType, 'commented');
      expect(a.uin, 20002);
      expect(a.time, 1700000000);
      expect(a.location, '广东');
      expect(a.content, '好棒');
      expect(a.pidContent, '我的第一条动态');
      expect(a.pid, '20002_1700000000');
      expect(a.picUrl, 'https://img/x.png');
      expect(a.unread, isTrue);
      expect(a.hasDetail, isTrue);
      expect(a.headline, '评论了你的动态：我的第一条动态');

      final b = page.items.last;
      expect(b.status, 1);
      expect(b.unread, isFalse);
      expect(b.uin, 20003);
      expect(b.time, 1700000001);
      expect(b.content, '赞', reason: 'URL 编码内容需解码');
    });

    test('data 已是 Map 时同样解析', () {
      final page = parseChannelMsgList({
        'ret': 0,
        'data': {
          'msg_list': [
            {
              'msg_id': 'f1',
              'data': {'uin': 10001, 'time': 5, 'location': '北京'},
            },
          ],
        },
      }, channel: MsgBoxChannel.fans);
      expect(page.items.single.channel, MsgBoxChannel.fans);
      expect(page.items.single.uin, 10001);
      expect(page.items.single.location, '北京');
      expect(page.items.single.actionLabel, '关注了你');
    });

    test('缺键：缺 msg_id 的条目跳过，缺 data 也不抛异常', () {
      final page = parseChannelMsgList({
        'code': 0,
        'data': {
          'msg_list': [
            {'msg_id': 'ok'},
            {'msg_type': 'commented'}, // 缺 msg_id
            'not-a-map',
            42,
          ],
        },
      });
      expect(page.items, hasLength(1));
      expect(page.items.single.msgId, 'ok');
      expect(page.items.single.data, isEmpty);
    });

    test('缺 msg_list：空列表；next_offset 仍解析', () {
      final page = parseChannelMsgList({
        'code': 0,
        'data': {'next_offset': 7},
      });
      expect(page.items, isEmpty);
      expect(page.nextOffset, 7);
    });

    test('错类型：msg_list 非 List / next_offset 非数字 → 空 + 0', () {
      final page = parseChannelMsgList({
        'code': 0,
        'data': {'msg_list': 'oops', 'next_offset': 'abc'},
      });
      expect(page.items, isEmpty);
      expect(page.nextOffset, 0);
    });

    test('空响应 / 非 Map → 空页', () {
      expect(parseChannelMsgList(null).items, isEmpty);
      expect(parseChannelMsgList('').items, isEmpty);
      expect(parseChannelMsgList(const {}).items, isEmpty);
      expect(parseChannelMsgList({'code': 0}).items, isEmpty);
      expect(parseChannelMsgList({'code': 0, 'data': 'x'}).items, isEmpty);
    });

    test('非零 code / ret → 空结果', () {
      final payload = {
        'data': {
          'msg_list': [
            {'msg_id': 'r1'},
          ],
        },
      };
      expect(parseChannelMsgList({...payload, 'code': 1}).items, isEmpty);
      expect(parseChannelMsgList({...payload, 'ret': 100}).items, isEmpty);
      expect(parseChannelMsgList({...payload, 'ret': '2'}).items, isEmpty);
      expect(
        parseChannelMsgList({...payload, 'ret': 'boom'}).items,
        isEmpty,
        reason: '非数字错误码视为失败',
      );
    });
  });

  group('MsgBoxMessage.fromItem', () {
    test('非 Map / 缺 msg_id / msg_id 为 null 字符串 → null', () {
      expect(MsgBoxMessage.fromItem(null, channel: 'x'), isNull);
      expect(MsgBoxMessage.fromItem('raw', channel: 'x'), isNull);
      expect(MsgBoxMessage.fromItem(const {}, channel: 'x'), isNull);
      expect(
        MsgBoxMessage.fromItem(const {'msg_id': 'null'}, channel: 'x'),
        isNull,
      );
    });

    test('actionLabel：已知类型 / 粉丝频道 / 未知回退', () {
      MsgBoxMessage msg(String type) =>
          MsgBoxMessage(msgId: '1', channel: MsgBoxChannel.rep, msgType: type);
      expect(msg('commented').actionLabel, '评论了你的动态');
      expect(msg('prized').actionLabel, '👍了这条动态');
      expect(msg('add_at').actionLabel, '@了你');
      expect(msg('comment_reply').actionLabel, '回复了你的评论');
      expect(msg('answer').actionLabel, '回答了你的问题');
      expect(msg('map_prize').actionLabel, '赞了你的作品');
      expect(msg('1').actionLabel, '动态投票消息');
      expect(msg('9').actionLabel, '动态问答消息');
      expect(msg('something_new').actionLabel, 'something_new');
      expect(msg('').actionLabel, '互动消息');
      expect(
        MsgBoxMessage(msgId: '1', channel: MsgBoxChannel.fans).actionLabel,
        '关注了你',
      );
    });

    test('hasDetail：pid 缺失 / "0" → false', () {
      expect(
        MsgBoxMessage(msgId: '1', channel: 'c', pid: '1_2').hasDetail,
        isTrue,
      );
      expect(MsgBoxMessage(msgId: '1', channel: 'c').hasDetail, isFalse);
      expect(
        MsgBoxMessage(msgId: '1', channel: 'c', pid: '0').hasDetail,
        isFalse,
      );
    });

    test('错误类型的数字字段归一为 0', () {
      final m = MsgBoxMessage.fromItem(const {
        'msg_id': 'x',
        'uin': 'abc',
        'time': null,
        'status': 'nope',
      }, channel: 'c');
      expect(m, isNotNull);
      expect(m!.uin, 0);
      expect(m.time, 0);
      expect(m.status, 0);
    });
  });

  group('parseChannelMsgCount', () {
    test('data 为数字 / 数字字符串 / 对象', () {
      expect(parseChannelMsgCount({'code': 0, 'data': 3}), 3);
      expect(parseChannelMsgCount({'ret': 0, 'data': '4'}), 4);
      expect(parseChannelMsgCount({'ret': 0, 'data': {'count': 5}}), 5);
      expect(
        parseChannelMsgCount({'ret': 0, 'data': {'unread_count': '6'}}),
        6,
      );
      expect(
        parseChannelMsgCount({'code': 0, 'data': {'msgtotal': 9}}),
        9,
      );
    });

    test('缺键 / 错类型 / 空 / 非零 code → 0', () {
      expect(parseChannelMsgCount(null), 0);
      expect(parseChannelMsgCount(const {}), 0);
      expect(parseChannelMsgCount({'code': 0}), 0);
      expect(parseChannelMsgCount({'code': 0, 'data': 'abc'}), 0);
      expect(parseChannelMsgCount({'code': 0, 'data': {'nope': 1}}), 0);
      expect(parseChannelMsgCount({'code': 1, 'data': 3}), 0);
    });
  });

  group('parseMultiChannelRedpoints', () {
    test('data 为 {频道: 计数}', () {
      final m = parseMultiChannelRedpoints({
        'ret': 0,
        'data': {'post_rep': 1, 'fans_change': '2'},
      });
      expect(m, {'post_rep': 1, 'fans_change': 2});
    });

    test('channles 包裹 / 数组形态', () {
      expect(
        parseMultiChannelRedpoints({
          'code': 0,
          'data': {
            'channles': {'post_at': 3},
          },
        }),
        {'post_at': 3},
      );
      expect(
        parseMultiChannelRedpoints({
          'code': 0,
          'data': [
            {'channel': 'map_interact', 'count': 4},
            {'channelid': 'post_sys', 'unread': '5'},
          ],
        }),
        {'map_interact': 4, 'post_sys': 5},
      );
    });

    test('畸形条目跳过 / 非零 code / 空 → 空 map', () {
      expect(
        parseMultiChannelRedpoints({
          'code': 0,
          'data': [
            {'channel': 'post_rep'},
            {'count': 2},
            'oops',
          ],
        }),
        isEmpty,
      );
      expect(parseMultiChannelRedpoints({'code': 1, 'data': {'a': 1}}), isEmpty);
      expect(parseMultiChannelRedpoints(const {}), isEmpty);
      expect(parseMultiChannelRedpoints(null), isEmpty);
    });
  });

  group('parseMsgBoxOk', () {
    test('code/ret 为 0 → true', () {
      expect(parseMsgBoxOk({'code': 0}), isTrue);
      expect(parseMsgBoxOk({'ret': 0}), isTrue);
      expect(parseMsgBoxOk({'ret': '0'}), isTrue);
      expect(parseMsgBoxOk({'code': 0, 'data': {}}), isTrue);
    });

    test('非零 / 非数字错误码 → false', () {
      expect(parseMsgBoxOk({'code': 1}), isFalse);
      expect(parseMsgBoxOk({'ret': '100'}), isFalse);
      expect(parseMsgBoxOk({'code': 0, 'ret': 1}), isFalse);
      expect(parseMsgBoxOk({'ret': 'boom'}), isFalse);
    });

    test('空 / 非 Map → false；缺 code/ret 的非空对象 → true', () {
      expect(parseMsgBoxOk(null), isFalse);
      expect(parseMsgBoxOk(''), isFalse);
      expect(parseMsgBoxOk(const {}), isFalse);
      expect(parseMsgBoxOk({'data': {'ok': 1}}), isTrue);
    });
  });
}
