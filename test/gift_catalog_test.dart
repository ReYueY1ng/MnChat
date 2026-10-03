import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/gift_catalog.dart';

/// 礼物目录解析：对齐 `NewFriendGiftInterface:OpenFriendGiftMainUI`
/// （`gift.gift_cfg` 每项带一层 `ctrl`，不能把 ctrl 里的字段当成一项）。
void main() {
  const config = '''
{
  gift = {
    select_times = 1,
    day_intimacies_limit = 200,
    gift_cfg = {
      {
        id = 43004,
        cost_id = 10002,
        cost_num = 20,
        intimacies = 10,
        charm_value = 5,
        if_free = 0,
        if_advert = 0,
        is_time_limit = 0,
        ctrl = {
          apiid = 110,
        },
      },
      {
        id = 43010,
        cost_id = 10000,
        cost_num = 0,
        intimacies = 30,
        charm_value = 12,
        if_free = 1,
        if_advert = 1,
        is_time_limit = 1,
        startTime = 1,
        endTime = 99999999999999,
      },
      {
        id = 43099,
        cost_id = 10002,
        cost_num = 5,
        intimacies = 1,
        is_time_limit = 1,
        startTime = 1,
        endTime = 2,
      },
    },
  },
}''';

  group('parseGiftCatalog', () {
    test('按 id/cost 解析，ctrl 块不会混进来', () {
      final c = parseGiftCatalog(config);
      expect(c.items.length, 3);
      expect(c.items.map((g) => g.id), [43004, 43010, 43099]);
      expect(c.defaultTimes, 1);
      expect(c.dayIntimaciesLimit, 200);

      final paid = c.byId(43004)!;
      expect(paid.costNum, 20);
      expect(paid.currency, '迷你币');
      expect(paid.intimacies, 10);
      expect(paid.charmValue, 5);
      expect(paid.free, isFalse);
      expect(paid.ad, isFalse);

      final free = c.byId(43010)!;
      expect(free.currency, '迷你豆');
      expect(free.free, isTrue);
      expect(free.ad, isTrue);
    });

    test('限时礼物过期后 activeAt 过滤掉', () {
      final c = parseGiftCatalog(config);
      final now = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
      final active = c.activeAt(now).map((g) => g.id).toList();
      expect(active, contains(43004));
      expect(active, contains(43010));
      // 43099 的 endTime 是 2ms，早就过期
      expect(active, isNot(contains(43099)));
    });

    test('缺少 gift_cfg 时返回空目录，不抛异常', () {
      expect(parseGiftCatalog('{ gift = { } }').isEmpty, isTrue);
      expect(parseGiftCatalog('').isEmpty, isTrue);
    });
  });

  group('道具名合并', () {
    const items = '''
{
  item_list = {
    { ID = 43004, Name = '棒棒糖', Icon = 'https://example.com/a.png' },
    { ID = 43010, Name = '玫瑰花' },
  },
}''';

    test('拿得到 items 配置时补上名称/图标', () {
      final defs = parseItemDefs(items);
      expect(defs[43004]?.name, '棒棒糖');
      expect(defs[43004]?.icon, 'https://example.com/a.png');
      final merged = mergeGiftNames(parseGiftCatalog(config), defs);
      expect(merged.byId(43004)!.displayName, '棒棒糖');
      expect(merged.byId(43010)!.displayName, '玫瑰花');
      // 没配到的仍回退编号
      expect(merged.byId(43099)!.displayName, '礼物 43099');
    });

    test('空 items 不改变目录', () {
      final c = parseGiftCatalog(config);
      final merged = mergeGiftNames(c, const {});
      expect(merged.items.length, c.items.length);
      expect(merged.byId(43004)!.displayName, '礼物 43004');
    });
  });

  /// 线上真实配置（2026-10-02 抓的 `new_give_gift_config`，`gift_cfg` 共 29 项）。
  ///
  /// 名字就写在每一项里，而 visual-cfg `items` 那份线上是 `{ items = { }}`，
  /// 所以只能从这里读 —— 曾经只读 items，于是面板里全是「礼物 43028」。
  group('礼物名写在 gift_cfg 项里', () {
    const live = '''
{
  gift = {
    gift_cfg = {
      {
        id = 43028,
        num = 1,
        cost_id = 10002,
        cost_num = 25,
        intimacies = 25,
        charm_value = 12,
        if_free = 0,
        if_advert = 0,
        name = '纸鹤',
        select_times = {
          {
            num = 1,
          },
        },
        ctrl = {
          version_min = '1.59.0',
        },
        is_time_limit = false,
        is_act_get = true,
        startTime = 1790042400000,
      },
      {
        id = 43027,
        cost_id = 10002,
        cost_num = 18,
        intimacies = 9,
        name = '棒棒糖',
      },
      {
        id = 43099,
        cost_id = 10002,
        cost_num = 5,
      },
    },
  },
}''';

    test('项自带的 name 被读出来，不再退化成编号', () {
      final c = parseGiftCatalog(live);
      expect(c.items.length, 3);
      expect(c.byId(43028)!.name, '纸鹤');
      expect(c.byId(43028)!.displayName, '纸鹤');
      expect(c.byId(43027)!.displayName, '棒棒糖');
      // 真的没有 name 的项才回退编号
      expect(c.byId(43099)!.displayName, '礼物 43099');
    });

    test('数字/布尔字段照旧解析（线上写的是 false 不是 0）', () {
      final g = parseGiftCatalog(live).byId(43028)!;
      expect(g.costNum, 25);
      expect(g.intimacies, 25);
      expect(g.charmValue, 12);
      expect(g.timeLimited, isFalse);
    });

    test('ctrl 里的 name 不算这份礼物的名字', () {
      final c = parseGiftCatalog('''
{
  gift = {
    gift_cfg = {
      {
        id = 43028,
        cost_id = 10002,
        cost_num = 25,
        ctrl = {
          name = 'ctrl里的不是礼物名',
        },
      },
    },
  },
}''');
      expect(c.byId(43028)!.name, isNull);
      expect(c.byId(43028)!.displayName, '礼物 43028');
    });

    test('items 为空时靠项内名字也能拼出完整目录', () {
      // 线上真实情况：items 是 `{ items = { }}`，merge 拿到空表。
      final merged = mergeGiftNames(parseGiftCatalog(live), const {});
      expect(merged.byId(43028)!.displayName, '纸鹤');
      expect(merged.byId(43027)!.displayName, '棒棒糖');
    });
  });
}
