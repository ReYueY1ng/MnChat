/// 登录页账号头像缓存：往返、重新登录不清缓存、脏数据降解，以及登录时的写入链路。
///
/// 登录页在**登录前**没有会话（拿不到 s2），头像只能读登录成功时缓存的这份展示
/// 信息（[SettingsStore.saveAccountAvatar] / [cacheAccountAvatar]）。存储往返用真实
/// 内存 Drift 库验证；登录链路用假 ChatService + 假资料客户端验证（不碰网络），
/// 同时挡住「在 AuthNotifier 里读依赖 authProvider 的 provider」造成的循环依赖。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/auth.dart' show MiniAuth;
import 'package:mnchat/core/services/chat_service.dart' show ChatService;
import 'package:mnchat/core/services/profile.dart'
    show PlayerProfile, ProfileClient;
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/core/storage/settings_store.dart';
import 'package:mnchat/state/providers.dart';

/// 固定返回一份资料的假客户端（不碰网络）。
class _FixedProfileClient extends ProfileClient {
  _FixedProfileClient(this.player)
    : super(uin: 7, s2: 's', s2t: 't', dio: Dio(), baseUrl: 'https://h');

  final PlayerProfile player;

  @override
  Future<Map<int, PlayerProfile>> fetchAvatarProfiles(List<int> uins) async => {
    for (final u in uins) u: player,
  };
}

/// 假 ChatService：登录直接成功，不碰网络。
class _FakeChatService extends ChatService {
  _FakeChatService(AppDatabase db) : super(db: db);

  @override
  Future<MiniAuth> login({required int uin, required String password}) async =>
      MiniAuth(
        uin: uin,
        apiId: 110,
        name: '甲',
        s2: 's2',
        s2t: 's2t',
        jwt: 'j',
      );
}

void main() {
  late AppDatabase db;
  late SettingsStore settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('登录成功后写缓存 → 账号列表能读回全部头像字段', () async {
    await settings.saveAccount(7, 'pwd', name: '甲');
    await settings.saveAccountAvatar(
      7,
      avatarUrl: 'http://cdn/diy.png',
      headType: 1,
      headId: 211,
      headFrameId: 100,
    );
    final accounts = await settings.listAccounts();
    expect(accounts, hasLength(1));
    expect(accounts.single.uin, 7);
    expect(accounts.single.avatarUrl, 'http://cdn/diy.png');
    expect(accounts.single.headType, 1);
    expect(accounts.single.headId, 211);
    expect(accounts.single.headFrameId, 100);
  });

  test('没有 DIY 头像时存的是角色头像本体（url 为 null）', () async {
    await settings.saveAccount(7, 'pwd');
    await settings.saveAccountAvatar(7, headType: 4, headId: 2);
    final a = (await settings.listAccounts()).single;
    expect(a.avatarUrl, isNull);
    expect(a.headType, 4);
    expect(a.headId, 2);
  });

  test('重新登录（saveAccount）不冲掉已缓存的头像', () async {
    await settings.saveAccount(7, 'pwd', name: '甲');
    await settings.saveAccountAvatar(7, headType: 4, headId: 2, headFrameId: 9);
    await settings.saveAccount(7, 'pwd2', name: '甲');
    final a = (await settings.listAccounts()).single;
    expect(a.password, 'pwd2', reason: '密码要更新');
    expect(a.headType, 4);
    expect(a.headId, 2);
    expect(a.headFrameId, 9);
  });

  test('四个值全空不写（不把已有缓存清成空）', () async {
    await settings.saveAccount(7, 'pwd');
    await settings.saveAccountAvatar(7, headType: 4, headId: 2);
    await settings.saveAccountAvatar(7);
    expect((await settings.listAccounts()).single.headId, 2);
  });

  test('uin 不在账号列表里 → 忽略，不凭空建账号', () async {
    await settings.saveAccount(7, 'pwd');
    await settings.saveAccountAvatar(8, headType: 4, headId: 2);
    final accounts = await settings.listAccounts();
    expect(accounts, hasLength(1));
    expect(accounts.single.uin, 7);
    expect(accounts.single.headId, isNull);
  });

  test('旧账号记录没有头像字段 → null，不抛', () async {
    await settings.saveAccount(7, 'pwd', name: '甲');
    final raw = await settings.getString(SettingsKeys.accounts);
    final list = (jsonDecode(raw!) as List).cast<Map<Object?, Object?>>();
    for (final k in SavedAccount.avatarKeys) {
      list.first.remove(k);
    }
    await settings.setString(SettingsKeys.accounts, jsonEncode(list));

    final a = (await settings.listAccounts()).single;
    expect(a.avatarUrl, isNull);
    expect(a.headType, isNull);
    expect(a.headId, isNull);
    expect(a.headFrameId, isNull);
  });

  test('账号 JSON 损坏 → 空列表，不抛', () async {
    await settings.setString(SettingsKeys.accounts, '{不是 json');
    expect(await settings.listAccounts(), isEmpty);
  });

  test('SavedAccount.fromJson：缺失 / 脏字符串 / 数字串都按约定降解', () {
    final missing = SavedAccount.fromJson({'uin': 7, 'pwd': 'x'});
    expect(missing.headType, isNull);
    expect(missing.headId, isNull);
    expect(missing.headFrameId, isNull);
    expect(missing.avatarUrl, isNull);

    final dirty = SavedAccount.fromJson({
      'uin': 7,
      'pwd': 'x',
      'head_type': 'abc',
      'head_id': '',
      'avatar_url': '',
    });
    expect(dirty.headType, isNull);
    expect(dirty.headId, isNull);
    expect(dirty.avatarUrl, isNull);

    final numeric = SavedAccount.fromJson({
      'uin': 7,
      'pwd': 'x',
      'head_type': '4',
      'head_id': 2,
      'head_frame_id': '100',
    });
    expect(numeric.headType, 4);
    expect(numeric.headId, 2);
    expect(numeric.headFrameId, 100);
  });

  group('cacheAccountAvatar：展示规则与落库', () {
    test('DIY 自定义头像 → 存 URL，本体为空', () async {
      await settings.saveAccount(7, 'pwd');
      await cacheAccountAvatar(
        _FixedProfileClient(
          const PlayerProfile(
            uin: 7,
            nickname: '甲',
            avatarUrl: 'http://cdn/diy.png',
            headType: 4,
            headId: 2,
          ),
        ),
        settings,
        uin: 7,
      );
      final a = (await settings.listAccounts()).single;
      expect(a.avatarUrl, 'http://cdn/diy.png');
      expect(a.headType, isNull, reason: 'AvatarView 有 URL 就不看本体，缓存也该是一致的');
    });

    test('无 DIY → 存角色头像本体与头像框', () async {
      await settings.saveAccount(7, 'pwd');
      await cacheAccountAvatar(
        _FixedProfileClient(
          const PlayerProfile(
            uin: 7,
            nickname: '甲',
            headType: 4,
            headId: 2,
            headFrameId: 100,
          ),
        ),
        settings,
        uin: 7,
      );
      final a = (await settings.listAccounts()).single;
      expect(a.avatarUrl, isNull);
      expect(a.headType, 4);
      expect(a.headId, 2);
      expect(a.headFrameId, 100);
    });

    test('没有可用头像 → 不写，保留已有缓存', () async {
      await settings.saveAccount(7, 'pwd');
      await settings.saveAccountAvatar(7, headType: 4, headId: 2);
      await cacheAccountAvatar(
        _FixedProfileClient(const PlayerProfile(uin: 7, nickname: '甲')),
        settings,
        uin: 7,
      );
      expect((await settings.listAccounts()).single.headId, 2);
    });
  });

  test('AuthNotifier.login：经工厂 provider 缓存头像，不触发循环依赖', () async {
    var factoryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        accountAvatarClientFactoryProvider.overrideWithValue((auth) {
          factoryCalls++;
          return _FixedProfileClient(
            const PlayerProfile(
              uin: 7,
              nickname: '甲',
              headType: 4,
              headId: 2,
              headFrameId: 100,
            ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final ok = await container
        .read(authProvider.notifier)
        .login(uin: 7, password: 'pwd');
    expect(ok, isTrue, reason: '缓存头像失败不能反过来让登录失败');
    await pumpEventQueue();
    expect(
      factoryCalls,
      1,
      reason: '必须经工厂 provider 构建缓存客户端：在 AuthNotifier 里读 '
          'profileClientProvider 会形成循环依赖（实测 CircularDependencyError）',
    );

    final a = (await SettingsStore(db).listAccounts()).single;
    expect(a.uin, 7);
    expect(a.headType, 4);
    expect(a.headId, 2);
    expect(a.headFrameId, 100);
    expect(a.avatarUrl, isNull);
  });
}
