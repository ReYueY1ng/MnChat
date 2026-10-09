// 「高频快照不再放大成重复请求」的 provider 层测试。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/auth.dart' show MiniAuth;
import 'package:mnchat/core/services/chat_service.dart' show SessionSnapshot;
import 'package:mnchat/core/services/partner.dart' show PartnerClient, PartnerInfo;
import 'package:mnchat/core/services/profile.dart'
    show HeadInfo, HeadSlot, PlayerProfile, ProfileClient;
import 'package:mnchat/state/providers.dart';

/// 记录被调用的拍档接口（不碰网络）。
class _CountingPartnerClient extends PartnerClient {
  _CountingPartnerClient(this.calls)
    : super(uin: 1, s2: 's', s2t: 't', dio: Dio(), baseUrl: 'https://h');

  final List<String> calls;

  @override
  Future<Map<int, int>> getPlatformLevels(List<int> uins) async {
    calls.add('levels:${uins.join(',')}');
    return <int, int>{for (final u in uins) u: 10};
  }

  @override
  Future<List<PartnerInfo>> getPartnerList({int? otherUin}) async {
    calls.add('list');
    return const <PartnerInfo>[];
  }

  @override
  Future<Map<int, int>> getVipExpiry(List<int> uins) async {
    calls.add('vip:${uins.join(',')}');
    return const <int, int>{};
  }
}

SessionSnapshot _snapshot(List<int> friendUins, {String lastText = 'x'}) =>
    SessionSnapshot(
      <ChatSession>[
        for (final uin in friendUins)
          ChatSession(
            id: uin,
            type: ChatSessionType.friend,
            name: '$uin',
            lastMessage: ChatMessage(uin: uin, text: lastText, time: 1700000000),
          ),
      ],
      const [],
    );

void main() {
  group('friendSessionUinsKey', () {
    test('只取好友会话、升序去重；没有数据为空串', () {
      expect(friendSessionUinsKey(null), '');
      expect(
        friendSessionUinsKey(_snapshot(<int>[9, 3, 3])),
        '3,9',
      );
      expect(
        friendSessionUinsKey(
          SessionSnapshot(
            const <ChatSession>[
              ChatSession(id: 7, type: ChatSessionType.group, name: 'g'),
              ChatSession(id: 0, type: ChatSessionType.friend, name: 'bad'),
            ],
            const [],
          ),
        ),
        '',
      );
    });
  });

  group('partnerDirectoryProvider 的重跑条件', () {
    test('好友集合不变时，连发会话快照不会重跑（每条消息不再 +3 请求）', () async {
      final calls = <String>[];
      final snapshots = StreamController<SessionSnapshot>();
      addTearDown(snapshots.close);
      final container = ProviderContainer(
        overrides: [
          partnerClientProvider.overrideWithValue(_CountingPartnerClient(calls)),
          sessionListProvider.overrideWith((ref) => snapshots.stream),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(partnerDirectoryProvider, (_, _) {});
      addTearDown(sub.close);

      snapshots.add(_snapshot(<int>[1, 2]));
      await pumpEventQueue();
      await container.read(partnerDirectoryProvider.future);
      await pumpEventQueue();
      expect(calls, <String>['levels:1,2', 'list', 'vip:1,2']);

      // 又来了一条消息（快照对象是新的），好友集合没变 → 不该再请求。
      snapshots.add(_snapshot(<int>[1, 2], lastText: '新消息'));
      await pumpEventQueue();
      expect(calls, hasLength(3), reason: '好友集合没变就不该重跑');

      // 好友集合变了 → 才重跑。
      snapshots.add(_snapshot(<int>[1, 2, 3]));
      await pumpEventQueue();
      await container.read(partnerDirectoryProvider.future);
      await pumpEventQueue();
      expect(calls, hasLength(6));
      expect(calls.sublist(3), <String>['levels:1,2,3', 'list', 'vip:1,2,3']);
    });
  });

  group('AuthState 值相等', () {
    test('同一 auth 实例 + 相同字段相等；换实例 / busy / error 变化不等', () {
      final auth = MiniAuth(
        uin: 1,
        apiId: 110,
        name: 'n',
        s2: 's',
        s2t: 't',
        jwt: 'j',
      );
      final other = MiniAuth(
        uin: 1,
        apiId: 110,
        name: 'n',
        s2: 's',
        s2t: 't',
        jwt: 'j',
      );

      expect(AuthState(isLoggedIn: true, auth: auth) == AuthState(isLoggedIn: true, auth: auth), isTrue);
      expect(
        AuthState(isLoggedIn: true, auth: auth).hashCode,
        AuthState(isLoggedIn: true, auth: auth).hashCode,
      );
      // 换账号/重登录 → 新的 auth 实例 → 必须视为不同状态
      expect(AuthState(isLoggedIn: true, auth: auth) == AuthState(isLoggedIn: true, auth: other), isFalse);
      expect(AuthState() == AuthState(), isTrue);
      expect(AuthState(isBusy: true) == AuthState(), isFalse);
      expect(AuthState(error: 'e') == AuthState(), isFalse);
    });
  });

  group('myAvatarInfoProvider 的重跑条件（自己的资料不被多次获取）', () {
    test('AuthState 抖动不重拉；换账号才重拉；一次运行里批量资料只拉一次', () async {
      final calls = <String>[];
      final auth = MiniAuth(
        uin: 1,
        apiId: 110,
        name: 'n',
        s2: 's',
        s2t: 't',
        jwt: 'j',
      );
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_FakeAuthNotifier.new),
          profileClientProvider.overrideWithValue(_CountingProfileClient(calls)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(authProvider.notifier) as _FakeAuthNotifier;
      notifier.setAuth(auth);
      final sub = container.listen(myAvatarInfoProvider, (_, _) {});
      addTearDown(sub.close);

      await container.read(myAvatarInfoProvider.future);
      await pumpEventQueue();
      expect(calls.where((c) => c.startsWith('heads:')), hasLength(1));
      expect(
        calls.where((c) => c.startsWith('batch3:')),
        hasLength(1),
        reason: '「资料兜底」与「头像 URL 兜底」必须共用同一次 getProfileBatch3',
      );

      // busy / 连接状态抖动（同一个 auth 实例）→ 不该重跑、不重拉
      final before = calls.length;
      notifier.setAuth(auth, busy: true);
      await pumpEventQueue();
      expect(calls.length, before, reason: '只依赖账号本身 → 状态抖动不该重跑');

      // 换账号 / 重登录（新的 auth 实例）→ 必须重拉
      notifier.setAuth(
        MiniAuth(
          uin: 1,
          apiId: 110,
          name: 'n',
          s2: 's2',
          s2t: 't2',
          jwt: 'j2',
        ),
      );
      await pumpEventQueue();
      await container.read(myAvatarInfoProvider.future);
      await pumpEventQueue();
      expect(calls.length, greaterThan(before));
    });
  });
}

/// 假登录态：不碰 chatServiceProvider（真 [AuthNotifier.build] 会 watch 它）。
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState();

  void setAuth(MiniAuth? auth, {bool busy = false}) =>
      state = AuthState(isLoggedIn: auth != null, auth: auth, isBusy: busy);
}

/// 记录被要了哪些资料接口的假客户端（不碰网络，也不走真缓存）。
class _CountingProfileClient extends ProfileClient {
  _CountingProfileClient(this.calls)
    : super(uin: 1, s2: 's', s2t: 't', dio: Dio(), baseUrl: 'https://h');

  final List<String> calls;

  @override
  Future<List<PlayerProfile>> getProfileBatch3(List<int> uins) async {
    calls.add('batch3:${uins.join(',')}');
    return const <PlayerProfile>[];
  }

  @override
  Future<Map<int, HeadSlot>> getPersonCenterHeadInfos(List<int> uins) async {
    calls.add('heads:${uins.join(',')}');
    return const <int, HeadSlot>{};
  }

  @override
  Future<Map<int, String?>> getPersonCenterHeadInfo(List<int> uins) async {
    calls.add('head1:${uins.join(',')}');
    return const <int, String?>{};
  }

  @override
  Future<PlayerProfile?> getMyProfile() async {
    calls.add('myProfile');
    return null;
  }

  @override
  Future<HeadInfo?> getMyHeadInfo() async {
    calls.add('myHead');
    return null;
  }
}
