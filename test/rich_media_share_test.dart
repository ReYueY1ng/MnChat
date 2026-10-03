import 'package:flutter_test/flutter_test.dart';

import 'package:mnchat/core/models/messages.dart' show GroupInfo;
import 'package:mnchat/core/services/rich_media.dart' show RichMedia, ShareType;

void main() {
  group('ShareType 标签补全', () {
    test('新补的分享类型有中文标签，未知类型回落「分享」', () {
      expect(ShareType.label(ShareType.familyRecruit), '家族招募');
      expect(ShareType.label(ShareType.rankSystem), '排行榜');
      expect(ShareType.label(ShareType.qixiPartnerInvite), '伙伴邀请');
      expect(ShareType.label(ShareType.familyDynamics), '家族动态');
      expect(ShareType.label(ShareType.contentFavsShare), '收藏');
      expect(ShareType.label(99999), '分享');
    });
  });

  group('通用分享卡兜底文案', () {
    test('无字段的卡片给 hint，而不是空卡片', () {
      const media = RichMedia(shareType: ShareType.skin);
      expect(media.hint, isNotEmpty);
      // subtitle 在无字段时回落到 title（标题已展示，不重复渲染）
      expect(media.subtitle, media.title);
    });

    test('有具体字段时 title 取类型标签、name 可取原名', () {
      const media = RichMedia(shareType: ShareType.map, name: '天空之城');
      expect(media.isMap, isTrue);
      expect(media.name, '天空之城');
    });
  });

  group('GroupInfo 群头像字段持久化', () {
    test('toJson/fromJson 保留 iconId/iconType', () {
      const info = GroupInfo(
        groupId: 456,
        name: '测试群',
        iconId: 7,
        iconType: 2,
      );
      final back = GroupInfo.fromJson(info.toJson());
      expect(back.iconId, 7);
      expect(back.iconType, 2);
      expect(back.name, '测试群');
    });
  });
}
