import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/family.dart';

/// `get_family_list` 响应解析（[parseFamilyList]）单元测试。
///
/// 覆盖：四种信封（顶层 / `family` / `families` / `data`）、脏数据跳过、
/// 同族去重。解析器不得抛异常，取不到时返回空列表。
void main() {
  group('parseFamilyList', () {
    test('顶层即家族对象', () {
      final list = parseFamilyList({'family_id': 12, 'family_name': 'MoonX'});
      expect(list, hasLength(1));
      expect(list.single.familyId, 12);
      expect(list.single.name, 'MoonX');
    });

    test('兼容 family / families / data 三种信封', () {
      expect(
        parseFamilyList({
          'family': {'family_id': 1, 'name': 'A'},
        }).single.name,
        'A',
      );
      expect(
        parseFamilyList({
          'families': [
            {'family_id': 1, 'name': 'A'},
            {'family_id': 2, 'name': 'B'},
          ],
        }).map((f) => f.name),
        ['A', 'B'],
      );
      expect(
        parseFamilyList({
          'data': [
            {'family_id': 3, 'name': 'C'},
          ],
        }).single.familyId,
        3,
      );
      expect(
        parseFamilyList({
          'data': {'family_id': 4, 'name': 'D'},
        }).single.name,
        'D',
      );
    });

    test('脏数据跳过：非 Map / 缺 family_id / id 为 0', () {
      expect(parseFamilyList({}), isEmpty);
      expect(parseFamilyList({'families': 'oops'}), isEmpty);
      expect(
        parseFamilyList({
          'families': [
            1,
            null,
            {'name': '无 id'},
            {'family_id': 0, 'name': 'zero'},
          ],
        }),
        isEmpty,
      );
    });

    test('同一 family_id 只保留首个', () {
      final list = parseFamilyList({
        'families': [
          {'family_id': 5, 'name': 'A'},
          {'family_id': 5, 'name': 'B'},
        ],
      });
      expect(list, hasLength(1));
      expect(list.single.name, 'A');
    });
  });
}
