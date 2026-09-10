// 消息排序回归测试（flutter_chat_ui 迁移前置波）：
// 1) drift messagesOf 必须按 time 升序返回（当前为 DESC，离线历史恢复后渲染倒序）。
// 2) sortMessagesAscending 是稳定的升序纯函数（time 为 epoch 秒）。
// 3) ChatService.historyOf 返回升序副本（缓存以升序为规范）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/storage/chat_mapper.dart';

/// 期望的升序排序参考（time 比较器排序后的副本）。
List<ChatMessage> _expectedAscending(Iterable<ChatMessage> msgs) {
  final list = msgs.toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  return list;
}

void main() {
  group('messagesOf（drift 查询）', () {
    test('乱序插入后按 time 升序返回 [100, 200, 300]', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const key = 'friend_123';
      const owner = 1;

      // 乱序插入：300 / 100 / 200
      await db.insertMessage(
          chatMessageToCompanion(ChatMessage(uin: 1, text: 'first', time: 300), key, myUin: 1, ownerUin: owner));
      await db.insertMessage(
          chatMessageToCompanion(ChatMessage(uin: 1, text: 'second', time: 100), key, myUin: 1, ownerUin: owner));
      await db.insertMessage(
          chatMessageToCompanion(ChatMessage(uin: 1, text: 'third', time: 200), key, myUin: 1, ownerUin: owner));

      final rows = await db.messagesOf(owner, key);
      final got = rows.map((r) => r.time).toList();
      // 升序语义：已排序输入排序后应恒等
      final expected = _expectedAscending(
        [for (final r in rows) chatMessageFromRecord(r)],
      ).map((m) => m.time).toList();
      expect(got, expected);
      expect(got, [100, 200, 300]);
    });
  });

  group('sortMessagesAscending（纯函数）', () {
    test('任意乱序输入 → 升序输出', () {
      final msgs = [
        ChatMessage(uin: 1, text: 'a', time: 300),
        ChatMessage(uin: 1, text: 'b', time: 100),
        ChatMessage(uin: 1, text: 'c', time: 200),
      ];
      final sorted = sortMessagesAscending(msgs);
      expect(sorted.map((m) => m.time).toList(), [100, 200, 300]);
      expect(sorted.map((m) => m.text).toList(), ['b', 'c', 'a']);
      // 不修改入参（返回新列表）
      expect(msgs.map((m) => m.time).toList(), [300, 100, 200]);
      expect(identical(sorted, msgs), isFalse);
    });

    test('time 相等时保持原有相对顺序（稳定排序）', () {
      final msgs = [
        ChatMessage(uin: 1, text: 'first', time: 200),
        ChatMessage(uin: 1, text: 'later', time: 300),
        ChatMessage(uin: 1, text: 'second', time: 200),
      ];
      final sorted = sortMessagesAscending(msgs);
      expect(sorted.map((m) => m.text).toList(), ['first', 'second', 'later']);
    });

    test('已升序输入保持不变', () {
      final msgs = [
        ChatMessage(uin: 1, text: 'a', time: 100),
        ChatMessage(uin: 1, text: 'b', time: 200),
        ChatMessage(uin: 1, text: 'c', time: 300),
      ];
      expect(sortMessagesAscending(msgs).map((m) => m.time).toList(), [100, 200, 300]);
      expect(sortMessagesAscending(msgs).map((m) => m.text).toList(), ['a', 'b', 'c']);
    });
  });

  group('historyOf（内存缓存）', () {
    test('addLocalMessage 两次后 historyOf 按 time 升序返回', () {
      final service = ChatService(db: null);
      service.addLocalMessage(ChatSessionType.friend, 273640665, 'one');
      service.addLocalMessage(ChatSessionType.friend, 273640665, 'two');

      final msgs = service.historyOf(ChatSessionType.friend, 273640665);
      expect(msgs, hasLength(2));
      expect(msgs.map((m) => m.text).toList(), ['one', 'two']);
      // 严格升序（相邻差 ≥ 0；同秒相等也满足）
      for (var i = 1; i < msgs.length; i++) {
        expect(msgs[i].time >= msgs[i - 1].time, isTrue,
            reason: 'historyOf 必须按 time 升序');
      }
    });
  });
}
