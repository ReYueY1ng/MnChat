import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/player_home.dart';

void main() {
  group('PlayerHomeClient.parseVisitorList 访客列表解析', () {
    test('正常列表按原顺序解析 uin / time', () {
      final list = PlayerHomeClient.parseVisitorList({
        'list': [
          {'uin': 1001, 'time': 1700000000},
          {'uin': 1002, 'time': 1700000100},
        ],
      });

      expect(list.length, 2);
      expect(list[0].uin, 1001);
      expect(list[0].time, 1700000000);
      expect(list[1].uin, 1002);
      expect(list[1].time, 1700000100);
    });

    test('null / String / int / 无 list 的 Map 均返回空列表', () {
      expect(PlayerHomeClient.parseVisitorList(null), isEmpty);
      expect(PlayerHomeClient.parseVisitorList('oops'), isEmpty);
      expect(PlayerHomeClient.parseVisitorList(123), isEmpty);
      expect(PlayerHomeClient.parseVisitorList(<String, Object?>{}), isEmpty);
      // list 存在但不是 List
      expect(
        PlayerHomeClient.parseVisitorList({'list': 'not-a-list'}),
        isEmpty,
      );
    });

    test('非 Map 条目被跳过（String / int / null）', () {
      final list = PlayerHomeClient.parseVisitorList({
        'list': [
          'x',
          42,
          null,
          {'uin': 7, 'time': 1},
        ],
      });

      expect(list.length, 1);
      expect(list.single.uin, 7);
      expect(list.single.time, 1);
    });

    test('uin 缺失 / 0 / 非数字的条目被跳过', () {
      final list = PlayerHomeClient.parseVisitorList({
        'list': [
          {'time': 1},
          {'uin': 0, 'time': 1},
          {'uin': 'abc', 'time': 1},
          {'uin': null, 'time': 1},
          {'uin': 9, 'time': 1},
        ],
      });

      expect(list.length, 1);
      expect(list.single.uin, 9);
    });

    test('time 缺失 / 非法时默认 0', () {
      final list = PlayerHomeClient.parseVisitorList({
        'list': [
          {'uin': 1},
          {'uin': 2, 'time': 'bad'},
          {'uin': 3, 'time': null},
        ],
      });

      expect(list.length, 3);
      expect(list.map((e) => e.time), everyElement(0));
    });

    test('uin / time 为数字字符串时正常解析', () {
      final list = PlayerHomeClient.parseVisitorList({
        'list': [
          {'uin': '123', 'time': '1700000000'},
        ],
      });

      expect(list.single.uin, 123);
      expect(list.single.time, 1700000000);
    });
  });
}
