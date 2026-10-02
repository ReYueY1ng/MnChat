import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/player_home.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/storage/settings_store.dart';

void main() {
  group('留下踪迹开关读的是持久化值', () {
    // 回归：曾经读 `leaveVisitTraceProvider`，而它的 build() 先同步返回默认值，
    // 持久化的值要等异步加载才写回 —— 冷启动后先去别人主页时开关被无视。
    test('未设置过默认**关闭**；显式打开之后才是开启', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = SettingsStore(db);

      // 默认关：看一眼别人主页就在对方访客记录里留一条，属于会通知到第三方的
      // 动作，不该默默替用户选上。
      expect(await PlayerHomeClient.leaveTraceEnabled(store), isFalse);
      await store.setBool(SettingsKeys.leaveVisitTrace, true);
      expect(await PlayerHomeClient.leaveTraceEnabled(store), isTrue);
      await store.setBool(SettingsKeys.leaveVisitTrace, false);
      expect(await PlayerHomeClient.leaveTraceEnabled(store), isFalse);
    });

    test('关掉开关后 shouldRecordVisit 一律不上报（含首次访问）', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = SettingsStore(db);
      await store.setBool(SettingsKeys.leaveVisitTrace, false);

      final leaveTrace = await PlayerHomeClient.leaveTraceEnabled(store);
      expect(
        PlayerHomeClient.shouldRecordVisit(
          leaveTrace: leaveTrace,
          lastSentAt: 0,
          now: 1000000,
        ),
        isFalse,
      );
    });
  });

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
