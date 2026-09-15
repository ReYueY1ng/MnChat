import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/animated_frames.dart' show kAnimatedFrameIds;
import 'package:mnchat/core/models/head_frame_catalog.dart';

/// 头像框目录（由 `csvdef/utf8/itemdef.csv` 生成）回归测试。
void main() {
  group('head_frame_catalog', () {
    test('目录非空，key 均为正整数，名称非空', () {
      expect(kHeadFrameCatalog, isNotEmpty);
      for (final e in kHeadFrameCatalog.entries) {
        expect(e.key, greaterThan(0));
        expect(e.value.name, isNotEmpty, reason: 'id=${e.key} 名称为空');
      }
    });

    test('已知条目逐字对齐 itemdef.csv', () {
      expect(kHeadFrameCatalog[20201]?.name, '单身汪');
      expect(kHeadFrameCatalog[20201]?.getWay, '双十一活动获取');
      expect(kHeadFrameCatalog[33290]?.name, '瓷语青莲');
      expect(kHeadFrameCatalog[33290]?.getWay, '瓷语生花，青莲入梦活动获得');
    });

    test('全部动画头像框 id 均被收录（覆盖率）', () {
      for (final id in kAnimatedFrameIds) {
        expect(
          kHeadFrameCatalog.containsKey(id),
          isTrue,
          reason: '动画框 $id 未收录进目录',
        );
      }
    });

    test('headFrameCaption：默认框 / 已收录 / 未收录回退', () {
      // 默认框 id=1 → GetS(5300)。
      expect(headFrameCaption(1), kDefaultHeadFrameCaption);
      expect(headFrameCaption(1), '默认头像框');
      // 已收录 → `<名称>: <获取途径>`。
      expect(headFrameCaption(33290), '瓷语青莲: 瓷语生花，青莲入梦活动获得');
      // 获取途径为空 → 只展示名称（不出现悬空冒号）。
      final emptyGetWay = kHeadFrameCatalog.entries.firstWhere(
        (e) => e.value.getWay.isEmpty,
      );
      expect(headFrameCaption(emptyGetWay.key), emptyGetWay.value.name);
      // 未收录 → 既有占位（不编造获取途径）。
      expect(headFrameCaption(999999), '头像框 #999999');
    });
  });
}
