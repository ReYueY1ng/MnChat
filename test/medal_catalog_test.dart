import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/medal_catalog.dart';

void main() {
  group('medal_catalog', () {
    test('勋章目录非空且图标文件随包存在', () {
      expect(kMedalIconName, isNotEmpty);
      for (final e in kMedalIconName.entries) {
        expect(e.key, greaterThan(0));
        expect(
          File('assets/medals/${e.value}.png').existsSync(),
          isTrue,
          reason: '缺少勋章图标 ${e.value}.png',
        );
      }
    });

    test('等级边框 1..5 且文件存在', () {
      expect(kMedalFrameByLevel.length, 5);
      for (final f in kMedalFrameByLevel) {
        expect(File('assets/medals/$f.png').existsSync(), isTrue, reason: f);
      }
    });

    test('medalIconAsset 生成正确路径', () {
      expect(
        medalIconAsset('cj_bosskiller'),
        'assets/medals/cj_bosskiller.png',
      );
    });

    test('isNew 勋章的等级徽章文件存在', () {
      expect(kMedalLevelIcons, isNotEmpty);
      for (final e in kMedalLevelIcons.entries) {
        expect(e.value.length, 5, reason: '勋章 ${e.key} 应有 5 个等级图标');
        for (final n in e.value) {
          expect(File('assets/medals/$n.png').existsSync(), isTrue, reason: n);
        }
      }
    });
  });
}
