import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/partner.dart';

/// 最佳拍档 / 等级 / 大会员解析器单测。
///
/// 每个解析器覆盖：有效数据、缺字段、类型错误、空、非 0 code/ret。
/// 契约：脏数据只跳过、绝不抛异常；失败返回空值。
void main() {
  group('PartnerInfo.fromItem', () {
    test('完整字段解析', () {
      final p = PartnerInfo.fromItem(const {
        'bestUin': 10001,
        'lab': 7,
        'tacitnum': 345,
        'createtime': 1700000000,
        'title_id': 3,
        'applyuin': 10002,
        'applylab': 1,
        'applytime': 1699999999,
        'apply_remove': 1,
        'labchgtime': 1700000100,
        'daytacittotal': 10,
        'giftdaytacittotal': 2,
      });
      expect(p, isNotNull);
      expect(p!.bestUin, 10001);
      expect(p.lab, 7);
      expect(p.labName, '最佳拍档');
      expect(p.tacitnum, 345);
      expect(p.createtime, 1700000000);
      expect(p.titleId, 3);
      expect(p.applyUin, 10002);
      expect(p.applyLab, 1);
      expect(p.applyTime, 1699999999);
      expect(p.applyRemove, 1);
      expect(p.labChgTime, 1700000100);
      expect(p.dayTacitTotal, 10);
      expect(p.giftDayTacitTotal, 2);
    });

    test('缺 bestUin / 非 Map → null', () {
      expect(PartnerInfo.fromItem(const {'lab': 1}), isNull);
      expect(PartnerInfo.fromItem(const {'bestUin': 0}), isNull);
      expect(PartnerInfo.fromItem('nope'), isNull);
      expect(PartnerInfo.fromItem(null), isNull);
      expect(PartnerInfo.fromItem(const [1, 2]), isNull);
    });

    test('字段类型错误 → 数字强转 0，不抛异常', () {
      final p = PartnerInfo.fromItem(const {
        'bestUin': '10001',
        'lab': 'bad',
        'tacitnum': null,
      });
      expect(p, isNotNull);
      expect(p!.bestUin, 10001);
      expect(p.lab, 0);
      expect(p.tacitnum, 0);
    });
  });

  group('PartnerInfo.parseList', () {
    test('跳过脏条目，保留有效项', () {
      final list = PartnerInfo.parseList(const [
        {'bestUin': 1, 'lab': 1},
        'bad',
        {'lab': 2},
        {'bestUin': 2, 'tacitnum': '88'},
      ]);
      expect(list.length, 2);
      expect(list[0].bestUin, 1);
      expect(list[1].bestUin, 2);
      expect(list[1].tacitnum, 88);
    });

    test('空 / 非 List → 空列表', () {
      expect(PartnerInfo.parseList(const []), isEmpty);
      expect(PartnerInfo.parseList(null), isEmpty);
      expect(PartnerInfo.parseList(const {'a': 1}), isEmpty);
    });
  });

  group('PartnerInfo.daysSince', () {
    test('ceil 且最小 1', () {
      const now = 1700086400;
      expect(PartnerInfo.daysSince(now, now), 1);
      expect(PartnerInfo.daysSince(now - 86400, now), 1);
      expect(PartnerInfo.daysSince(now - 86401, now), 2);
      expect(PartnerInfo.daysSince(now - 86400 * 3, now), 3);
    });

    test('createtime 缺失 / 非正 → 0', () {
      expect(PartnerInfo.daysSince(0, 1700086400), 0);
      expect(PartnerInfo.daysSince(-5, 1700086400), 0);
      expect(PartnerInfo.daysSince(1700086400, 0), 0);
    });
  });

  group('PartnerLab', () {
    test('固定映射与未知回退', () {
      expect(PartnerLab.name(1), '挚友');
      expect(PartnerLab.name(2), '知己');
      expect(PartnerLab.name(3), '姐妹');
      expect(PartnerLab.name(4), '兄弟');
      expect(PartnerLab.name(5), '闺蜜');
      expect(PartnerLab.name(6), '兄妹');
      expect(PartnerLab.name(7), '最佳拍档');
      expect(PartnerLab.name(100), '最佳拍档');
      expect(PartnerLab.name(999), '拍档');
    });
  });

  group('PartnerSlotInfo.parse', () {
    test('有效 → total = normal + special', () {
      final s = PartnerSlotInfo.parse(const {
        'unlock_normal': 2,
        'unlock_special': 1,
      });
      expect(s, isNotNull);
      expect(s!.unlockNormal, 2);
      expect(s.unlockSpecial, 1);
      expect(s.total, 3);
    });

    test('缺字段 → 0', () {
      final s = PartnerSlotInfo.parse(const <String, Object?>{});
      expect(s, isNotNull);
      expect(s!.total, 0);
    });

    test('非 Map → null', () {
      expect(PartnerSlotInfo.parse('x'), isNull);
      expect(PartnerSlotInfo.parse(null), isNull);
    });
  });

  group('RelationProgress', () {
    test('next 未知（配置缺失）→ ratio null', () {
      expect(const RelationProgress(current: 10).ratio, isNull);
      expect(const RelationProgress(current: 10, next: 0).ratio, isNull);
    });

    test('next 已知 → 计算并钳制到 [0,1]', () {
      expect(const RelationProgress(current: 10, next: 20).ratio, 0.5);
      expect(const RelationProgress(current: 30, next: 20).ratio, 1.0);
    });
  });

  group('PartnerDirectory', () {
    test('levelOf / partnerOf / isVip', () {
      const dir = PartnerDirectory(
        levels: {1: 5},
        partners: {1: PartnerInfo(bestUin: 1, tacitnum: 9)},
        vipExpiry: {1: 2000, 2: 500},
      );
      expect(dir.levelOf(1), 5);
      expect(dir.levelOf(9), 0);
      expect(dir.partnerOf(1)!.tacitnum, 9);
      expect(dir.partnerOf(9), isNull);
      expect(dir.isVip(1, now: 1000), isTrue);
      expect(dir.isVip(1, now: 2000), isFalse);
      expect(dir.isVip(2, now: 1000), isFalse);
      expect(dir.isVip(3, now: 1), isFalse);
    });

    test('empty 无任何数据', () {
      expect(PartnerDirectory.empty.levelOf(1), 0);
      expect(PartnerDirectory.empty.partnerOf(1), isNull);
      expect(PartnerDirectory.empty.isVip(1, now: 1), isFalse);
    });
  });

  group('PartnerClient.parseLevelBatchResponse', () {
    test('有效列表（含数字字符串）', () {
      final m = PartnerClient.parseLevelBatchResponse(const {
        'ret': 0,
        'data': [
          {'uin': 1, 'level': 5},
          {'uin': '2', 'level': '3'},
        ],
      });
      expect(m, {1: 5, 2: 3});
    });

    test('ret 非 0 → 空', () {
      expect(
        PartnerClient.parseLevelBatchResponse(const {
          'ret': 1,
          'data': [
            {'uin': 1, 'level': 5},
          ],
        }),
        isEmpty,
      );
    });

    test('code 非 0 → 空', () {
      expect(
        PartnerClient.parseLevelBatchResponse(const {
          'code': 2,
          'data': [
            {'uin': 1, 'level': 5},
          ],
        }),
        isEmpty,
      );
    });

    test('data 缺失 / 非 List → 空', () {
      expect(PartnerClient.parseLevelBatchResponse(const {'ret': 0}), isEmpty);
      expect(
        PartnerClient.parseLevelBatchResponse(const {'ret': 0, 'data': 'x'}),
        isEmpty,
      );
      expect(PartnerClient.parseLevelBatchResponse(null), isEmpty);
    });

    test('脏条目 / uin 非正跳过', () {
      final m = PartnerClient.parseLevelBatchResponse(const {
        'ret': 0,
        'data': [
          'bad',
          {'uin': 0, 'level': 9},
          {'uin': 3},
          {'uin': 4, 'level': 2},
        ],
      });
      expect(m, {3: 0, 4: 2});
    });
  });

  group('PartnerClient.parsePartnerListResponse', () {
    test('有效列表', () {
      final list = PartnerClient.parsePartnerListResponse(const {
        'code': 0,
        'data': [
          {'bestUin': 1, 'lab': 7, 'tacitnum': 12},
        ],
      });
      expect(list.length, 1);
      expect(list.first.bestUin, 1);
      expect(list.first.tacitnum, 12);
    });

    test('非 0 code → 空', () {
      expect(
        PartnerClient.parsePartnerListResponse(const {
          'code': 1,
          'data': [
            {'bestUin': 1},
          ],
        }),
        isEmpty,
      );
    });

    test('data 非 List → 空', () {
      expect(
        PartnerClient.parsePartnerListResponse(const {
          'code': 0,
          'data': {'bestUin': 1},
        }),
        isEmpty,
      );
      expect(PartnerClient.parsePartnerListResponse(null), isEmpty);
    });
  });

  group('PartnerClient.parsePartnerSlotResponse', () {
    test('有效', () {
      final s = PartnerClient.parsePartnerSlotResponse(const {
        'code': 0,
        'data': {'unlock_normal': 3, 'unlock_special': 2},
      });
      expect(s, isNotNull);
      expect(s!.total, 5);
    });

    test('非 0 code → null', () {
      expect(
        PartnerClient.parsePartnerSlotResponse(const {
          'code': 9,
          'data': {'unlock_normal': 3},
        }),
        isNull,
      );
    });

    test('data 非 Map / 整体非 Map → null', () {
      expect(
        PartnerClient.parsePartnerSlotResponse(const {'code': 0, 'data': 1}),
        isNull,
      );
      expect(PartnerClient.parsePartnerSlotResponse('x'), isNull);
    });
  });

  group('PartnerClient.parseRedDotResponse', () {
    test('有效 count', () {
      expect(
        PartnerClient.parseRedDotResponse(const {
          'code': 0,
          'data': {'count': 4},
        }),
        4,
      );
    });

    test('非 0 / 缺 count / 非 Map → 0', () {
      expect(
        PartnerClient.parseRedDotResponse(const {
          'code': 1,
          'data': {'count': 4},
        }),
        0,
      );
      expect(
        PartnerClient.parseRedDotResponse(const {'code': 0, 'data': {}}),
        0,
      );
      expect(PartnerClient.parseRedDotResponse(null), 0);
    });
  });

  group('PartnerClient.parseSelfVipResponse', () {
    test('有效 repiredtime', () {
      expect(
        PartnerClient.parseSelfVipResponse(const {
          'code': 0,
          'data': [
            {'repiredtime': 1900000000},
          ],
        }),
        1900000000,
      );
    });

    test('空 data / 非 0 / 到期时间非正 → null', () {
      expect(
        PartnerClient.parseSelfVipResponse(const {'code': 0, 'data': []}),
        isNull,
      );
      expect(
        PartnerClient.parseSelfVipResponse(const {
          'code': 1,
          'data': [
            {'repiredtime': 1900000000},
          ],
        }),
        isNull,
      );
      expect(
        PartnerClient.parseSelfVipResponse(const {
          'code': 0,
          'data': [
            {'repiredtime': 0},
          ],
        }),
        isNull,
      );
    });
  });

  group('PartnerClient.parseVipUinListResponse', () {
    test('有效 map（含数字字符串）', () {
      final m = PartnerClient.parseVipUinListResponse(const {
        'code': 0,
        'tvip_info': {'1': 100, '2': '200'},
      });
      expect(m, {1: 100, 2: 200});
    });

    test('缺 tvip_info / 非 Map → 空', () {
      expect(
        PartnerClient.parseVipUinListResponse(const {'code': 0}),
        isEmpty,
      );
      expect(PartnerClient.parseVipUinListResponse(null), isEmpty);
      expect(
        PartnerClient.parseVipUinListResponse(const {'tvip_info': 1}),
        isEmpty,
      );
    });

    test('非正到期时间跳过', () {
      final m = PartnerClient.parseVipUinListResponse(const {
        'tvip_info': {'1': 0, '2': 300},
      });
      expect(m, {2: 300});
    });
  });

  group('parsePartnerLevels', () {
    test('整表：沿 FriendSystem.levelIntimacy.partnerLevel_list 取值并按 level 升序', () {
      final levels = parsePartnerLevels(const {
        'FriendSystem': {
          'levelIntimacy': {
            'partnerLevel_list': [
              {'level': 5, 'intimacyValue': 10000},
              {'level': 1, 'intimacyValue': 100},
              {'level': 3, 'intimacyValue': 2000},
              {'level': 2, 'intimacyValue': 600},
              {'level': 4, 'intimacyValue': 5000},
            ],
          },
        },
      });
      expect(levels, [
        (1, 100),
        (2, 600),
        (3, 2000),
        (4, 5000),
        (5, 10000),
      ]);
    });

    test('可直接传入 partnerLevel_list 列表', () {
      final levels = parsePartnerLevels(const [
        {'level': 2, 'intimacyValue': 600},
        {'level': 1, 'intimacyValue': 100},
      ]);
      expect(levels, [(1, 100), (2, 600)]);
    });

    test('数字字符串强转；脏条目跳过', () {
      final levels = parsePartnerLevels(const {
        'FriendSystem': {
          'levelIntimacy': {
            'partnerLevel_list': [
              'bad',
              {'level': 0, 'intimacyValue': 5},
              {'level': 1, 'intimacyValue': 0},
              {'level': '2', 'intimacyValue': '600'},
            ],
          },
        },
      });
      expect(levels, [(2, 600)]);
    });

    test('同 level 去重（保留首个）', () {
      final levels = parsePartnerLevels(const [
        {'level': 1, 'intimacyValue': 100},
        {'level': 1, 'intimacyValue': 999},
      ]);
      expect(levels, [(1, 100)]);
    });

    test('路径缺失 / null / 非 0 code → 空', () {
      expect(parsePartnerLevels(null), isEmpty);
      expect(parsePartnerLevels(const {'FriendSystem': {}}), isEmpty);
      expect(
        parsePartnerLevels(const {
          'code': 1,
          'FriendSystem': {
            'levelIntimacy': {
              'partnerLevel_list': [
                {'level': 1, 'intimacyValue': 100},
              ],
            },
          },
        }),
        isEmpty,
      );
    });
  });

  group('partnerLevelFor', () {
    const cfg = <(int, int)>[
      (1, 100),
      (2, 600),
      (3, 2000),
      (4, 5000),
      (5, 10000),
    ];

    test('低于首级 → 1 级、首级门槛', () {
      expect(partnerLevelFor(50, cfg), (1, 100));
    });

    test('区间内 → 当前级 + 下一级门槛', () {
      expect(partnerLevelFor(300, cfg), (1, 600));
      expect(partnerLevelFor(600, cfg), (2, 2000));
      expect(partnerLevelFor(999, cfg), (2, 2000));
      expect(partnerLevelFor(2500, cfg), (3, 5000));
    });

    test('恰好等于门槛 → 抬升到该级', () {
      expect(partnerLevelFor(100, cfg), (1, 600));
      expect(partnerLevelFor(10000, cfg), (5, 10000));
    });

    test('超过最高级 → 末级 + 末级门槛', () {
      expect(partnerLevelFor(999999, cfg), (5, 10000));
    });

    test('空阈值 → (1, 0)', () {
      expect(partnerLevelFor(123, const <(int, int)>[]), (1, 0));
    });
  });
}
