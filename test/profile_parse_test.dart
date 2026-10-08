import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/profile.dart';

void main() {
  group('PlayerProfile.fromItem 头像框解析', () {
    test('head_frame_id 在 profile 层（对齐 friendservice.lua）', () {
      // 真实结构：head_frame_id 与 RoleInfo 同级，RoleInfo 只放 NickName 等。
      final p = PlayerProfile.fromItem({
        'uin': 123,
        'profile': {
          'head_frame_id': 20201,
          'RoleInfo': {'NickName': '小明'},
          'head_frames': {
            '20201': {'t': 1},
            '20205': <String, Object?>{},
          },
          'head_frames_temp': {
            '20210': {'t': 1, 'left': 100},
          },
          'header': {'url': 'https://example.com/a.png'},
        },
      });

      expect(p, isNotNull);
      expect(p!.uin, 123);
      expect(p.nickname, '小明');
      expect(p.headFrameId, 20201);
      // `header`/`header2` 实测是**地图截图**（`map<NNN>.mini1.cn/map/...`），
      // 不是头像 → 不再当头像用（2026-10-08 真实账号探针）。
      expect(p.avatarUrl, isNull);
      expect(p.ownedHeadFrameIds, containsAll(<int>[20201, 20205, 20210]));
      expect(p.ownedHeadFrameIds.length, 3);
    });

    test('head_frame_id 落在 RoleInfo 内时也能解析（兼容）', () {
      final p = PlayerProfile.fromItem({
        'uin': 123,
        'profile': {
          'RoleInfo': {'NickName': '小明', 'head_frame_id': 20202},
        },
      });
      expect(p!.headFrameId, 20202);
    });

    test('head_frame_id 为 0 或缺失时归一为 null（不渲染头像框）', () {
      final zero = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {'head_frame_id': 0},
      });
      expect(zero!.headFrameId, isNull);

      final missing = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {
          'RoleInfo': {'NickName': 'a'},
        },
      });
      expect(missing!.headFrameId, isNull);
    });

    test('缺少 head_frames 时为空集合（不代表无头像框）', () {
      final p = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {
          'RoleInfo': {'NickName': 'a'},
        },
      });
      expect(p, isNotNull);
      expect(p!.ownedHeadFrameIds, isEmpty);
    });

    test('非法 key 被忽略，仅保留正整数 id', () {
      final p = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {
          'head_frames': {'abc': 1, '99': 1, '0': 1, '-3': 1},
        },
      });
      expect(p!.ownedHeadFrameIds, <int>{99});
    });

    test('uin 缺失时返回 null', () {
      final p = PlayerProfile.fromItem({
        'profile': {
          'RoleInfo': {'NickName': 'a'},
        },
      });
      expect(p, isNull);
    });
  });

  group('PlayerProfile RoleInfo 角色头像字段解析', () {
    test('读取 RoleInfo.SkinID / Model（真实资料结构）', () {
      // 官方角色头像链路的数据源：roleicons/<Model>.png 或
      // roleicons/<roleskin[SkinID].Head>.png。
      final p = PlayerProfile.fromItem({
        'uin': 123,
        'profile': {
          'head_frame_id': 20201,
          'RoleInfo': {'NickName': '小明', 'SkinID': 33, 'Model': 2},
          'header': {'url': 'https://example.com/a.png'},
        },
      });

      expect(p, isNotNull);
      expect(p!.headSkinId, 33);
      expect(p.headModel, 2);
    });

    test('兼容小写/别名拼写（skin_id / skinId / model）', () {
      final p = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {
          'RoleInfo': {'NickName': 'a', 'skin_id': 12, 'model': 3},
        },
      });
      expect(p!.headSkinId, 12);
      expect(p.headModel, 3);

      final alias = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {
          'RoleInfo': {'NickName': 'a', 'skinId': 13},
        },
      });
      expect(alias!.headSkinId, 13);
    });

    test('缺失或非正数归一为 null（不产出无效头像 id）', () {
      final missing = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {
          'RoleInfo': {'NickName': 'a'},
        },
      });
      expect(missing!.headSkinId, isNull);
      expect(missing.headModel, isNull);

      final nonPositive = PlayerProfile.fromItem({
        'uin': 1,
        'profile': {
          'RoleInfo': {'NickName': 'a', 'SkinID': 0, 'Model': -1},
        },
      });
      expect(nonPositive!.headSkinId, isNull);
      expect(nonPositive.headModel, isNull);
    });
  });

  group('resolveDiyUrl DIY 头像解析（pre_url 仅本人可见）', () {
    test('仅 pass_url：本人与他人一律用 pass', () {
      final info = <String, Object?>{
        'diy_header': {'pass_url': 'https://a/pass.png'},
      };
      expect(resolveDiyUrl(info, isSelf: false), 'https://a/pass.png');
      expect(resolveDiyUrl(info, isSelf: true), 'https://a/pass.png');
    });

    test('仅 pre_url：本人可见，他人不可见（回退角色头像）', () {
      final info = <String, Object?>{
        'diy_header': {'pre_url': 'https://a/pre.png'},
      };
      expect(resolveDiyUrl(info, isSelf: true), 'https://a/pre.png');
      expect(resolveDiyUrl(info, isSelf: false), isNull);
    });

    test('pass + pre：一律优先 pass', () {
      final info = <String, Object?>{
        'diy_header': {'pass_url': 'pass', 'pre_url': 'pre'},
      };
      expect(resolveDiyUrl(info, isSelf: false), 'pass');
      expect(resolveDiyUrl(info, isSelf: true), 'pass');
    });

    test('两者都没有 / diy_header 缺失或类型不符：null', () {
      expect(
        resolveDiyUrl(<String, Object?>{
          'diy_header': {'pass_url': '', 'pre_url': ''},
        }, isSelf: true),
        isNull,
      );
      expect(resolveDiyUrl(const <String, Object?>{}, isSelf: true), isNull);
      expect(
        resolveDiyUrl(<String, Object?>{'diy_header': 'oops'}, isSelf: false),
        isNull,
      );
    });
  });
}
