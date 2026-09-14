import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/profile.dart';

void main() {
  group('PlayerProfile.resolveRoleHeadFallback 角色头像本地回退', () {
    test('人物中心头信息可用（type 1/3/4 且 id>0）时原样透传', () {
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 1, headId: 7),
        (type: 1, id: 7),
      );
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 3, headId: 7001),
        (type: 3, id: 7001),
      );
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 4, headId: 9001),
        (type: 4, id: 9001),
      );
      // 可用头信息优先于资料里的皮肤/型号（保持官方选择的头像本体）。
      expect(
        PlayerProfile.resolveRoleHeadFallback(
          headType: 1,
          headId: 31,
          skinId: 5,
          model: 2,
        ),
        (type: 1, id: 31),
      );
    });

    test('缺失/type2 且有皮肤：回退 type 1（SkinID 经 kSkinHeadIcon 映射）', () {
      expect(
        PlayerProfile.resolveRoleHeadFallback(skinId: 5),
        (type: 1, id: 5),
      );
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 2, headId: 9, skinId: 5),
        (type: 1, id: 5),
      );
      // type 1 但 id 无效（<=0）同样降级到资料皮肤。
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 1, headId: 0, skinId: 5),
        (type: 1, id: 5),
      );
    });

    test('无皮肤（或无头信息）时回退 RoleInfo.Model → type 4（roleicons/<model>.png）',
        () {
      expect(
        PlayerProfile.resolveRoleHeadFallback(model: 2),
        (type: 4, id: 2),
      );
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 2, headId: 9, model: 2),
        (type: 4, id: 2),
      );
      // 皮肤 id 非正数（0）时继续降到 Model。
      expect(
        PlayerProfile.resolveRoleHeadFallback(skinId: 0, model: 3),
        (type: 4, id: 3),
      );
    });

    test('无任何可用来源时返回 null（调用方保留原值/回退网络头像）', () {
      expect(PlayerProfile.resolveRoleHeadFallback(), isNull);
      expect(
        PlayerProfile.resolveRoleHeadFallback(
          headType: 2,
          headId: 9,
          skinId: 0,
          model: -1,
        ),
        isNull,
      );
      // 非法头类型（0/5）不视为可用，且无资料兜底 → null。
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 5, headId: 9),
        isNull,
      );
      expect(
        PlayerProfile.resolveRoleHeadFallback(headType: 0, headId: 9),
        isNull,
      );
    });

    test('绝不产出 type 2（头套无 2D 资源，产出会挡住网络头像）', () {
      final cases = <({int type, int id})?>[
        PlayerProfile.resolveRoleHeadFallback(headType: 2, headId: 9),
        PlayerProfile.resolveRoleHeadFallback(headType: 2, headId: 9, skinId: 5),
        PlayerProfile.resolveRoleHeadFallback(headType: 2, headId: 9, model: 2),
        PlayerProfile.resolveRoleHeadFallback(
          headType: 2,
          headId: 9,
          skinId: 5,
          model: 2,
        ),
      ];
      for (final r in cases) {
        expect(r?.type, isNot(2));
      }
    });

    test('与 fromItem 串起来：真实资料 → 角色皮肤头像 (1, SkinID)', () {
      final p = PlayerProfile.fromItem({
        'uin': 123,
        'profile': {
          'RoleInfo': {'NickName': '小明', 'SkinID': 33, 'Model': 2},
          'header': {'url': 'https://example.com/a.png'},
        },
      });
      expect(p, isNotNull);
      final parsed = p!;
      expect(
        PlayerProfile.resolveRoleHeadFallback(
          headType: null,
          headId: null,
          skinId: parsed.headSkinId,
          model: parsed.headModel,
        ),
        (type: 1, id: 33),
      );
      // 未穿皮肤（SkinID=0 → null）时落到官方角色本体兜底。
      final bare = PlayerProfile.fromItem({
        'uin': 124,
        'profile': {
          'RoleInfo': {'NickName': '小红', 'SkinID': 0, 'Model': 2},
        },
      });
      expect(
        PlayerProfile.resolveRoleHeadFallback(
          headType: null,
          headId: null,
          skinId: bare!.headSkinId,
          model: bare.headModel,
        ),
        (type: 4, id: 2),
      );
    });
  });
}
