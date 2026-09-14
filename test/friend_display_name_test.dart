import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/storage/chat_mapper.dart';

/// 好友名净化回归测试。
///
/// 历史插值 bug 曾把 `'${r.uin}'` 误写成 `'$r.uin'`：`$r.uin` 会把整个
/// Drift `FriendRecord` 插值成字符串再拼上字面量 `.uin`，库里因此落下一批
/// `FriendRecord(...).uin` 并直接显示。修复后读取路径统一走
/// [friendDisplayName]，坏值 / 空值回退迷你号。
void main() {
  group('friendDisplayName', () {
    test('空昵称 → 迷你号', () {
      expect(friendDisplayName('', 470134507), '470134507');
    });

    test('被写坏的 FriendRecord(...) 字面量 → 迷你号', () {
      const bad = 'FriendRecord(uin: 470134507, nickname: , avatar: null, '
          'isOnline: false, gameStatus: null, updatedAt: 1789214638, '
          'relation: 16, mark: 0, ownerUin: 279630451).uin';
      expect(friendDisplayName(bad, 470134507), '470134507');
    });

    test('真实昵称原样返回', () {
      expect(friendDisplayName('阿星', 470134507), '阿星');
    });
  });

  group('读取路径净化', () {
    test('friendFromRecord 把坏昵称读成迷你号', () {
      final r = FriendRecord(
        uin: 7,
        nickname: 'FriendRecord(uin: 7, nickname: , avatar: null).uin',
        isOnline: false,
        updatedAt: 1,
        relation: 16,
        mark: 0,
        ownerUin: 1,
      );
      expect(friendFromRecord(r).nickname, '7');
    });

    test('friendFromRecord 保留真实昵称', () {
      final r = FriendRecord(
        uin: 7,
        nickname: '小明',
        isOnline: false,
        updatedAt: 1,
        relation: 8,
        mark: 0,
        ownerUin: 1,
      );
      expect(friendFromRecord(r).nickname, '小明');
    });
  });
}
