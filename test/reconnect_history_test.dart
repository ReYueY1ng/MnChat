// 重连后「补拉哪些会话历史」的纯函数测试。
//
// 目的：重连不再无条件拉最近 20 个会话（chat_query 是消费式读取，一次重连就是
// 20 次请求），只挑掉线窗口内有动静的 + 未读的 + 少量兜底。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat/reconnect_history.dart';

/// 掉线时刻（秒 1700000000）。
final DateTime _droppedAt = DateTime.fromMillisecondsSinceEpoch(
  1700000000 * 1000,
);

ChatSession _session(int id, {int unread = 0, int? lastTime}) => ChatSession(
  id: id,
  type: ChatSessionType.friend,
  name: '$id',
  unreadCount: unread,
  lastMessage: lastTime == null
      ? null
      : ChatMessage(uin: id, text: 'x', time: lastTime),
);

void main() {
  group('reconnectHistoryTargets', () {
    test('未读 > 0 的会话一定补拉', () {
      final targets = reconnectHistoryTargets(<ChatSession>[
        _session(1, unread: 2, lastTime: 1699000000), // 很旧但有未读
        _session(2, lastTime: 1699000000), // 很旧且已读
      ], _droppedAt);
      expect(targets, contains(1));
      expect(targets, contains(2)); // 兜底（最近 N 个）
      expect(targets, hasLength(2));
    });

    test('最后一条消息落在掉线窗口内（含宽限）→ 补拉', () {
      final inWindow = _session(10, lastTime: 1700000000 - 30);
      final atEdge = _session(11, lastTime: 1700000000 - 59);
      final tooOld = _session(12, lastTime: 1700000000 - 600);
      final targets = reconnectHistoryTargets(
        <ChatSession>[inWindow, atEdge, tooOld],
        _droppedAt,
      );
      expect(targets, contains(10));
      expect(targets, contains(11));
      // 12 靠兜底入选（最近 3 个），但窗口判定本身不包含它：用只有它 + 4 个
      // 更老的会话来证明窗口之外不单独入选。
      final onlyOld = reconnectHistoryTargets(<ChatSession>[
        _session(20, lastTime: 1700000000 - 600),
        _session(21, lastTime: 1700000000 - 700),
        _session(22, lastTime: 1700000000 - 800),
        _session(23, lastTime: 1700000000 - 900),
      ], _droppedAt);
      expect(onlyOld, <int>[20, 21, 22]); // 兜底 3 个，不是 4 个
    });

    test('没有消息的会话不参与（没有历史可补）', () {
      final targets = reconnectHistoryTargets(<ChatSession>[
        _session(30, unread: 5),
      ], _droppedAt);
      expect(targets, isEmpty);
    });

    test('按最近消息倒序排列，最多 20 个', () {
      final many = <ChatSession>[
        for (var i = 1; i <= 25; i++)
          _session(i, unread: 1, lastTime: 1700000000 - i * 10),
      ];
      final targets = reconnectHistoryTargets(many, _droppedAt);
      expect(targets, hasLength(kReconnectHistoryMax));
      expect(targets.first, 1); // 最近的一条在最前
    });

    test('droppedAt 为 null（没有掉线记录）时只按未读 + 兜底挑', () {
      final targets = reconnectHistoryTargets(<ChatSession>[
        _session(40, unread: 1, lastTime: 1),
        _session(41, lastTime: 1700000000 - 10), // 时间是新的，但没有掉线窗口参照
        _session(42, lastTime: 2),
      ], null);
      expect(targets, contains(40)); // 未读
      expect(targets, contains(41)); // 兜底（最近 3 个里的第一个）
    });
  });
}
