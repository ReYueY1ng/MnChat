import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/player_home.dart';

/// `get_top_flag_list` 置顶列表解析 + `SetTopFlagResult` 单测。
void main() {
  group('PlayerHomeClient.parseTopFlagList 置顶列表解析', () {
    test('正常响应：解析 top_id，只统计 time>0', () {
      final ids = PlayerHomeClient.parseTopFlagList({
        'code': 0,
        'data': {
          'module_id': 7,
          'top_list': [
            {'top_id': '20201', 'time': 1700000000},
            {'top_id': 33290, 'time': 1700000100},
          ],
        },
      });
      expect(ids, {20201, 33290});
    });

    test('非零 code / ret 返回空集合', () {
      expect(
        PlayerHomeClient.parseTopFlagList({
          'code': 1,
          'data': {
            'top_list': [
              {'top_id': 1, 'time': 1},
            ],
          },
        }),
        isEmpty,
      );
      expect(PlayerHomeClient.parseTopFlagList({'ret': 5}), isEmpty);
    });

    test('缺字段 / 类型错误返回空集合', () {
      expect(PlayerHomeClient.parseTopFlagList(null), isEmpty);
      expect(PlayerHomeClient.parseTopFlagList('x'), isEmpty);
      expect(PlayerHomeClient.parseTopFlagList(123), isEmpty);
      expect(PlayerHomeClient.parseTopFlagList(<String, Object?>{}), isEmpty);
      // 缺 data / data 非 Map / 缺 top_list / top_list 非 List。
      expect(PlayerHomeClient.parseTopFlagList({'code': 0}), isEmpty);
      expect(
        PlayerHomeClient.parseTopFlagList({'code': 0, 'data': 'x'}),
        isEmpty,
      );
      expect(
        PlayerHomeClient.parseTopFlagList({
          'code': 0,
          'data': <String, Object?>{},
        }),
        isEmpty,
      );
      expect(
        PlayerHomeClient.parseTopFlagList({
          'code': 0,
          'data': {'top_list': 'x'},
        }),
        isEmpty,
      );
    });

    test('条目脏数据只跳过，不抛异常', () {
      final ids = PlayerHomeClient.parseTopFlagList({
        'code': 0,
        'data': {
          'top_list': [
            'x',
            42,
            null,
            {'top_id': 0, 'time': 1},
            {'top_id': 'abc', 'time': 1},
            {'time': 1},
            {'top_id': 7, 'time': 0}, // time=0 → 已取消，跳过
            {'top_id': 8}, // 缺 time → 跳过
            {'top_id': 9, 'time': 1}, // 有效
          ],
        },
      });
      expect(ids, {9});
    });

    test('top_id / time 为数字字符串时正常解析', () {
      final ids = PlayerHomeClient.parseTopFlagList({
        'data': {
          'top_list': [
            {'top_id': '123', 'time': '1700000000'},
          ],
        },
      });
      expect(ids, {123});
    });
  });

  group('SetTopFlagResult', () {
    test('成功 / 失败携带服务端文案', () {
      expect(const SetTopFlagResult(ok: true).ok, isTrue);
      const fail = SetTopFlagResult(ok: false, message: '置顶数量已达上限');
      expect(fail.ok, isFalse);
      expect(fail.message, '置顶数量已达上限');
    });
  });
}
