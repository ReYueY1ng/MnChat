import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/message_center.dart';

/// 消息中心 msgcenter 侧新增解析器 / 频道表单元测试。
///
/// [parseChannelsInfo] 与 [MsgItem.fromDetail] 的 status 位兜底：
/// 合法载荷 / 缺键 / 错类型 / 空 / 非零 ret → 文档化结果，绝不抛异常。
void main() {
  group('parseChannelsInfo', () {
    test('合法载荷：{频道: 计数} 数字与对象混合', () {
      final map = parseChannelsInfo({
        'ret': 0,
        'data': {
          '1': 3,
          '2': {'unread': 2, 'total': 5},
          '10005': '4',
          '20002': {'count': 1},
        },
      });
      expect(map[1], const ChannelSummary(channel: 1, unread: 3, total: 3));
      expect(map[2], const ChannelSummary(channel: 2, unread: 2, total: 5));
      expect(map[10005], const ChannelSummary(channel: 10005, unread: 4, total: 4));
      expect(map[20002], const ChannelSummary(channel: 20002, unread: 1, total: 1));
    });

    test('channles 包裹（对齐 fetch_reddot 形态）', () {
      final map = parseChannelsInfo({
        'code': 0,
        'data': {
          'channles': {'1': 7},
        },
      });
      expect(map, {1: const ChannelSummary(channel: 1, unread: 7, total: 7)});
    });

    test('数组形态：[{channelid, unread}]', () {
      final map = parseChannelsInfo({
        'ret': 0,
        'data': [
          {'channelid': 20003, 'unread': 2},
          {'channel_id': '10005', 'count': '3'},
        ],
      });
      expect(map[20003]?.unread, 2);
      expect(map[10005]?.unread, 3);
    });

    test('解析不了的条目跳过（非频道键 / 值类型不符 / 缺频道 id）', () {
      final map = parseChannelsInfo({
        'ret': 0,
        'data': {
          'msgtotal': 10,
          'abc': 1,
          '1': true,
          '2': ['nope'],
        },
      });
      expect(map, isEmpty);
      expect(
        parseChannelsInfo({
          'ret': 0,
          'data': [
            {'count': 3},
            'oops',
            {'channelid': 0, 'count': 3},
          ],
        }),
        isEmpty,
      );
    });

    test('空 / 缺 data / 非 Map / 非零 ret → 空 map', () {
      expect(parseChannelsInfo(null), isEmpty);
      expect(parseChannelsInfo(const {}), isEmpty);
      expect(parseChannelsInfo({'ret': 0}), isEmpty);
      expect(parseChannelsInfo({'ret': 0, 'data': 'x'}), isEmpty);
      expect(parseChannelsInfo({'ret': 1, 'data': {'1': 5}}), isEmpty);
      expect(parseChannelsInfo({'code': 'boom', 'data': {'1': 5}}), isEmpty);
    });

    test('摘要对象缺少计数字段 → 0/0（不算错误，频道仍在）', () {
      final map = parseChannelsInfo({
        'ret': 0,
        'data': {
          '1': {'other': 9},
        },
      });
      expect(map[1], const ChannelSummary(channel: 1));
    });
  });

  group('MsgItem.fromDetail status 位兜底', () {
    test('status=1（已读）→ readState=1，未领取', () {
      final item = MsgItem.fromDetail(1, const {
        'id': 'm1',
        'title': 't',
        'status': 1,
      });
      expect(item.readState, 1);
      expect(item.unread, isFalse);
      expect(item.attachmentTaken, isFalse);
    });

    test('status=2（已领取）→ 未读 + 附件已领取', () {
      final item = MsgItem.fromDetail(1, const {'id': 'm1', 'status': 2});
      expect(item.readState, 0);
      expect(item.unread, isTrue);
      expect(item.attachmentTaken, isTrue);
    });

    test('status=3（已读+已领取）', () {
      final item = MsgItem.fromDetail(1, const {'id': 'm1', 'status': 3});
      expect(item.readState, 1);
      expect(item.attachmentTaken, isTrue);
    });

    test('readState 显式存在时优先于 status', () {
      final item = MsgItem.fromDetail(1, const {
        'id': 'm1',
        'readState': 0,
        'status': 3,
      });
      expect(item.readState, 0);
      expect(item.attachmentTaken, isTrue, reason: 'status 位仍用于附件');
    });

    test('缺 status / 错类型 → 未读且未领取，不抛异常', () {
      expect(MsgItem.fromDetail(1, const {'id': 'm1'}).readState, 0);
      final item = MsgItem.fromDetail(1, const {'id': 'm1', 'status': 'x'});
      expect(item.readState, 0);
      expect(item.attachmentTaken, isFalse);
      final item2 = MsgItem.fromDetail(1, const {'id': 'm1', 'status': '3'});
      expect(item2.readState, 1, reason: '数字字符串同样兼容');
      expect(item2.attachmentTaken, isTrue);
    });
  });

  group('MsgChannel 频道表', () {
    test('新 7 分类名称与顺序', () {
      expect(MsgChannel.categoryOrder, const [
        MsgChannel.gift,
        MsgChannel.systemMail,
        MsgChannel.creator,
        MsgChannel.sysMsg,
        MsgChannel.friendMail,
        MsgChannel.activityAssistant,
        MsgChannel.activity,
      ]);
      expect(MsgChannel.name(MsgChannel.gift), '礼物消息');
      expect(MsgChannel.name(MsgChannel.systemMail), '官方邮件');
      expect(MsgChannel.name(MsgChannel.creator), '创作者助手');
      expect(MsgChannel.name(MsgChannel.sysMsg), '系统消息');
      expect(MsgChannel.name(MsgChannel.friendMail), '好友邮件');
      expect(MsgChannel.name(MsgChannel.activityAssistant), '动态助手');
      expect(MsgChannel.name(MsgChannel.activity), '运营活动');
    });

    test('msgcenter 频道集合不含动态助手（0 走 msg_box）', () {
      expect(MsgChannel.mailChannels, isNot(contains(0)));
      expect(MsgChannel.mailChannels, contains(MsgChannel.creator));
      expect(MsgChannel.categoryOrder, contains(0));
    });

    test('未收录频道回退 频道N', () {
      expect(MsgChannel.name(999), '频道999');
    });
  });
}
