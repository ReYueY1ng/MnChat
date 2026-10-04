import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/account_inventory.dart';

/// 账号道具背包解析：对齐 `clientex/account.lua` 的 `ItemInfo` getter
/// （`BillDataSvr.ItemInfo` + `leveldb.ItemInfoNew` + `leveldb.ItemInfo`）。
///
/// 响应里的两种形状都来自 2026-10-04 的游戏抓包（`tool/mitm`）。
void main() {
  group('AccountInventory.fromUpdateResponse', () {
    test('线上形状：BillDataSvr.ItemInfo 是 [id,num] 对列表', () {
      final resp = [
        1,
        'baseinfo',
        'update',
        1796406401,
        5116137,
        [
          0,
          [
            307905116,
            [3386, 2189, 1, 1, 1, 20738],
            {
              'Chest': {'Uin': 279630451},
              'Account': {
                'BillDataSvr': {
                  'MiniBean': 0,
                  'ItemInfo': [
                    [43000, 18],
                    [12833, 56],
                    [845, 32],
                  ],
                  'ItemInfoNum': 3,
                },
              },
            },
            {
              'Uin': 279630451,
              'ItemInfoNew': [
                {'ItemID': 20006, 'Num': 6},
                {'ItemID': 43000, 'Num': 1},
              ],
              'ItemInfo': <Object?>[],
            },
          ],
        ],
      ];
      final inv = AccountInventory.fromUpdateResponse(resp);
      expect(inv.countOf(43000), 19, reason: '两个 store 的数量要相加（同 item_num）');
      expect(inv.countOf(12833), 56);
      expect(inv.countOf(20006), 6);
      expect(inv.countOf(99999), 0);
      expect(inv.isEmpty, isFalse);
    });

    test('code != 0（漏发前置参数时的 4001）当空背包，不把错误载荷读成库存', () {
      final resp = [
        1,
        'baseinfo',
        'update',
        1,
        2,
        [
          4001,
          [
            307904751,
            [3386, 2189, 1, 1, 1, 20738],
            {
              'Account': {
                'BillDataSvr': {
                  'ItemInfo': [
                    [43000, 18],
                  ],
                },
              },
            },
          ],
        ],
      ];
      expect(AccountInventory.fromUpdateResponse(resp).isEmpty, isTrue);
    });

    test('同一个 store 出现两次不翻倍（按列表身份去重）', () {
      final store = <Object?>[
        [43000, 18],
      ];
      final resp = [
        1,
        'baseinfo',
        'update',
        1,
        2,
        [
          0,
          [
            {
              'Account': {
                'BillDataSvr': {'ItemInfo': store},
              },
            },
            {'ItemInfoNew': store},
          ],
        ],
      ];
      expect(AccountInventory.fromUpdateResponse(resp).countOf(43000), 18);
    });

    test('脏数据跳过，绝不抛：缺字段 / 类型不对 / 非正数', () {
      final resp = [
        1,
        'baseinfo',
        'update',
        1,
        2,
        [
          0,
          [
            {
              'Account': {
                'BillDataSvr': {
                  'ItemInfo': [
                    'dirty',
                    <Object?>[],
                    [0, 5],
                    [43000, 0],
                    <Object?>[43001],
                    [43002, -3],
                    {'ItemID': '43003', 'Num': '7'},
                    {'Num': 4},
                    {'ItemID': 43004, 'Num': null},
                  ],
                },
              },
            },
          ],
        ],
      ];
      final inv = AccountInventory.fromUpdateResponse(resp);
      expect(inv.counts, {43003: 7});
    });

    test('结构不对（null / 非列表 / 太短）→ 空背包', () {
      expect(AccountInventory.fromUpdateResponse(null).isEmpty, isTrue);
      expect(AccountInventory.fromUpdateResponse('nope').isEmpty, isTrue);
      expect(AccountInventory.fromUpdateResponse(<Object?>[1, 2]).isEmpty, isTrue);
      expect(
        AccountInventory.fromUpdateResponse(<Object?>[1, 'baseinfo', 'update', 1, 2])
            .isEmpty,
        isTrue,
      );
    });
  });
}
