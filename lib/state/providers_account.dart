part of 'providers.dart';

// ── 认证状态 ─────────────────────────────────────────────────────────────

class AuthState {
  final bool isLoggedIn;
  final MiniAuth? auth;
  final bool isBusy;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.auth,
    this.isBusy = false,
    this.error,
  });

  /// 值相等。
  ///
  /// [AuthNotifier] 每次收到 ChatService 的状态事件都会 `state = _stateFrom(...)`，
  /// 而登录/重连本身会连着发好几个状态（authenticating → connectingChatPush →
  /// connected）；没有这层判断，`watch(authProvider)` 的每个 client provider 都会
  /// 重建，依赖它们的网络 provider 也就跟着重跑一遍（同一份数据重复请求）。
  /// [auth] 用默认的同一个实例比较（`MiniAuth` 没有值相等）：换账号/重登录必然是
  /// 新实例，同一会话内的状态抖动则复用同一实例。
  @override
  bool operator ==(Object other) =>
      other is AuthState &&
      other.isLoggedIn == isLoggedIn &&
      other.isBusy == isBusy &&
      other.error == error &&
      other.auth == auth;

  @override
  int get hashCode => Object.hash(isLoggedIn, isBusy, error, auth);
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<ChatServiceState>? _sub;

  @override
  AuthState build() {
    final service = ref.watch(chatServiceProvider);
    _sub ??= service.stateStream.listen((s) => state = _stateFrom(service));
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    // 同步读取 service 当前状态作为初始值：service 可能已处于 connected
    // （如自动登录已发起），只等流事件会漏掉初始态导致 UI 误判未登录。
    return _stateFrom(service);
  }

  AuthState _stateFrom(ChatService service) {
    final s = service.state;
    final loggedIn =
        s == ChatServiceState.connected ||
        s == ChatServiceState.connectingChatPush;
    return AuthState(
      isLoggedIn: loggedIn,
      auth: service.auth,
      isBusy: s == ChatServiceState.authenticating,
      error: s == ChatServiceState.error ? service.lastError : null,
    );
  }

  /// 登录；成功返回 true。
  /// 成功后账号总是加入本地账号列表（切换账号用）；自动登录凭据仅当
  /// autoLogin 开启时保存（决定下次启动是否免登录）。
  Future<bool> login({
    required int uin,
    required String password,
    String? name,
  }) async {
    final service = ref.read(chatServiceProvider);
    state = const AuthState(isBusy: true);
    try {
      final auth = await service.login(uin: uin, password: password);
      state = AuthState(isLoggedIn: true, auth: auth);
      final settings = ref.read(settingsProvider);
      // 账号列表：记录昵称（登录成功即有 auth.name）
      await settings.saveAccount(uin, password, name: name ?? auth.name);
      // 自动登录开启时保存当前凭据，下次启动免登录
      final autoLogin = await settings.getBool(SettingsKeys.autoLogin);
      if (autoLogin) {
        await settings.saveCredentials(uin, password);
      }
      return true;
    } catch (e) {
      state = AuthState(error: e.toString());
      return false;
    }
  }

  /// 启动自动登录：设置开启且有已存凭据 → 登录。返回是否发起了登录。
  Future<bool> autoLogin() async {
    if (state.isLoggedIn || state.isBusy) return false;
    final settings = ref.read(settingsProvider);
    final enabled = await settings.getBool(SettingsKeys.autoLogin);
    if (!enabled) return false;
    final creds = await settings.loadCredentials();
    if (creds == null) return false;
    await login(uin: creds.uin, password: creds.password);
    return true;
  }

  void logout() {
    final service = ref.read(chatServiceProvider);
    // reset() 是 async：fire-and-forget，出错也交由内部处理，不阻塞登出流程
    unawaited(service.reset());
    // 换账号：关闭当前打开的会话 + 清空聊天控制器，防止旧账号消息残留
    ref.read(activeSessionProvider.notifier).close();
    ref.read(chatBridgeProvider).reset();
    state = const AuthState();
  }
}


// ── 当前会话 ─────────────────────────────────────────────────────────────

class ActiveSession {
  final ChatSessionType type;
  final int id;

  const ActiveSession(this.type, this.id);

  @override
  bool operator ==(Object other) =>
      other is ActiveSession && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

final activeSessionProvider =
    NotifierProvider<ActiveSessionNotifier, ActiveSession?>(
      ActiveSessionNotifier.new,
    );

class ActiveSessionNotifier extends Notifier<ActiveSession?> {
  @override
  ActiveSession? build() => null;

  void open(ChatSessionType type, int id) => state = ActiveSession(type, id);
  void close() => state = null;
}


/// 直接 `watch(chatServiceProvider).myUin` 时，依赖（单例 ChatService 实例）
/// 永不变化 → 切账号后 provider 不重建、永远返回**旧账号** uin，导致
/// newMsg 的 authorId 与新 currentUserId 不匹配，flutter_chat_ui 把"我发的"
/// 判成"对方发的"（消息显示成旧账号发的）。
final myUinProvider = Provider<int>((ref) {
  final auth = ref.watch(authProvider);
  return auth.auth?.uin ?? 0;
});

/// 本人头像资料（聊天页给自己的消息显示头像用）。
class MyAvatarInfo {
  /// 昵称（登录返回；可能为空）。
  final String name;

  /// 头像 URL（DIY 自定义头像优先）。
  final String? avatarUrl;

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）。
  final int? headType;
  final int? headId;

  /// 头像框 id。
  final int? frameId;

  const MyAvatarInfo({
    this.name = '',
    this.avatarUrl,
    this.headType,
    this.headId,
    this.frameId,
  });
}

/// 本人头像资料缓存：与资料页/好友资料同源。
///
/// 走的是**好友资料已在用的那套接口**（`getPersonCenterHeadInfos`，一次同时返回
/// DIY 自定义头像与头像本体 type/id；其中 `isSelf` 分支会放行本人审核中的
/// `pre_url`），头像框另由 `getMyProfile()` 下发（`HeadSlot` 里没有框）。
/// 失败不再静默吞掉 —— 写 warn 日志，便于从 logcat 定位成因为何头像/框没出来。
/// `FutureProvider` 自带缓存，聊天页逐条消息读取不会重复请求。
final myAvatarInfoProvider = FutureProvider<MyAvatarInfo>((ref) async {
  // 只依赖账号本身（select）：登录 / 重连会连着发好几个 AuthState（busy、
  // connectingChatPush、connected），watch 整个状态会让本 provider 反复重跑 ——
  // 表现就是「进 App 后自己的资料被多次获取」。
  final auth = ref.watch(authProvider.select((a) => a.auth));
  final name = auth?.name ?? '';
  if (auth == null) return MyAvatarInfo(name: name);
  // 复用共享客户端：它带资料缓存（ProfileClient.cacheTtl），与自己的资料页同源
  // 同实例，不再各自去拉人物中心 / 批量资料。
  final client = ref.watch(profileClientProvider);
  if (client == null) return MyAvatarInfo(name: name);
  const tag = 'myAvatarInfo';

  // ① 人物中心：DIY 自定义头像 + 头像本体 type/id（isSelf 分支会放行审核中的 pre_url）
  HeadSlot? slot;
  try {
    slot = (await client.getPersonCenterHeadInfos([auth.uin]))[auth.uin];
  } catch (e) {
    log.warn('getPersonCenterHeadInfos 失败: $e', tag: tag);
  }
  // ① 本人资料：`getMyProfile` 是对「本人」最可靠的端点 —— 资料页的头像框就是它
  //    给的（用户实测资料页有框），说明这条通。`getProfileBatch3` 对部分账号**不
  //    返回自己**，只作兜底。
  PlayerProfile? profile;
  try {
    profile = await client.getMyProfile();
  } catch (e) {
    log.warn('getMyProfile 失败: $e', tag: tag);
  }
  // 批量资料只拉一次：下面「资料兜底」与「头像 URL 兜底」原先各拉一次同一个
  // `getProfileBatch3([自己])`，正是「自己的信息被多次获取」的两次。
  Future<PlayerProfile?>? batch3Once;
  Future<PlayerProfile?> batch3Self() => batch3Once ??= () async {
    try {
      final list = await client.getProfileBatch3([auth.uin]);
      return list.isEmpty ? null : list.first;
    } catch (e) {
      log.warn('getProfileBatch3 失败: $e', tag: tag);
      return null;
    }
  }();

  profile ??= await batch3Self();
  // ② 头像本体：`getMyHeadInfo` 是本人专用端点；人物中心那个作兜底（还带 DIY）
  int? headType = slot?.type;
  int? headId = slot?.id;
  if (headType == null || headId == null) {
    try {
      final head = await client.getMyHeadInfo();
      if (head != null) {
        headType ??= head.type;
        headId ??= head.id;
      }
    } catch (e) {
      log.warn('getMyHeadInfo 失败: $e', tag: tag);
    }
  }
  // ③ 头像 URL：本人资料里的 avatarUrl 可能是空的，而 `getProfileBatch3`
  //    （好友头像正是靠它）会给到 per-user 的网络头像 —— 实测好友都有值。
  //    两条都试，取到为止。
  var avatarUrl = slot?.diyUrl ?? profile?.avatarUrl;
  if (avatarUrl == null || avatarUrl.isEmpty) {
    avatarUrl = (await batch3Self())?.avatarUrl;
  }
  // 人物中心缺失 / type=2（头套无 2D 资源）时用资料 SkinID/Model 回退角色头像
  final fallback = PlayerProfile.resolveRoleHeadFallback(
    headType: headType,
    headId: headId,
    skinId: profile?.headSkinId,
    model: profile?.headModel,
  );
  // DIY 自定义头像是显式选择，必须压过角色头像（AvatarView 本体优先于 URL，
  // 故有 DIY 时把本体清空），规则与好友资料一致（见 _fetchFriendInfos）。
  final useDiy = slot?.diyUrl != null;
  // 没有 DIY 时按官方 `GetPlayerHeadPath` 展示角色头像本体，而不是资料里的
  // `header*` 网络头像（那是别人的"自定义头像"假象的来源）。
  final roleHeadWins =
      !useDiy && PlayerProfile.roleHeadHasLocalIcon(fallback);
  final nickname = profile?.nickname ?? '';
  final info = MyAvatarInfo(
    name: nickname.isNotEmpty ? nickname : name,
    avatarUrl: roleHeadWins ? null : avatarUrl,
    headType: useDiy ? null : (fallback?.type ?? headType),
    headId: useDiy ? null : (fallback?.id ?? headId),
    frameId: profile?.headFrameId,
  );
  log.debug(
    '本人头像资料: name=${info.name} head=${info.headType}/${info.headId} '
    'frame=${info.frameId} avatar=${(info.avatarUrl ?? '').isEmpty ? "无" : "有"}',
    tag: tag,
  );
  return info;
});

