import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/player_home.dart';

void main() {
  group('PlayerHomeClient.shouldRecordVisit 访客记录去重', () {
    test('关闭"留下踪迹"时即便从未发送过也不上报', () {
      expect(
        PlayerHomeClient.shouldRecordVisit(
          leaveTrace: false,
          lastSentAt: 0,
          now: 1000000,
        ),
        isFalse,
      );
    });

    test('开启且从未发送（0）时上报', () {
      expect(
        PlayerHomeClient.shouldRecordVisit(
          leaveTrace: true,
          lastSentAt: 0,
          now: 1000000,
        ),
        isTrue,
      );
    });

    test('开启且 100 秒前发送过时不再上报', () {
      expect(
        PlayerHomeClient.shouldRecordVisit(
          leaveTrace: true,
          lastSentAt: 1000000 - 100,
          now: 1000000,
        ),
        isFalse,
      );
    });

    test('开启且距今 86399 秒（差一秒不满 24h）时不再上报', () {
      expect(
        PlayerHomeClient.shouldRecordVisit(
          leaveTrace: true,
          lastSentAt: 1000000 - 86399,
          now: 1000000,
        ),
        isFalse,
      );
    });

    test('开启且恰好 86400 秒前发送过时上报（对齐官方客户端）', () {
      expect(
        PlayerHomeClient.shouldRecordVisit(
          leaveTrace: true,
          lastSentAt: 1000000 - 86400,
          now: 1000000,
        ),
        isTrue,
      );
    });

    test('开启且 86401 秒前发送过时上报', () {
      expect(
        PlayerHomeClient.shouldRecordVisit(
          leaveTrace: true,
          lastSentAt: 1000000 - 86401,
          now: 1000000,
        ),
        isTrue,
      );
    });
  });
}
