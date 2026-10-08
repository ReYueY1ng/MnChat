/// `parseFamilyIdList`（`act=query_user_family_id_list` 的「已加入家族 id 列表」）
/// 解析口径回归：多种信封都认，脏数据跳过、绝不抛。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/family.dart';

void main() {
  test('数组形态：数字 id', () {
    expect(parseFamilyIdList({'data': [1, 2, 3]}), [1, 2, 3]);
  });

  test('数组形态：对象条目取 family_id', () {
    expect(
      parseFamilyIdList({
        'data': [
          {'family_id': 11},
          {'familyId': 12},
          {'id': 13},
        ],
      }),
      [11, 12, 13],
    );
  });

  test('映射形态：{"12": {...}} 用键', () {
    expect(
      parseFamilyIdList({
        'data': {
          '12': {'name': '家族A'},
          '15': {'name': '家族B'},
        },
      }),
      [12, 15],
    );
  });

  test('顶层 id_list / family_id_list / list 兜底', () {
    expect(parseFamilyIdList({'id_list': [7]}), [7]);
    expect(parseFamilyIdList({'family_id_list': [8]}), [8]);
    expect(parseFamilyIdList({'list': [9]}), [9]);
  });

  test('去重且跳过脏数据：0 / 空串 / null 载荷', () {
    expect(parseFamilyIdList({}), isEmpty);
    expect(parseFamilyIdList({'data': [0, 5, 5, '6', '']}), [5, 6]);
    expect(parseFamilyIdList({'data': <Object>[]}), isEmpty);
  });
}
