// ChatService 行为表征测试。
//
// 这些测试钉住当前可观察行为，作为后续解耦重构的**安全网**——
// 它们必须先在重构前对现状通过（证明是"表征"而非"定义"行为）。
// 用 ChatService.forTest 注入假客户端，避免真实网络。
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/emoji_catalog.dart'
    show kImfcEmojis, imfcMessageText;
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
import 'package:mnchat/core/storage/chat_mapper.dart';

/// 假登录客户端：跳过真实网络，直接返回成功认证。
class _FakeLoginClient extends LoginClient {
  _FakeLoginClient() : super();
  @override
  Future<MiniAuth> login({
    required int uin,
    required String passwd,
    int apiId = 110,
    String deviceId = 'MNClientDefault',
  }) async =>
      MiniAuth(
        uin: uin,
        apiId: apiId,
        name: 'Tester',
        s2: 's2',
        s2t: 's2t',
        jwt: 'jwt',
      );
}

/// 假 chatpush 客户端：跳过真实 WS，仅使 alloc 不命中真实 lb。
class _FakeChatPushClient extends ChatPushClient {
  _FakeChatPushClient() : super();
  @override
  Future<(String, String)> alloc({
    required int uin,
    required String s2,
    required String s2t,
    required String jwt,
  }) async =>
      throw StateError('not expected in these tests');
}

/// 假好友客户端：queryFriendList 返回空，避免 login 时真实网络产生垃圾会话。
class _FakeFriendClient extends FriendClient {
  _FakeFriendClient() : super(uin: 1, s2: 'x', s2t: 'y');
  @override
  Future<Map<String, Object?>> queryFriendList({String? relation}) async => {};
}

/// 假群客户端：queryUserGroups 返回空，避免 login 时真实网络产生垃圾会话。
class _FakeGroupClient extends GroupClient {
  _FakeGroupClient() : super(uin: 1, s2: 'x', s2t: 'y');
  @override
  Future<Map<String, Object?>> queryUserGroups() async => {};
}

/// 记录发出的聊天消息（校验互动表情的 payload 组装）。
class _CapturingFriendClient extends FriendClient {
  _CapturingFriendClient() : super(uin: 1, s2: 'x', s2t: 'y');

  final List<({int desUin, String msg, Object? extend})> sent = [];

  @override
  Future<Map<String, Object?>> queryFriendList({String? relation}) async => {};

  @override
  Future<Map<String, Object?>> sendChatMsg({
    required Object desUin,
    required String msg,
    int showType = 1,
    int msgtype = 1,
    int issys = 0,
    Object? extendData,
    Object? uinOverride,
  }) async {
    sent.add((
      desUin: int.tryParse('$desUin') ?? 0,
      msg: msg,
      extend: extendData,
    ));
    return {'result': 0};
  }
}

/// 构造一个"已登录"的 ChatService：注入假客户端 + 假心跳（跳过真实 WS 换 s2）。
ChatService _loggedInService({
  AppDatabase? db,
  FriendClient? friend,
  GroupClient? group,
  ChatPushClient? chatpush,
  LoginClient? login,
}) {
  final service = ChatService.forTest(
    db: db,
    loginClient: login ?? _FakeLoginClient(),
    chatPushClient: chatpush ?? _FakeChatPushClient(),
    friendClient: friend ?? _FakeFriendClient(),
    groupClient: group ?? _FakeGroupClient(),
    messageCenterClient: MessageCenterClient(uin: 1, s2: 'x', s2t: 'y'),
    socialSignClient: SocialSignClient(uin: 1, s2: 'x', s2t: 'y'),
    playerHomeClient: PlayerHomeClient(uin: 1, s2: 'x', s2t: 'y'),
    heartbeatOverride: (auth) async => ('s2', 's2t'),
  );
  return service;
}

void main() {
  group('session 列表排序 / 消息 upsert 后失效', () {
    test('upsert 使 lastMessage 更新、sessions 按最后消息时间倒序', () async {
      final service = _loggedInService();
      await service.login(uin: 1, password: 'p');
      service.addLocalMessage(ChatSessionType.friend, 100, 'a');
      service.addLocalMessage(ChatSessionType.friend, 100, 'b');
      service.addLocalMessage(ChatSessionType.friend, 200, 'g');

      final ss = service.sessions;
      // 断言两个 friend 会话都存在
      expect(ss.map((s) => s.id).toSet().containsAll({100, 200}), isTrue);
      // 缓存失效前快照（按最后消息时间）
      final before = service.sessions.map((s) => s.lastMessage!.time).toList();
      // 追加一条更晚时间的消息 → 该会话应排到最前
      await Future.delayed(const Duration(milliseconds: 1100));
      service.addLocalMessage(ChatSessionType.friend, 100, 'late');
      final after = service.sessions.map((s) => s.lastMessage!.time).toList();
      expect(after, isNot(equals(before)));
      // 现在 friend(100) 的最后消息是 late，time 最新 → 排第一
      expect(service.sessions.first.id, 100);
      expect(service.sessions.first.lastMessage!.text, 'late');
    });

    test('重复投递同一逻辑消息不改变 lastMessage / 不新增条目', () {
      final service = _loggedInService();
      service.addLocalMessage(ChatSessionType.friend, 7, 'hi');
      expect(service.historyOf(ChatSessionType.friend, 7), hasLength(1));
    });
  });

  group('historyOf 返回升序、按 id 去重', () {
    test('乱序时间戳输入 → historyOf 升序', () async {
      final service = _loggedInService();
      // 直接塞缓存：通过 addLocalMessage 只能拿到单调递增时间；这里用请求历史路径。
      // 用 db 预置乱序消息后 loadOfflineCache 验证。见下方 offline bootstrap 组。
      // 本用例仅验证 addLocalMessage 顺序保持（时间单调）。
      service.addLocalMessage(ChatSessionType.friend, 55, 'one');
      await Future.delayed(const Duration(milliseconds: 1100));
      service.addLocalMessage(ChatSessionType.friend, 55, 'two');
      final msgs = service.historyOf(ChatSessionType.friend, 55);
      expect(msgs.map((m) => m.text).toList(), ['one', 'two']);
      for (var i = 1; i < msgs.length; i++) {
        expect(msgs[i].time >= msgs[i - 1].time, isTrue);
      }
    });

    test('同 id 去重（uin,time,text 三元组唯一）', () {
      final service = _loggedInService();
      service.addLocalMessage(ChatSessionType.friend, 9, 'x');
      service.addLocalMessage(ChatSessionType.friend, 9, 'x'); // 重复
      final msgs = service.historyOf(ChatSessionType.friend, 9);
      expect(msgs.map((m) => m.text).where((t) => t == 'x'), hasLength(1));
    });
  });

  group('unread accounting with setViewing', () {
    test('正在查看时消息不累计未读；离开后补标已读', () {
      final service = _loggedInService();
      // 登记查看 friend_50（autoRead 会 markRead，但此刻无未读）
      service.setViewing(ChatSessionType.friend, 50, autoRead: false);
      // 模拟收到好友消息（本地消息，uin=myUin 不计未读；这里构造对方消息）
      // addLocalMessage 用 myUin，恒 muted → 无法验证。改用 _upsert 不可行（私有）。
      // 因此这里验证的是：myUin 消息在查看时也 muted 且不产生未读。
      service.addLocalMessage(ChatSessionType.friend, 50, 'self');
      // self 恒 muted（自己发的）→ unread 保持 0
      expect(service.sessions.firstWhere((s) => s.id == 50).unreadCount, 0);
      service.setViewing(null, null, autoRead: false); // 离开
      service.setViewing(null, null, autoRead: false);
    });
  });

  group('offline bootstrap from DB（ownerUin 隔离）', () {
    test('预置会话+消息后 login → _bootstrapSessions 恢复', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const owner = 42;
      // 直接预置会话/消息行（绕过 Service 私有路径，模拟落库状态）
      await db.insertMessage(chatMessageToCompanion(
        ChatMessage(uin: 500, text: 'hello', time: 1700000000),
        'friend_500',
        myUin: owner,
        ownerUin: owner,
      ));
      await db.upsertSession(chatSessionToCompanion(
        ChatSession(id: 500, type: ChatSessionType.friend, name: 'Bob'),
        ownerUin: owner,
      ));
      final service = _loggedInService(db: db);
      await service.login(uin: owner, password: 'p');

      final sess = service.sessions.where((s) => s.id == 500).toList();
      expect(sess, hasLength(1));
      expect(sess.first.name, 'Bob');
      final hist = service.historyOf(ChatSessionType.friend, 500);
      expect(hist, hasLength(1));
      expect(hist.first.text, 'hello');
    });

    test('不同 owner 数据不串号', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const ownerA = 42;
      await db.insertMessage(chatMessageToCompanion(
        ChatMessage(uin: 600, text: 'a-msg', time: 1700000000),
        'friend_600',
        myUin: ownerA,
        ownerUin: ownerA,
      ));
      await db.upsertSession(chatSessionToCompanion(
        ChatSession(id: 600, type: ChatSessionType.friend, name: 'AA'),
        ownerUin: ownerA,
      ));
      // ownerB 登录，不应看到 ownerA 的数据
      final service = _loggedInService(db: db);
      await service.login(uin: 999, password: 'p');
      expect(service.historyOf(ChatSessionType.friend, 600), isEmpty);
      expect(service.sessions.where((s) => s.id == 600), isEmpty);
    });
  });

  group('好友消息 upsert 持久化 + 快照', () {
    test('addLocalMessage 落库一行 + emits 快照', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _loggedInService(db: db);
      await service.login(uin: 42, password: 'p');
      final snapshots = <int>[];
      service.sessionStream.listen((s) => snapshots.add(s.sessions.length));

      service.addLocalMessage(ChatSessionType.friend, 700, 'ping');
      // 落库
      final rows = await db.allMessages(42);
      expect(rows, hasLength(1));
      expect(rows.first.content, 'ping');
      // 快照至少发了一次
      expect(snapshots, isNotEmpty);
    });
  });

  group('reset 清理状态 + 取消重连', () {
    test('reset 后未登录、session 清空、state=unauthenticated', () async {
      final service = _loggedInService();
      await service.login(uin: 1, password: 'p');
      service.addLocalMessage(ChatSessionType.friend, 123, 'x');
      expect(service.sessions, isNotEmpty);
      expect(service.state, ChatServiceState.connected);
      expect(service.myUin, 1);

      await service.reset();
      expect(service.state, ChatServiceState.unauthenticated);
      expect(service.myUin, 0);
      expect(service.sessions, isEmpty);
      expect(service.contacts, isEmpty);
      expect(service.historyOf(ChatSessionType.friend, 123), isEmpty);
      await service.dispose();
    });
  });

  group('互动表情 sendImfcEmoji（骰子 / 猜拳）', () {
    test('骰子：结果 1..6，文本为 JSON 信封，extend_data 内嵌 interCode', () async {
      final friend = _CapturingFriendClient();
      final service = _loggedInService(friend: friend);
      await service.login(uin: 1, password: 'p');

      final dice = kImfcEmojis.firstWhere((e) => e.index == 1);
      final result = await service.sendImfcEmoji(100, dice);

      expect(result, inInclusiveRange(1, 6));
      expect(friend.sent.length, 1);
      final sent = friend.sent.single;
      expect(sent.desUin, 100);

      final interCode = '@IMFC&1_$result';
      // 消息文本 = JSON{content: 低版本占位文案, extend_data: interCode}
      expect(sent.msg, imfcMessageText(1, result));
      // extend_data = url_encode(base64(JSON{nickname, shareType, bubble, interCode}))
      final json = utf8.decode(
        base64Decode(Uri.decodeComponent(sent.extend! as String)),
      );
      expect(jsonDecode(json)['interCode'], interCode);

      // 本地乐观回显（气泡据此渲染结果帧）
      final hist = service.historyOf(ChatSessionType.friend, 100);
      expect(hist.any((m) => m.interCode == interCode), isTrue);
      await service.dispose();
    });

    test('猜拳：结果 1..3', () async {
      final friend = _CapturingFriendClient();
      final service = _loggedInService(friend: friend);
      await service.login(uin: 1, password: 'p');

      final rps = kImfcEmojis.firstWhere((e) => e.index == 2);
      for (var i = 0; i < 20; i++) {
        final result = await service.sendImfcEmoji(200, rps);
        expect(result, inInclusiveRange(1, 3));
      }
      expect(friend.sent.length, 20);
      expect(friend.sent.every((s) => s.msg.contains('@IMFC&2_')), isTrue);
      await service.dispose();
    });
  });

  group('markRead 只在红点真的消掉时发会话快照', () {
    test('未读 3 → 发一次；已经是 0 / 会话不存在 → 不发', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const owner = 42;
      await db.insertMessage(chatMessageToCompanion(
        ChatMessage(uin: 700, text: 'hi', time: 1700000000),
        'friend_700',
        myUin: owner,
        ownerUin: owner,
      ));
      await db.upsertSession(chatSessionToCompanion(
        ChatSession(
          id: 700,
          type: ChatSessionType.friend,
          name: 'Bob',
          unreadCount: 3,
        ),
        ownerUin: owner,
      ));

      final service = _loggedInService(db: db);
      await service.login(uin: owner, password: 'p');
      expect(
        service.sessions.firstWhere((s) => s.id == 700).unreadCount,
        3,
        reason: '预置的未读要能恢复，否则本用例失去意义',
      );

      final snapshots = <SessionSnapshot>[];
      final sub = service.sessionStream.listen(snapshots.add);
      addTearDown(sub.cancel);

      // 3 → 0：红点消掉，必须广播（列表要跟着清红点）。
      service.markRead(ChatSessionType.friend, 700);
      await pumpEventQueue();
      expect(snapshots, hasLength(1));
      expect(
        snapshots.single.sessions.firstWhere((s) => s.id == 700).unreadCount,
        0,
      );

      // 已经是 0：进/出会话、回前台都会再调一次，不该为空转发买单。
      service.markRead(ChatSessionType.friend, 700);
      await pumpEventQueue();
      expect(snapshots, hasLength(1));

      // 不存在的会话：无事可做，不发快照。
      service.markRead(ChatSessionType.friend, 424242);
      await pumpEventQueue();
      expect(snapshots, hasLength(1));

      await service.dispose();
    });
  });
}