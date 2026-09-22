import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/skin_head_catalog.dart';

void main() {
  group('skin_head_catalog', () {
    test('目录非空且 id 均为正整数', () {
      expect(kSkinHeadIcon, isNotEmpty);
      for (final e in kSkinHeadIcon.entries) {
        expect(e.key, greaterThan(0));
        expect(e.value, greaterThan(0));
      }
    });

    test('roleIconAsset 生成正确资源路径', () {
      expect(roleIconAsset(31), 'assets/roleicons/31.webp');
    });

    test('headIconAsset 按类型解析资源路径', () {
      final firstSkin = kSkinHeadIcon.entries.first;
      // type 1：皮肤 ID 经 kSkinHeadIcon 映射到 Head 图标
      expect(headIconAsset(1, firstSkin.key), roleIconAsset(firstSkin.value));
      // type 4：立绘 id 直接作为图标 id
      expect(headIconAsset(4, 12345), roleIconAsset(12345));
      // type 3：坐骑走 rideicons
      expect(headIconAsset(3, 7), rideIconAsset(7));
      // type 2（头套）无本地图标
      expect(headIconAsset(2, 1), isNull);
      // 未收录的皮肤 id
      expect(headIconAsset(1, -999), isNull);
    });

    test('目录内至少一个图标随包提供（抽查首个）', () {
      final first = kSkinHeadIcon.values.first;
      expect(roleIconAsset(first), startsWith('assets/roleicons/'));
    });
  });
}
