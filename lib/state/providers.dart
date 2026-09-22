/// Riverpod 提供者 —— 把 ChatService 暴露给 UI 层。
/// 使用 riverpod 3.x 的 Notifier API（StateNotifier/StateProvider 已在 3.x 移除）。
library;

import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_bridge.dart';
import '../core/models/messages.dart';
import '../core/services/auth.dart';
import '../core/services/chat_service.dart';
import '../core/services/dynamics.dart';
import '../core/services/message_center.dart';
import '../core/services/msg_box.dart';
import '../core/services/notification_service.dart';
import '../core/services/partner.dart';
import '../core/services/profile.dart';
import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/settings_store.dart' show SettingsKeys, SettingsStore;
import '../core/utils/avatar_debug.dart';
import '../core/utils/log.dart';

/// ChatService 单例（注入本地 SQLite 用于持久化；main() 中 override databaseProvider）。
final chatServiceProvider = Provider<ChatService>((ref) {
  final db = ref.read(databaseProvider);
  final service = ChatService(db: db);
  ref.onDispose(service.dispose);
  return service;
});

/// ChatBridge 单例（flutter_chat_ui 迁移的桥接层）。
///
/// 持有每个会话的 [ChatController]，订阅 ChatService.eventStream 单一订阅，
/// 把历史增量 reconcile 到控制器。已取代 messageHistoryProvider 的消息显示链路。
final chatBridgeProvider = Provider<ChatBridge>((ref) {
  final service = ref.watch(chatServiceProvider);
  final bridge = ChatBridge(service);
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// AppDatabase 单例（main() 中用 drift_flutter 构建后 override）。
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('AppDatabase must be created in main()'),
);

/// 应用设置存储（自动登录凭据等）单例 —— 基于 Drift 设置表（Web/原生统一）。
final settingsProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.read(databaseProvider)),
);

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

// ── 数据流 ───────────────────────────────────────────────────────────────

/// 会话列表（由 ChatService.sessionStream 驱动）。
final sessionListProvider = StreamProvider<SessionSnapshot>((ref) {
  final service = ref.watch(chatServiceProvider);
  return service.sessionStream;
});

/// 联系人列表。
final contactsProvider = StreamProvider<List<Contact>>((ref) {
  final service = ref.watch(chatServiceProvider);
  return service.sessionStream.map((snap) => snap.contacts);
});

/// 待处理好友申请列表（由 applyed_notify 推送驱动）。
final friendRequestStreamProvider = StreamProvider<List<FriendRequest>>((ref) {
  final service = ref.watch(chatServiceProvider);
  return service.friendRequestStream;
});

/// 待处理好友申请数（红点）。
final friendRequestCountProvider = Provider<int>((ref) {
  ref.watch(friendRequestStreamProvider);
  return ref.watch(chatServiceProvider).friendRequestCount;
});

/// 会话排序方式。
enum SessionSortMode {
  time('time', '按时间'),
  name('name', '按名称'),
  unread('unread', '按未读');

  const SessionSortMode(this.key, this.label);
  final String key;
  final String label;

  static SessionSortMode fromKey(String? k) => SessionSortMode.values
      .firstWhere((m) => m.key == k, orElse: () => SessionSortMode.time);
}

/// 会话排序方式（持久化到设置）。
final sessionSortModeProvider =
    NotifierProvider<SessionSortModeNotifier, SessionSortMode>(
      SessionSortModeNotifier.new,
    );

class SessionSortModeNotifier extends Notifier<SessionSortMode> {
  @override
  SessionSortMode build() {
    // 初始化：从设置读取（异步；provider 可能先被 dispose，用 ref.mounted 保护）
    ref
        .read(settingsProvider)
        .getString(SettingsKeys.sortMode)
        .then((k) {
          if (!ref.mounted) return;
          final m = SessionSortMode.fromKey(k);
          if (m != state) state = m;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return SessionSortMode.time;
  }

  Future<void> setMode(SessionSortMode mode) async {
    state = mode;
    await ref.read(settingsProvider).setString(SettingsKeys.sortMode, mode.key);
  }
}

/// 应用主题模式（跟随系统 / 浅色 / 深色），持久化到设置。
enum AppThemeMode {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色');

  const AppThemeMode(this.key, this.label);
  final String key;
  final String label;

  static AppThemeMode fromKey(String? k) => AppThemeMode.values.firstWhere(
    (m) => m.key == k,
    orElse: () => AppThemeMode.system,
  );
}

/// 主题模式（持久化到设置）。
final appThemeModeProvider =
    NotifierProvider<AppThemeModeNotifier, AppThemeMode>(
      AppThemeModeNotifier.new,
    );

class AppThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    ref
        .read(settingsProvider)
        .getString(SettingsKeys.themeMode)
        .then((k) {
          if (!ref.mounted) return;
          final m = AppThemeMode.fromKey(k);
          if (m != state) state = m;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return AppThemeMode.system;
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    await ref
        .read(settingsProvider)
        .setString(SettingsKeys.themeMode, mode.key);
  }
}

/// 新消息通知开关（运行时即时生效，持久化到设置）。
final notifyEnabledProvider = NotifierProvider<NotifyEnabledNotifier, bool>(
  NotifyEnabledNotifier.new,
);

class NotifyEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref
        .read(settingsProvider)
        .getBool(SettingsKeys.notifyEnabled, fallback: true)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsProvider).setBool(SettingsKeys.notifyEnabled, value);
  }
}

/// 后台保活开关（前台服务维持长连接，后台也能收推送），持久化到设置。
/// 默认开启：与旧行为一致（进入主界面即启动前台服务）。
final keepAliveProvider = NotifierProvider<KeepAliveNotifier, bool>(
  KeepAliveNotifier.new,
);

class KeepAliveNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref
        .read(settingsProvider)
        .getBool(SettingsKeys.keepAlive, fallback: true)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {
          // 设置读取失败保持默认值
        });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsProvider).setBool(SettingsKeys.keepAlive, value);
  }
}

/// 已登录用户 uin（供聊天页判断消息方向）。
///
/// 必须从 [authProvider]（Notifier）派生而非直接读 chatServiceProvider：
/// 通知服务：按平台选择实现（Android 原生 / Linux dbus / 其他 Noop）。
///
/// 单元测试环境不会碰到原生通道或 dbus —— Noop 实现什么都不做、也不抛异常。
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => createNotificationService(),
);

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
  final auth = ref.watch(authProvider).auth;
  final name = auth?.name ?? '';
  if (auth == null) return MyAvatarInfo(name: name);
  final client = ProfileClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
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
  if (profile == null) {
    try {
      final list = await client.getProfileBatch3([auth.uin]);
      if (list.isNotEmpty) profile = list.first;
    } catch (e) {
      log.warn('getProfileBatch3 失败: $e', tag: tag);
    }
  }
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
    try {
      final list = await client.getProfileBatch3([auth.uin]);
      if (list.isNotEmpty) avatarUrl = list.first.avatarUrl;
    } catch (e) {
      log.warn('getProfileBatch3(本人头像) 失败: $e', tag: tag);
    }
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
  final nickname = profile?.nickname ?? '';
  final info = MyAvatarInfo(
    name: nickname.isNotEmpty ? nickname : name,
    avatarUrl: avatarUrl,
    headType: useDiy ? null : (fallback?.type ?? headType),
    headId: useDiy ? null : (fallback?.id ?? headId),
    frameId: profile?.headFrameId,
  );
  // 临时诊断（见 core/utils/avatar_debug.dart）
  avatarDebug(
    'self slot(diy=${slot?.diyUrl}, type=${slot?.type}, id=${slot?.id}) '
    'profile(name=${profile?.nickname}, avatar=${profile?.avatarUrl}, '
    'frame=${profile?.headFrameId}, head=${profile?.headType}/${profile?.headId}, '
    'skin=${profile?.headSkinId}, model=${profile?.headModel})',
  );
  avatarDebug(
    'self resolved name=${info.name} avatar=${(info.avatarUrl ?? "").isEmpty ? "无" : info.avatarUrl} '
    'head=${info.headType}/${info.headId} frame=${info.frameId}',
  );
  log.debug(
    '本人头像资料: name=${info.name} head=${info.headType}/${info.headId} '
    'frame=${info.frameId} avatar=${(info.avatarUrl ?? '').isEmpty ? "无" : "有"}',
    tag: tag,
  );
  return info;
});

// ── 通用设置（显示 / 输入 / 隐私 / 桌面端）────────────────────────────────

/// 安全获取设置存储：测试等环境未注入 databaseProvider 时返回 null，
/// 让设置类 provider 退化为默认值，而不是把异常抛给 UI。
SettingsStore? _trySettings(Ref ref) {
  try {
    return ref.read(settingsProvider);
  } catch (_) {
    return null;
  }
}

/// 布尔类设置的通用基类：读 [key]，默认值 [fallback]，写入即时生效。
abstract class _BoolSettingNotifier extends Notifier<bool> {
  String get key;
  bool get fallback;

  @override
  bool build() {
    _trySettings(ref)
        ?.getBool(key, fallback: fallback)
        .then((v) {
          if (!ref.mounted) return;
          if (v != state) state = v;
        })
        .catchError((Object _) {
          // 读取失败保持默认值
        });
    return fallback;
  }

  Future<void> set(bool value) async {
    state = value;
    await _trySettings(ref)?.setBool(key, value);
  }
}

/// 头像框动画开关：关闭后仅使用静态 PNG（省电 / 省流）。
final animatedFramesProvider = NotifierProvider<AnimatedFramesNotifier, bool>(
  AnimatedFramesNotifier.new,
);

class AnimatedFramesNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.animatedFrames;
  @override
  bool get fallback => true;
}

/// 富文本显示原文本：开启后昵称 / 消息名原样显示标签串
/// （如 `[i][color][b]顾念`），不再解析颜色 / 加粗 / 表情。
/// 默认关闭：与旧行为一致，展示解析后的富文本。
final richTextRawProvider = NotifierProvider<RichTextRawNotifier, bool>(
  RichTextRawNotifier.new,
);

class RichTextRawNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.richTextRaw;
  @override
  bool get fallback => false;
}

/// 回车发送（桌面端）。
final sendOnEnterProvider = NotifierProvider<SendOnEnterNotifier, bool>(
  SendOnEnterNotifier.new,
);

class SendOnEnterNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.sendOnEnter;
  @override
  bool get fallback => true;
}

/// 进入会话自动标记已读。
final autoMarkReadProvider = NotifierProvider<AutoMarkReadNotifier, bool>(
  AutoMarkReadNotifier.new,
);

class AutoMarkReadNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.autoMarkRead;
  @override
  bool get fallback => true;
}

/// 通知隐藏内容（锁屏仅提示"有新消息"，不显示正文）。
final hideNotifyContentProvider =
    NotifierProvider<HideNotifyContentNotifier, bool>(
      HideNotifyContentNotifier.new,
    );

class HideNotifyContentNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.hideNotifyContent;
  @override
  bool get fallback => false;
}

/// 免打扰时段开关。
final dndEnabledProvider = NotifierProvider<DndEnabledNotifier, bool>(
  DndEnabledNotifier.new,
);

class DndEnabledNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.dndEnabled;
  @override
  bool get fallback => false;
}

/// 关闭到托盘（仅桌面端生效）。
final closeToTrayProvider = NotifierProvider<CloseToTrayNotifier, bool>(
  CloseToTrayNotifier.new,
);

class CloseToTrayNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.closeToTray;
  @override
  bool get fallback => true;
}

/// 应用锁开关。
final lockEnabledProvider = NotifierProvider<LockEnabledNotifier, bool>(
  LockEnabledNotifier.new,
);

class LockEnabledNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.lockEnabled;
  @override
  bool get fallback => false;
}

/// 访问主页留下踪迹：关闭后不再向对方发送访问记录。
/// 默认开启 —— 与官方客户端一致（playercenterv2datamanager.lua 中
/// `if layoutInfo.VisitRecord == nil then layoutInfo.VisitRecord = true end`）。
final leaveVisitTraceProvider =
    NotifierProvider<LeaveVisitTraceNotifier, bool>(
      LeaveVisitTraceNotifier.new,
    );

class LeaveVisitTraceNotifier extends _BoolSettingNotifier {
  @override
  String get key => SettingsKeys.leaveVisitTrace;
  @override
  bool get fallback => true;
}

/// 聊天字号缩放（[ChatFontScaleNotifier.min] ~ [ChatFontScaleNotifier.max]）。
final chatFontScaleProvider =
    NotifierProvider<ChatFontScaleNotifier, double>(ChatFontScaleNotifier.new);

class ChatFontScaleNotifier extends Notifier<double> {
  static const double min = 0.8;
  static const double max = 1.6;

  @override
  double build() {
    _trySettings(ref)
        ?.getDouble(SettingsKeys.chatFontScale)
        .then((v) {
          if (!ref.mounted) return;
          if (v != null) {
            final c = v.clamp(min, max);
            if (c != state) state = c;
          }
        })
        .catchError((Object _) {});
    return 1.0;
  }

  Future<void> set(double value) async {
    final v = value.clamp(min, max);
    state = v;
    await _trySettings(ref)?.setDouble(SettingsKeys.chatFontScale, v);
  }
}

/// 主题强调色（seed）。
final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);

class AccentColorNotifier extends Notifier<Color> {
  /// 品牌 seed（与 `AppColors.brandSeed` 一致；内联以避免 state→ui 层依赖）。
  static const Color defaultSeed = Color(0xFF108850);

  @override
  Color build() {
    _trySettings(ref)
        ?.getInt(SettingsKeys.seedColor)
        .then((v) {
          if (!ref.mounted || v == null) return;
          final c = Color(v);
          if (c != state) state = c;
        })
        .catchError((Object _) {});
    return defaultSeed;
  }

  Future<void> set(Color c) async {
    state = c;
    await _trySettings(ref)?.setInt(SettingsKeys.seedColor, c.toARGB32());
  }
}

/// 免打扰时段：起止为当天分钟数；[start] > [end] 表示跨午夜。
class DndWindow {
  final int start;
  final int end;
  const DndWindow({this.start = 22 * 60, this.end = 8 * 60});

  /// [now] 是否落在免打扰时段内。
  bool contains(DateTime now) {
    if (start == end) return false;
    final m = now.hour * 60 + now.minute;
    return start < end ? (m >= start && m < end) : (m >= start || m < end);
  }

  String get label => '${_hhmm(start)} - ${_hhmm(end)}';

  static String _hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

final dndWindowProvider = NotifierProvider<DndWindowNotifier, DndWindow>(
  DndWindowNotifier.new,
);

class DndWindowNotifier extends Notifier<DndWindow> {
  @override
  DndWindow build() {
    final settings = _trySettings(ref);
    settings
        ?.getInt(SettingsKeys.dndStart)
        .then((s) {
          if (!ref.mounted || s == null) return;
          state = DndWindow(start: s, end: state.end);
        })
        .catchError((Object _) {});
    settings
        ?.getInt(SettingsKeys.dndEnd)
        .then((e) {
          if (!ref.mounted || e == null) return;
          state = DndWindow(start: state.start, end: e);
        })
        .catchError((Object _) {});
    return const DndWindow();
  }

  Future<void> set(DndWindow w) async {
    state = w;
    final settings = _trySettings(ref);
    if (settings == null) return;
    await settings.setInt(SettingsKeys.dndStart, w.start);
    await settings.setInt(SettingsKeys.dndEnd, w.end);
  }
}

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
Future<T> _partnerGuard<T>(Future<T> Function() run, T fallback) async {
  try {
    return await run();
  } catch (_) {
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
    () => client.getPlatformLevels(uins),
    const <int, int>{},
  );
  final partners = await _partnerGuard(
    () => client.getPartnerList(),
    const <PartnerInfo>[],
  );
  final vip = await _partnerGuard(
    () => client.getVipExpiry(uins),
    const <int, int>{},
  );
  return PartnerDirectory(
    levels: levels,
    partners: {for (final p in partners) p.bestUin: p},
    vipExpiry: vip,
  );
});

/// 本人拍档列表。
final myPartnerListProvider = FutureProvider<List<PartnerInfo>>((ref) async {
  final client = _tryPartnerClient(ref);
  if (client == null) return const <PartnerInfo>[];
  return _partnerGuard(() => client.getPartnerList(), const <PartnerInfo>[]);
});

/// 本人拍档槽位（可建立拍档数上限）。
final partnerSlotProvider = FutureProvider<PartnerSlotInfo?>((ref) async {
  final uin = ref.watch(myUinProvider);
  final client = _tryPartnerClient(ref);
  if (client == null || uin <= 0) return null;
  return _partnerGuard(() => client.getPartnerSlot(uin), null);
});

/// 拍档红点数量。
final partnerRedDotProvider = FutureProvider<int>((ref) async {
  final client = _tryPartnerClient(ref);
  if (client == null) return 0;
  return _partnerGuard(() => client.getRedDotCount(), 0);
});

/// 本人拍档的平台等级（拍档页 `Lv<N>`）。
final partnerLevelsProvider = FutureProvider<Map<int, int>>((ref) async {
  final partners = await ref.watch(myPartnerListProvider.future);
  if (partners.isEmpty) return const <int, int>{};
  final client = _tryPartnerClient(ref);
  if (client == null) return const <int, int>{};
  final uins = partners.map((p) => p.bestUin).toList();
  return _partnerGuard(
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
        () => client.getPartnerLevels(),
        const <(int, int)>[],
      );
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
