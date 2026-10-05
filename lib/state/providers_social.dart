part of 'providers.dart';

// ── 消息中心 / 互动通知 ─────────────────────────────────────────────────

/// 消息中心（/miniw/msgcenter）客户端（未登录返回 null）。
final messageCenterClientProvider = Provider<MessageCenterClient?>((ref) {
  final auth = ref.watch(authProvider).auth;
  if (auth == null) return null;
  return MessageCenterClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
});

/// 互动通知（/miniw/msg_box，顶部 3 入口 + 动态助手频道）客户端。
final msgBoxClientProvider = Provider<MsgBoxClient?>((ref) {
  final auth = ref.watch(authProvider).auth;
  if (auth == null) return null;
  return MsgBoxClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
});

/// 动态客户端（消息中心 `详情` 跳转动态详情用；未登录返回 null）。
final dynamicsClientProvider = Provider<DynamicsClient?>((ref) {
  final auth = ref.watch(authProvider).auth;
  if (auth == null) return null;
  return DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
});

/// 资料客户端（互动通知列表头像补全；未登录返回 null）。
final profileClientProvider = Provider<ProfileClient?>((ref) {
  final auth = ref.watch(authProvider).auth;
  if (auth == null) return null;
  return ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
});

/// 地图信息客户端（作品互动卡片的作品名；未登录返回 null）。
final mapInfoClientProvider = Provider<MapInfoClient?>((ref) {
  final auth = ref.watch(authProvider).auth;
  if (auth == null) return null;
  return MapInfoClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
});


// ── 请求失败提示 ────────────────────────────────────────────────────────

/// 请求失败总线：UI（角标 + 详情弹窗 + 吐司）用它显示「哪个请求失败了」。
///
/// 业务码失败由各 client 上报（见 [PartnerClient]），传输层失败由 `createDio`
/// 的拦截器上报；测试可 override 成干净实例。
final requestErrorBusProvider = Provider<RequestErrorBus>(
  (ref) => RequestErrorBus.instance,
);


// ── 最佳拍档 / 玩家等级 / 大会员 ─────────────────────────────────────────

/// 拍档/等级/大会员客户端（未登录返回 null）。
final partnerClientProvider = Provider<PartnerClient?>((ref) {
  final auth = ref.watch(authProvider).auth;
  if (auth == null) return null;
  return PartnerClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
});

/// 安全获取拍档客户端：测试等环境未注入认证时返回 null，让派生 provider
/// 退化为空数据，而不是把异常抛给 UI。
PartnerClient? _tryPartnerClient(Ref ref) {
  try {
    return ref.watch(partnerClientProvider);
  } catch (_) {
    return null;
  }
}

/// 忽略失败的异步读取：网络/解析异常时退回 [fallback]。
Future<T> _partnerGuard<T>(Ref ref, String label, Future<T> Function() run, T fallback) async {
  try {
    return await run();
  } catch (e) {
    // 静默降级会让"默契度全是 0"看起来像服务端没数据 —— 日志 + UI 都要能看到。
    log.warn('拍档目录部分数据拉取失败: $e', tag: 'Partner');
    ref.read(requestErrorBusProvider).report(label: label, endpoint: '', message: '$e');
    return fallback;
  }
}

/// 会话可见好友的等级 / 拍档 / 大会员聚合缓存。
///
/// 一次批量拉取（等级 + 拍档列表 + 大会员），随会话流变化重算；未登录或
/// 数据未就绪时返回 [PartnerDirectory.empty]，行 UI 自动降级为无徽标。
final partnerDirectoryProvider = FutureProvider<PartnerDirectory>((ref) async {
  final snap = ref.watch(sessionListProvider).asData?.value;
  if (snap == null) return PartnerDirectory.empty;
  final uins = <int>{
    for (final s in snap.sessions)
      if (s.type == ChatSessionType.friend && s.id > 0) s.id,
  }.toList();
  if (uins.isEmpty) return PartnerDirectory.empty;
  final client = _tryPartnerClient(ref);
  if (client == null) return PartnerDirectory.empty;
  final levels = await _partnerGuard(
    ref,
    '平台等级',
    () => client.getPlatformLevels(uins),
    const <int, int>{},
  );
  final partners = await _partnerGuard(
    ref,
    '拍档列表',
    () => client.getPartnerList(),
    const <PartnerInfo>[],
  );
  final vip = await _partnerGuard(
    ref,
    '大会员',
    () => client.getVipExpiry(uins),
    const <int, int>{},
  );
  return PartnerDirectory(
    levels: levels,
    partners: {for (final p in partners) p.bestUin: p},
    vipExpiry: vip,
  );
});

/// 本人**拍档**列表（只含已建立关系的 `lab > 0`）。
///
/// 注意：`get_list` 会给每个好友都下发一条带 `tacitnum` 的记录，没建立关系的
/// `lab == 0`（只有默契值）——那些不算拍档，不能进这个列表（否则「可建立拍档数」
/// 会算错、头像/等级也会多拉一批）。只有默契值的好友见 [partnerDirectoryProvider]。
final myPartnerListProvider = FutureProvider<List<PartnerInfo>>((ref) async {
  final client = _tryPartnerClient(ref);
  if (client == null) return const <PartnerInfo>[];
  final all = await _partnerGuard(
    ref,
    '拍档列表',
    () => client.getPartnerList(),
    const <PartnerInfo>[],
  );
  return all.where((p) => PartnerLab.isPartnerLab(p.lab)).toList();
});

/// 本人拍档槽位（可建立拍档数上限）。
final partnerSlotProvider = FutureProvider<PartnerSlotInfo?>((ref) async {
  final uin = ref.watch(myUinProvider);
  final client = _tryPartnerClient(ref);
  if (client == null || uin <= 0) return null;
  return _partnerGuard(ref, '拍档槽位', () => client.getPartnerSlot(uin), null);
});

/// 拍档红点数量。
final partnerRedDotProvider = FutureProvider<int>((ref) async {
  final client = _tryPartnerClient(ref);
  if (client == null) return 0;
  return _partnerGuard(ref, '拍档红点', () => client.getRedDotCount(), 0);
});

/// 本人拍档的平台等级（拍档页 `Lv<N>`）。
final partnerLevelsProvider = FutureProvider<Map<int, int>>((ref) async {
  final partners = await ref.watch(myPartnerListProvider.future);
  if (partners.isEmpty) return const <int, int>{};
  final client = _tryPartnerClient(ref);
  if (client == null) return const <int, int>{};
  final uins = partners.map((p) => p.bestUin).toList();
  return _partnerGuard(
    ref,
    '平台等级',
    () => client.getPlatformLevels(uins),
    const <int, int>{},
  );
});

/// 关系等级阈值（`FriendSystem.levelIntimacy.partnerLevel_list`）。
///
/// 服务端 visual-cfg，进程内缓存（[PartnerClient.getPartnerLevels]）；未登录 /
/// 拉取失败 → 空列表，行 UI 与拍档卡片自动降级为「不画进度条」。
final partnerLevelConfigProvider =
    FutureProvider<List<(int level, int intimacyValue)>>((ref) async {
      final client = _tryPartnerClient(ref);
      if (client == null) return const <(int, int)>[];
      return _partnerGuard(
        ref,
        '关系等级配置',
        () => client.getPartnerLevels(),
        const <(int, int)>[],
      );
    });

/// 好友标签池（服务端 `query_friend_label_pool`）。
///
/// 增删标签 / 给好友打标签之后 `ref.invalidate(friendTagPoolProvider)` 刷新。
final friendTagPoolProvider = FutureProvider<List<FriendTag>>((ref) async {
  try {
    final svc = ref.watch(chatServiceProvider);
    return parseFriendTagPool(await svc.friendLabelPool());
  } catch (_) {
    return const <FriendTag>[];
  }
});

/// 交友宣言标签表（服务端 visual-cfg `FriendShipDeclaration`）。
///
/// 「想要…/喜欢…」的文案**由服务端下发**，不是客户端写死的；拉不到时返回空目录，
/// 调用方回退内置表（见 `core/services/social_sign.dart`）。
final declarationCatalogProvider = FutureProvider<DeclarationCatalog>((ref) async {
  return DeclarationConfigClient().catalog();
});

/// 本人拍档的资料（昵称 / 头像 / 头像框），供拍档卡片渲染。
final partnerProfilesProvider =
    FutureProvider<Map<int, PlayerProfile>>((ref) async {
      final partners = await ref.watch(myPartnerListProvider.future);
      if (partners.isEmpty) return const <int, PlayerProfile>{};
      final auth = ref.watch(authProvider).auth;
      if (auth == null) return const <int, PlayerProfile>{};
      final uins = partners.map((p) => p.bestUin).toList();
      final out = <int, PlayerProfile>{};
      try {
        final client = ProfileClient(
          uin: auth.uin,
          s2: auth.s2,
          s2t: auth.s2t,
        );
        for (var i = 0; i < uins.length; i += 20) {
          final end = (i + 20) < uins.length ? i + 20 : uins.length;
          final batch = uins.sublist(i, end);
          for (final p in await client.getProfileBatch3(batch)) {
            out[p.uin] = p;
          }
        }
      } catch (_) {
        // 资料拉取失败：卡片退回迷你号 + 首字头像。
      }
      return out;
    });
