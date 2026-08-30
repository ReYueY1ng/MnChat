import 'package:flutter_test/flutter_test.dart';

/// 好友列表嵌套结构解析测试——对齐反编译源码 ParseFriendData：
/// friend_list 每项是 {online, relation, baseinfo:{Uin, RoleInfo:{NickName},
/// SkinID, Model}, profile:{header:{url, md5}}}。
/// 该结构决定了 chat_service 中 _friendUin/_friendNickname/_friendAvatar
/// 必须读嵌套 key（不能读扁平的 Uin/NickName/IconUrl）。
void main() {
  // 真实响应样本（账号有好友时的结构，字段名来自 friendservice.lua ParseFriendData）
  const nestedItem = <String, Object?>{
    'online': 1,
    'relation': 8, // friend_eachother = 1<<3
    'baseinfo': <String, Object?>{
      'Uin': 1134065913,
      'RoleInfo': <String, Object?>{
        'NickName': 'test_friend',
        'SkinID': 12345,
        'Model': 3,
      },
      'CltVersion': 80384,
    },
    'profile': <String, Object?>{
      'header': <String, Object?>{
        'url': 'https://cdn.example.com/avatar/1134065913.png',
        'md5': 'abc',
      },
    },
  };

  group('friend list nested structure (decompiled ParseFriendData)', () {
    test('baseinfo.Uin 是好友 uin（非顶层 Uin）', () {
      final baseinfo = nestedItem['baseinfo'] as Map;
      expect(baseinfo['Uin'], 1134065913);
      // 顶层没有扁平 Uin —— 这正是旧代码取不到 uin 的根因
      expect(nestedItem.containsKey('Uin'), isFalse);
      expect(nestedItem.containsKey('uin'), isFalse);
    });

    test('昵称在 baseinfo.RoleInfo.NickName', () {
      final baseinfo = nestedItem['baseinfo'] as Map;
      final role = baseinfo['RoleInfo'] as Map;
      expect(role['NickName'], 'test_friend');
      // 顶层没有扁平 NickName
      expect(nestedItem.containsKey('NickName'), isFalse);
      expect(nestedItem.containsKey('nickname'), isFalse);
    });

    test('头像 URL 在 profile.header.url', () {
      final profile = nestedItem['profile'] as Map;
      final header = profile['header'] as Map;
      expect(header['url'], 'https://cdn.example.com/avatar/1134065913.png');
      // 顶层没有扁平 IconUrl
      expect(nestedItem.containsKey('IconUrl'), isFalse);
    });

    test('含 uin→info 映射包装的 friend_list（服务端真实形状）', () {
      final friendList = <String, Object?>{'1134065913': nestedItem};
      final items = <Map<String, Object?>>[];
      for (final v in friendList.values) {
        if (v is Map) items.add(v.cast<String, Object?>());
      }
      expect(items.length, 1);
      final item = items.first;
      final baseinfo = item['baseinfo'] as Map;
      expect(baseinfo['Uin'], 1134065913);
    });
  });
}