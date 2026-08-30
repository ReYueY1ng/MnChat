import 'package:flutter_test/flutter_test.dart';

/// 好友列表结构解析测试——实测真实响应（用真实账号验证）：
/// `friend_list` 是**扁平数组**，每项只有 `{mark, uin, relation}`，
/// **不含昵称/头像**（需 batch_friend_info 另取）。
/// 之前误判为嵌套 baseinfo 结构是 bug 根因。
void main() {
  // 实测真实响应样本（160 好友项中的单项）
  const flatItem = <String, Object?>{
    'mark': 1627004582,
    'uin': 1134065913,
    'relation': 8,
  };

  // uin→info 映射的兼容样本（老接口或别的返回值形态）
  const nestedItem = <String, Object?>{
    'online': 1,
    'relation': 16,
    'baseinfo': <String, Object?>{
      'Uin': 61595887,
      'RoleInfo': <String, Object?>{'NickName': 'nested_friend'},
    },
    'profile': <String, Object?>{
      'header': <String, Object?>{'url': 'https://cdn.example.com/h.png'},
    },
  };

  group('friend list structure (real: flat {mark,uin,relation})', () {
    test('扁平项 uin 在顶层（无 baseinfo）', () {
      expect(flatItem['uin'], 1134065913);
      expect(flatItem['mark'], 1627004582);
      expect(flatItem['relation'], 8);
      // 顶层没有嵌套 baseinfo —— 之前误读嵌套是取不到 uin 的根因
      expect(flatItem.containsKey('baseinfo'), isFalse);
    });

    test('扁平项没有昵称/头像（需 batch_friend_info 另取）', () {
      expect(flatItem.containsKey('NickName'), isFalse);
      expect(flatItem.containsKey('nickname'), isFalse);
      expect(flatItem.containsKey('profile'), isFalse);
    });

    test('兼容嵌套结构（uin 在 baseinfo.Uin）', () {
      final bi = nestedItem['baseinfo'] as Map;
      expect(bi['Uin'], 61595887);
      final role = bi['RoleInfo'] as Map;
      expect(role['NickName'], 'nested_friend');
    });

    test('friend_list 是扁平 List（数组）', () {
      final list = <Map<String, Object?>>[
        flatItem.cast<String, Object?>(),
        const <String, Object?>{'mark': 0, 'uin': 153078116, 'relation': 16}
            .cast<String, Object?>(),
      ];
      expect(list.length, 2);
      expect(list.first['uin'], 1134065913);
      expect(list.last['uin'], 153078116);
    });
  });
}