import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/dynamics.dart';

/// dynamics.dart [DynamicsLottery] 的解析单元测试。
///
/// [DynamicsLottery.fromItem] / [DynamicsLottery.parseList] 的宽松解析契约：
/// 数组 / `{lottery_id:{...}}` 映射 / `{list:[...]}` 三种载荷均可解析；
/// 无 lottery_id 的条目被跳过；脏输入 → 空列表；绝不抛异常。
void main() {
  group('DynamicsLottery.fromItem', () {
    test('完整真实条目：字段与 is_author 语义', () {
      final l = DynamicsLottery.fromItem(const {
        'lottery_id': 'L20261006',
        'item_id': 1001,
        'item_num': 3,
        'item_type': 2,
        'select_num': 5,
        'cost_num': 10,
        'lottery_time': 1787800000,
        'task': '1,2,3',
        'status': 2,
        'join_count': 88,
        'uin': 273640665,
        'is_author': true,
      });
      expect(l, isNotNull);
      final lot = l!;
      expect(lot.lotteryId, 'L20261006');
      expect(lot.itemId, 1001);
      expect(lot.itemNum, 3);
      expect(lot.itemType, 2);
      expect(lot.selectNum, 5);
      expect(lot.costNum, 10);
      expect(lot.lotteryTime, 1787800000);
      expect(lot.task, '1,2,3');
      expect(lot.status, 2);
      expect(lot.joinCount, 88);
      expect(lot.uin, 273640665);
      expect(lot.isAuthor, isTrue);
      expect(lot.displayable, isTrue);
    });

    test('无 lottery_id（空白/字面 null）→ null；id 别名可用', () {
      expect(DynamicsLottery.fromItem(const {'status': 2}), isNull);
      expect(DynamicsLottery.fromItem(const {}), isNull);
      expect(DynamicsLottery.fromItem(const {'lottery_id': '  '}), isNull);
      expect(DynamicsLottery.fromItem(const {'lottery_id': 'null'}), isNull);
      expect(DynamicsLottery.fromItem(const {'id': 42})?.lotteryId, '42');
    });

    test('displayable 仅 status 2/3 为真', () {
      DynamicsLottery lot(int status) =>
          DynamicsLottery.fromItem({'lottery_id': 'L', 'status': status})!;
      expect(lot(0).displayable, isFalse);
      expect(lot(1).displayable, isFalse);
      expect(lot(2).displayable, isTrue);
      expect(lot(3).displayable, isTrue);
      expect(lot(4).displayable, isFalse);
    });

    test('is_author 宽松布尔：true / 1 / "1" 为真，其余为假', () {
      bool author(Object? v) =>
          DynamicsLottery.fromItem({'lottery_id': 'L', 'is_author': v})!
              .isAuthor;
      expect(author(true), isTrue);
      expect(author(1), isTrue);
      expect(author('1'), isTrue);
      expect(author(false), isFalse);
      expect(author(0), isFalse);
      expect(author('0'), isFalse);
      expect(author(null), isFalse);
    });

    test('数值字符串被 _pickInt 接受；缺省字段 → 0', () {
      final l = DynamicsLottery.fromItem(const {
        'lottery_id': 'L',
        'status': '3',
        'join_num': '9', // join_count 别名
        'author_uin': '777', // uin 别名
      })!;
      expect(l.status, 3);
      expect(l.joinCount, 9);
      expect(l.uin, 777);
      expect(l.itemId, 0);
      expect(l.costNum, 0);
      expect(l.task, '');
    });
  });

  group('DynamicsLottery.parseList', () {
    test('数组形态：逐条解析，无 lottery_id 的条目跳过', () {
      final list = DynamicsLottery.parseList(const [
        {'lottery_id': 'L1', 'status': 2},
        {'status': 3}, // 无 id → 跳过
        {'lottery_id': 'L2', 'join_count': 5},
      ]);
      expect(list.length, 2);
      expect(list[0].lotteryId, 'L1');
      expect(list[1].lotteryId, 'L2');
      expect(list[1].joinCount, 5);
    });

    test('{list:[...]} 形态', () {
      final list = DynamicsLottery.parseList(const {
        'list': [
          {'lottery_id': 'L1', 'status': 2},
        ],
      });
      expect(list.length, 1);
      expect(list.single.lotteryId, 'L1');
    });

    test('{lottery_id:{...}} 映射形态：取每条 value', () {
      final list = DynamicsLottery.parseList(const {
        'L1': {'lottery_id': 'L1', 'status': 2},
        'L2': {'lottery_id': 'L2', 'status': 3},
      });
      expect(list.length, 2);
      expect(list.map((e) => e.lotteryId).toList(), ['L1', 'L2']);
      expect(list.every((e) => e.displayable), isTrue);
    });

    test('脏输入 → 空列表，绝不抛', () {
      expect(DynamicsLottery.parseList(null), isEmpty);
      expect(DynamicsLottery.parseList('junk'), isEmpty);
      expect(DynamicsLottery.parseList(42), isEmpty);
      expect(DynamicsLottery.parseList(const <Object?>[]), isEmpty);
      expect(DynamicsLottery.parseList(const {'list': 'x'}), isEmpty);
      expect(
        DynamicsLottery.parseList(const {
          'list': <Object?>['raw', 5, <String, Object?>{}],
        }),
        isEmpty,
      );
      expect(
        DynamicsLottery.parseList(const {'a': 'not-a-map'}),
        isEmpty,
      );
    });
  });
}
