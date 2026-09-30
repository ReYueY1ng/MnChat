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
}
