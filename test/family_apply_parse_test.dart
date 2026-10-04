// 家族接口的类型化边界：`getFamilyDetail` 现在返回 FamilyDetail（家族信息 +
// 入族申请），`getFamilyList` 返回 List<FamilyInfo>。
//
// 这里锁的是**解析口径**（信封兼容、脏数据跳过、昵称洗富文本标记），
// 与服务端真实字段对齐：apply_list / NickName / uin / Uin。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/family.dart';

void main() {
  group('FamilyApply.fromJson', () {
    test('解析 uin 与昵称（NickName 小写、Uin 大写都认）', () {
      final a = FamilyApply.fromJson({'uin': 123, 'NickName': '顾念'})!;
      expect(a.uin, 123);
      expect(a.nickname, '顾念');

      final b = FamilyApply.fromJson({'Uin': '456', 'NickName': '张三'})!;
      expect(b.uin, 456);
      expect(b.nickname, '张三');
    });

    test('昵称的富文本标记在解析时就洗掉（页面不该再洗一遍）', () {
      final a = FamilyApply.fromJson({
        'uin': 1,
        'NickName': '[i][color][b]顾念',
      })!;
      expect(a.nickname, '顾念');
    });

    test('昵称缺失 / 洗成空 → 回退迷你号', () {
      expect(FamilyApply.fromJson({'uin': 7})!.nickname, '7');
      expect(FamilyApply.fromJson({'uin': 7, 'NickName': '[b]'})!.nickname, '7');
    });

    test('脏数据（没有有效 uin）→ null，不抛异常', () {
      expect(FamilyApply.fromJson(const {}), isNull);
      expect(FamilyApply.fromJson(const {'uin': 0}), isNull);
      expect(FamilyApply.fromJson(const {'uin': null, 'NickName': 'x'}), isNull);
      expect(FamilyApply.fromJson(const {'uin': 'abc'}), isNull);
    });
  });

  group('parseFamilyList 的信封兼容', () {
    test('顶层即家族 / {family} / {families} / {data} 四种都能解', () {
      final one = {'family_id': 9, 'family_name': '测试家族'};
      expect(parseFamilyList(one).single.familyId, 9);
      expect(parseFamilyList({'family': one}).single.familyId, 9);
      expect(parseFamilyList({
        'families': [one],
      }).single.familyId, 9);
      expect(parseFamilyList({'data': one}).single.familyId, 9);
    });

    test('重复 family_id 去重，脏节点跳过', () {
      final list = parseFamilyList({
        'families': [
          {'family_id': 9, 'family_name': 'A'},
          {'family_id': 9, 'family_name': 'A2'},
          {'family_name': '无 id'},
          'not a map',
        ],
      });
      expect(list.length, 1);
      expect(list.single.familyId, 9);
    });
  });
}
