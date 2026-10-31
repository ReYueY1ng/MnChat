// 历史分页（P0-2）的服务层契约：最新页恢复、游标向前翻页、收起、按天取窗口。
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/auth.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/core/services/chatpush.dart';
import 'package:mnchat/core/services/friend.dart';
import 'package:mnchat/core/services/group.dart';
import 'package:mnchat/core/services/message_center.dart';
import 'package:mnchat/core/services/player_home.dart';
import 'package:mnchat/core/services/social_sign.dart';
import 'package:mnchat/core/storage/app_database.dart';

import 'support/harness.dart';

class _FakeLoginClient extends LoginClient {
  @override
  Future<MiniAuth> login({
    required int uin,
    required String passwd,
    int apiId = 110,
    String deviceId = 'MNClientDefault',
  }) async => MiniAuth(
    uin: uin,
    apiId: apiId,
    name: 'Tester',
    s2: 's2',
    s2t: 's2t',
    jwt: 'jwt',
  );
}

class _FakeChatPushClient extends ChatPushClient {
  @override
  Future<(String, String)> alloc({
    required int uin,
    required String s2,
    required String s2t,
    required String jwt,
  }) async => throw StateError('not expected');
}

class _FakeFriendClient extends FriendClient {
  _FakeFriendClient() : super(uin: 7, s2: 'x', s2t: 'y');
  @override
  Future<Map<String, Object?>> queryFriendList({String? relation}) async => {};
}

class _FakeGroupClient extends GroupClient {
  _FakeGroupClient() : super(uin: 7, s2: 'x', s2t: 'y');
  @override
  Future<Map<String, Object?>> queryUserGroups() async => {};
}

ChatService _service(AppDatabase db) => ChatService.forTest(
  db: db,
  loginClient: _FakeLoginClient(),
  chatPushClient: _FakeChatPushClient(),
  friendClient: _FakeFriendClient(),
  groupClient: _FakeGroupClient(),
  messageCenterClient: MessageCenterClient(uin: 7, s2: 'x', s2t: 'y'),
  socialSignClient: SocialSignClient(uin: 7, s2: 'x', s2t: 'y'),
  playerHomeClient: PlayerHomeClient(uin: 7, s2: 'x', s2t: 'y'),
  heartbeatOverride: (auth) async => ('s2', 's2t'),
);

ChatMessagesCompanion _row({
  required int owner,
  required String key,
  required int time,
  required String text,
  int uin = 1,
}) => ChatMessagesCompanion.insert(
  content: text,
  sessionKey: key,
  uin: uin,
  time: time,
  isSuccess: true,
  isSystemMsg: false,
  isTime: false,
  direction: 'in',
  ownerUin: Value(owner),
);

void main() {
  const owner = 7;
  const key = 'friend_1001';

  late AppDatabase db;
  late ChatService service;

  setUp(() async {
    db = newTestDb();
    // 250 条连续消息：登录时只应恢复最新 200 条（time 51..250）。
    for (var i = 1; i <= 250; i++) {
      await db.insertMessage(
        _row(owner: owner, key: key, time: i, text: 'm$i'),
      );
    }
    service = _service(db);
    await service.login(uin: owner, password: 'p');
  });

  tearDown(() async {
    await service.dispose();
    await db.close();
  });

  group('启动恢复最新页', () {
    test('恢复最新 200 条而不是最早 200 条', () {
      final history = service.historyOf(ChatSessionType.friend, 1001);
      expect(history, hasLength(200));
      expect(history.first.text, 'm51');
      expect(history.last.text, 'm250');
    });

    test('存在更早的游标', () {
      expect(service.hasOlderHistory(ChatSessionType.friend, 1001), isTrue);
    });
  });

  group('游标向前翻页', () {
    test('翻一页补齐更早的 50 条，且走 historyStream 而不是 eventStream', () async {
      final normal = <ChatEvent>[];
      final history = <ChatEvent>[];
      final s1 = service.eventStream.listen(normal.add);
      final s2 = service.historyStream.listen(history.add);
      addTearDown(s1.cancel);
      addTearDown(s2.cancel);

      final added = await service.loadOlderHistory(
        ChatSessionType.friend,
        1001,
      );
      // broadcast stream 的投递在下一个微任务。
      await pumpEventQueue();
      expect(added, 50);
      final all = service.historyOf(ChatSessionType.friend, 1001);
      expect(all, hasLength(250));
      expect(all.first.text, 'm1');
      // 翻阅历史不应触发通知/未读那条事件流。
      expect(normal, isEmpty);
      expect(history, hasLength(1));
    });

    test('翻到底后游标消失，再翻返回 0', () async {
      expect(await service.loadOlderHistory(ChatSessionType.friend, 1001), 50);
      // 这一页恰好 50 条，游标还在；再翻一次拿空。
      expect(await service.loadOlderHistory(ChatSessionType.friend, 1001), 0);
      expect(service.hasOlderHistory(ChatSessionType.friend, 1001), isFalse);
    });

    test('加载更早期间收到新消息不会把历史裁回 50 条', () async {
      await service.loadOlderHistory(ChatSessionType.friend, 1001);
      service.addLocalMessage(ChatSessionType.friend, 1001, 'new');
      final all = service.historyOf(ChatSessionType.friend, 1001);
      expect(all.length, greaterThanOrEqualTo(250));
      expect(all.last.text, 'new');
    });
  });

  group('收起与重新进入', () {
    test('收起后只留最近 50 条；再次进入可继续向前翻', () async {
      await service.loadOlderHistory(ChatSessionType.friend, 1001);
      service.collapseHistory(ChatSessionType.friend, 1001);
      final trimmed = service.historyOf(ChatSessionType.friend, 1001);
      expect(trimmed, hasLength(50));
      expect(trimmed.last.text, 'm250');
      expect(service.hasOlderHistory(ChatSessionType.friend, 1001), isFalse);

      await service.prepareHistory(ChatSessionType.friend, 1001);
      expect(service.hasOlderHistory(ChatSessionType.friend, 1001), isTrue);
      final added = await service.loadOlderHistory(
        ChatSessionType.friend,
        1001,
      );
      expect(added, 50);
      expect(service.historyOf(ChatSessionType.friend, 1001).first.text, 'm151');
    });

    test('没有历史缓存的会话，prepareHistory 从库里取最新一页', () async {
      for (var i = 1; i <= 120; i++) {
        await db.insertMessage(
          _row(owner: owner, key: 'friend_4004', time: i, text: 'n$i'),
        );
      }
      await service.prepareHistory(ChatSessionType.friend, 4004);
      final history = service.historyOf(ChatSessionType.friend, 4004);
      expect(history, hasLength(120));
      expect(history.last.text, 'n120');
    });
  });

  group('按天取窗口', () {
    test('返回当天全部消息；空日期回退到该日之前最近 50 条', () async {
      final day1 = DateTime(2026, 10, 1);
      final day2 = DateTime(2026, 10, 2);
      final t1 = day1.millisecondsSinceEpoch ~/ 1000 + 3600;
      final t2 = day1.millisecondsSinceEpoch ~/ 1000 + 7200;
      final t3 = day2.millisecondsSinceEpoch ~/ 1000 + 60;
      for (final (time, text) in [(t1, 'd1a'), (t2, 'd1b'), (t3, 'd2a')]) {
        await db.insertMessage(
          _row(owner: owner, key: 'friend_9009', time: time, text: text),
        );
      }
      final d1 = await service.historyForDay(
        ChatSessionType.friend,
        9009,
        day1,
      );
      expect(d1.map((m) => m.text).toList(), ['d1a', 'd1b']);

      final empty = await service.historyForDay(
        ChatSessionType.friend,
        9009,
        DateTime(2026, 9, 1),
      );
      expect(empty, isEmpty);
    });
  });
}
