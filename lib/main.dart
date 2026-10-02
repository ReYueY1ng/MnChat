import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/messages.dart';
import 'core/models/skin_head_catalog.dart' show headIconAsset;
import 'core/services/app_lock.dart';
import 'core/services/chat/online_notify.dart'
    show newlyOnlineFriends, onlineFriendUins;
import 'core/services/chat_service.dart'
    show ChatService, ChatEvent, SessionSnapshot;
import 'core/services/notification_service.dart';
import 'core/services/tray_service.dart';
import 'core/storage/app_database.dart';
import 'core/storage/settings_store.dart';
import 'core/utils/log.dart';
import 'state/providers.dart';
import 'ui/home_shell.dart' show MainShell;
import 'ui/lock_page.dart';
import 'ui/login_page.dart';
import 'ui/theme/app_theme.dart';

/// 本模块日志标签。
const String _logTag = 'Main';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase(driftDatabase(name: 'mnchat'));
  // 托盘/窗口初始化必须在 runApp **之后**、且不能 await：
  // 它要走平台通道（window_manager）与根 bundle（图标解码），这两者在
  // hot restart 后可能迟迟不返回；若像以前那样在 runApp 之前 await，
  // runApp 永远执行不到，界面会卡在旧帧上（表现为"热重启后整个 UI 卡死"）。
  // 放到首帧之后再初始化，最坏情况只是"没有托盘"，界面不受影响。
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MnChatApp(),
    ),
  );
  unawaited(_initDesktopShell(db));
}

/// 初始化桌面壳层（系统托盘 + 关闭到托盘）。
///
/// 仅在桌面端生效；任何失败（含资源缺失）都只记日志并降级，绝不抛出，
/// 避免影响已经渲染出来的界面。
Future<void> _initDesktopShell(AppDatabase db) async {
  try {
    final store = SettingsStore(db);
    final closeToTray = await store.getBool(
      SettingsKeys.closeToTray,
      fallback: true,
    );
    final trayReady = await TrayService.init(closeToTray: closeToTray);
    // 只有桌面端才谈得上「托盘注册失败」；Android 上 init 直接返回 false，
    // 那不是失败，别去改设置。
    if (TrayService.isDesktop && !trayReady && closeToTray) {
      // 没有可用托盘（Linux 上是 StatusNotifierWatcher 缺失）却还拦截关窗：
      // 关窗后应用既不可见也召不回来。降级为「关窗即退出」，并把设置写回去，
      // 设置页会显示为已关闭；下次启动就不会再拦。
      await TrayService.setCloseToTray(false);
      await store.setBool(SettingsKeys.closeToTray, false);
      log.warn(
        '系统托盘不可用，已自动关闭「关闭到托盘」（关窗现在会直接退出）',
        tag: _logTag,
      );
    }
  } catch (e) {
    log.warn('桌面壳层初始化失败（已忽略）: $e', tag: _logTag);
  }
}

class MnChatApp extends ConsumerStatefulWidget {
  const MnChatApp({super.key});

  @override
  ConsumerState<MnChatApp> createState() => _MnChatAppState();
}

class _MnChatAppState extends ConsumerState<MnChatApp>
    with WidgetsBindingObserver {
  bool _autoLoginTried = false;

  /// 是否存在可用的自动登录凭据（启动时先读一次，用于跳过登录页停留）。
  bool _autoLoginAvailable = false;

  /// 应用锁是否启用（启动时读一次，设置变更时同步）。
  bool _lockEnabled = false;

  /// 当前是否处于锁定态（启动 / 从后台回前台时置位）。
  bool _locked = false;

  /// 是否**真的**进过后台（paused / hidden）。
  ///
  /// 桌面端「窗口失焦」只会上报 `inactive`，不算后台；只有最小化 / 隐藏窗口
  /// 才会上报 `hidden`。用这个粘性标记（而非"上一次状态"）判断，可避免
  /// `hidden → inactive → resumed` 这类多步恢复序列被漏判。
  bool _wasBackground = false;

  /// 后台通知订阅（dispose 时必须取消，否则泄漏）。
  StreamSubscription<ChatEvent>? _notifySub;

  /// 通知服务（按平台选择实现）；dispose 时释放。
  NotificationService? _notifications;

  /// 通知点击订阅（点通知 → 打开对应会话）。
  StreamSubscription<String>? _tapSub;

  /// 每个会话最近的若干条正文，供通知折叠面板展示。
  final Map<String, List<String>> _recentTexts = {};

  /// 登录前点到通知：先记住 key，登录成功后补开。
  String? _pendingTapSessionKey;

  /// 通知权限是否已申请过（只申请一次）。
  bool _notifyPermissionAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 监听登录态：曾登录后变为未登录（手动登出）→ 清除"可自动登录"
    // 标记，回到登录页。否则 _autoLoginAvailable 保持 true，登出后
    // home 仍进入 MainShell，表现为"无法退出登录"。
    ref.listenManual(authProvider, (prev, next) {
      if (prev?.isLoggedIn == true && next.isLoggedIn == false && mounted) {
        if (_autoLoginAvailable) setState(() => _autoLoginAvailable = false);
      }
      // 登录成功：申请通知权限（Android 13+）并补开「登录前点击的通知」
      if (prev?.isLoggedIn != true && next.isLoggedIn) _afterLogin();
    });
    // 设置页开关变化即时同步（关闭时立刻取消锁定态）
    ref.listenManual(lockEnabledProvider, (_, next) {
      if (!mounted) return;
      setState(() {
        _lockEnabled = next;
        if (!next) _locked = false;
      });
    });
    _prepareAutoLogin();
  }

  /// 启动即读取设置：若有自动登录凭据 → 直接走"正在自动登录"启动页。
  Future<void> _prepareAutoLogin() async {
    final settings = ref.read(settingsProvider);
    final enabled = await settings.getBool(SettingsKeys.autoLogin);
    final creds = enabled ? await settings.loadCredentials() : null;
    // 应用锁：仅当开关开启且已设置密码时才需要解锁。
    final lockOn = await settings.getBool(SettingsKeys.lockEnabled);
    final hasPin = lockOn && await AppLockService(settings).isPinSet();
    if (!mounted) return;
    setState(() {
      _autoLoginAvailable = creds != null;
      _lockEnabled = lockOn;
      _locked = hasPin;
    });
    // 后台新消息通知监听（含通知点击跳转 / 平台通知实现初始化）
    await _initNotifications();
    // 等设置读取完成后再尝试自动登录，消除与启动页的竞态
    await _tryAutoLogin();
  }

  /// 初始化通知服务，并接上事件流与点击回调。
  Future<void> _initNotifications() async {
    final svc = ref.read(notificationServiceProvider);
    _notifications = svc;
    await svc.init();
    // 点击通知 → 打开对应会话（热启动）
    _tapSub = svc.taps.listen(_openSessionFromKey);
    // 冷启动：应用是被点击通知拉起来的 → 直接进那个会话
    final initial = await svc.initialTapSessionKey();
    if (initial != null && initial.isNotEmpty) _openSessionFromKey(initial);
    _subscribeNotifications(svc);
  }

  /// 点击通知 → 打开对应会话（key 形如 `friend_123` / `group_456`）。
  void _openSessionFromKey(String key) {
    final sep = key.lastIndexOf('_');
    if (sep <= 0) return;
    final id = int.tryParse(key.substring(sep + 1));
    if (id == null || id == 0) return;
    // 尚未登录（冷启动早期）→ 先记住，登录成功后补开
    if (!mounted || !ref.read(authProvider).isLoggedIn) {
      _pendingTapSessionKey = key;
      return;
    }
    final type = key.substring(0, sep) == ChatSessionType.group.name
        ? ChatSessionType.group
        : ChatSessionType.friend;
    ref.read(activeSessionProvider.notifier).open(type, id);
  }

  /// 登录成功后的通知相关动作：申请权限 + 补开「登录前点击的通知」。
  void _afterLogin() {
    if (!_notifyPermissionAsked) {
      _notifyPermissionAsked = true;
      // Android 13+ 必须在运行时申请，否则系统静默丢弃所有通知
      unawaited(ref.read(notificationServiceProvider).requestPermission());
    }
    final pending = _pendingTapSessionKey;
    if (pending != null) {
      _pendingTapSessionKey = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openSessionFromKey(pending),
      );
    }
  }

  /// 是否处于「用户看不到界面」的状态。
  ///
  /// **`inactive` 不算后台**：Android 上它只表示「可见但失焦」（系统弹窗、下拉
  /// 通知栏、切换任务都会触发），把它当后台正是「前台也在弹通知」的来源。
  bool get _isBackground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.detached;
  }

  /// 前后台切换时同步保活：Android 只在后台启动前台服务（前台通知栏保持干净）。
  void _syncBackgroundService(AppLifecycleState state) {
    final svc = _notifications;
    if (svc == null) return;
    final background =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    svc.setBackgroundMode(background && ref.read(keepAliveProvider));
  }

  /// 订阅 ChatService 事件流：仅**后台**弹系统通知，且按会话聚合。
  /// 上一次看到的"在线好友"集合 —— 用来识别「离线 → 在线」的跳变。
  final Set<int> _onlineSeen = <int>{};
  ProviderSubscription<AsyncValue<SessionSnapshot>>? _onlineSub;

  /// 好友上线通知：对齐反编译 `friendservice.lua:7618-7624` 的
  /// `DoFriendOnlineNotify` —— 只有**离线→在线**且开了「上线通知」才提醒。
  void _subscribeOnlineNotify(NotificationService svc) {
    _onlineSub?.close();
    _onlineSub = ref.listenManual<AsyncValue<SessionSnapshot>>(
      sessionListProvider,
      (prev, next) {
        final snap = next.asData?.value;
        if (snap == null) return;
        final online = onlineFriendUins(snap.sessions);
        // 首次只记录基线，不提醒（刚启动时人人都是"新上线"）。
        final baseline = _onlineSeen.isEmpty && prev?.asData?.value == null;
        final fresh = newlyOnlineFriends(_onlineSeen, online);
        _onlineSeen
          ..clear()
          ..addAll(online);
        if (baseline || !_isBackground) return;
        for (final uin in fresh) {
          unawaited(_notifyOnline(svc, snap, uin));
        }
      },
    );
  }

  Future<void> _notifyOnline(
    NotificationService svc,
    SessionSnapshot snap,
    int uin,
  ) async {
    try {
      if (!ref.read(notifyEnabledProvider)) return;
      if (ref.read(dndEnabledProvider) &&
          ref.read(dndWindowProvider).contains(DateTime.now())) {
        return;
      }
      final store = ref.read(settingsProvider);
      if (!await store.friendOnlineNotify(uin)) return;
      ChatSession? session;
      for (final s in snap.sessions) {
        if (s.type == ChatSessionType.friend && s.id == uin) {
          session = s;
          break;
        }
      }
      final name = session?.name ?? '$uin';
      svc.showMessage(
        MessageNotification(
          // 用独立 key：不要顶掉这个好友的新消息通知。
          sessionKey: 'online_$uin',
          title: '好友上线',
          text: '你的好友「$name」上线了',
          group: false,
          avatarUrl: session?.avatar,
          avatarAsset: _headAssetOf(session),
        ),
      );
    } catch (_) {
      // 通知失败不影响其它流程
    }
  }

  void _subscribeNotifications(NotificationService svc) {
    final service = ref.read(chatServiceProvider);
    _notifySub?.cancel();
    _subscribeOnlineNotify(svc);
    _notifySub = service.eventStream.listen((event) {
      // 通知开关即时生效
      if (!ref.read(notifyEnabledProvider)) return;
      // 自己发的消息不通知
      if (event.message.uin == service.myUin) return;
      // 免打扰时段内不弹通知
      if (ref.read(dndEnabledProvider) &&
          ref.read(dndWindowProvider).contains(DateTime.now())) {
        return;
      }
      // 前台不弹系统通知（UI 自己会展示）；inactive 不算后台
      if (!_isBackground) return;

      final key = '${event.sessionType.name}_${event.sessionId}';
      final hide = ref.read(hideNotifyContentProvider);
      final raw = event.message.text;
      // 该会话最近几条正文（隐私模式下不收集）
      final recent = _recentTexts.putIfAbsent(key, () => <String>[]);
      if (!hide && raw.isNotEmpty) {
        recent.add(raw.length > 60 ? '${raw.substring(0, 60)}…' : raw);
        if (recent.length > 5) recent.removeRange(0, recent.length - 5);
      }
      final session = _sessionOf(service, event);
      final isGroup = event.sessionType == ChatSessionType.group;
      svc.showMessage(
        MessageNotification(
          sessionKey: key,
          title: hide ? 'MnChat · 新消息' : _sessionTitleOf(session, isGroup),
          text: hide
              ? '你有一条新消息'
              : (raw.isEmpty
                    ? '新消息'
                    : (raw.length > 30
                          ? '${raw.substring(0, 30)}…'
                          : raw)),
          lines: hide ? const [] : List<String>.from(recent),
          group: isGroup,
          // 通知头像：优先本地头像本体图标（无需联网），其次网络头像
          avatarUrl: session?.avatar,
          avatarAsset: _headAssetOf(session),
        ),
      );
    });
  }

  /// 事件对应的会话（取通知标题与头像用）；找不到返回 null。
  ChatSession? _sessionOf(ChatService service, ChatEvent event) {
    for (final s in service.sessions) {
      if (s.type == event.sessionType && s.id == event.sessionId) return s;
    }
    return null;
  }

  /// 通知标题：会话名（群聊加前缀）；取不到时退化为「新消息」。
  String _sessionTitleOf(ChatSession? session, bool isGroup) {
    final name = session?.name.trim() ?? '';
    if (name.isEmpty) return isGroup ? '群聊新消息' : '新消息';
    return isGroup ? '群聊 · $name' : name;
  }

  /// 会话的本地头像图标（头像本体 type/id 有对应资源时）—— 通知大图标优先用它，
  /// 免得为了一个通知去联网下载；返回 Flutter asset key。
  String? _headAssetOf(ChatSession? session) {
    final type = session?.headType;
    final id = session?.headId;
    if (type == null || id == null || id <= 0) return null;
    return headIconAsset(type, id);
  }

  /// 自动登录：成功后进入会话页；失败/无凭据回登录页。
  Future<void> _tryAutoLogin() async {
    if (_autoLoginTried) return;
    _autoLoginTried = true;
    await ref.read(authProvider.notifier).autoLogin();
    // 自动登录失败 → 清除"待自动登录"标记，回退到登录页
    if (mounted && !ref.read(authProvider).isLoggedIn && _autoLoginAvailable) {
      setState(() => _autoLoginAvailable = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifySub?.cancel();
    _notifySub = null;
    _tapSub?.cancel();
    _tapSub = null;
    _notifications?.dispose();
    _notifications = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 前后台切换同步保活：只在后台挂前台服务，回到前台立刻摘掉常驻通知
    _syncBackgroundService(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackground = true;
    }
    // 回前台动作（重连 / 重新上锁）只在**确实进过后台**时执行。
    // 桌面端窗口聚焦也会上报 resumed（失焦是 inactive），若不加这个门闩，
    // 每次点回窗口都会被当成"回前台"而重连、刷新一遍会话。
    if (state == AppLifecycleState.resumed && _wasBackground) {
      _wasBackground = false;
      // 若 WS 断开则重连；活跃则强制心跳（防止账号在游戏端被标记离线）。
      ref.read(chatServiceProvider).ensureConnection();
      if (_lockEnabled && !_locked && mounted) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final accent = ref.watch(accentColorProvider);
    final loggedIn = auth.isLoggedIn || _autoLoginAvailable;
    final showLock = loggedIn && _lockEnabled && _locked;

    return MaterialApp(
      title: 'MnChat · 迷你世界外部聊天',
      debugShowCheckedModeBanner: false,
      // 关闭 M3 的「拉伸」过滚指示器（见 [AppScrollBehavior]）。
      scrollBehavior: const AppScrollBehavior(),
      theme: buildAppTheme(Brightness.light, seedColor: accent),
      darkTheme: buildAppTheme(Brightness.dark, seedColor: accent),
      themeMode: switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      home: !loggedIn
          ? const LoginPage()
          : showLock
          ? LockPage(onUnlocked: () => setState(() => _locked = false))
          // 已登录或即将自动登录：直接进会话页，登录在后台完成
          : const MainShell(),
    );
  }
}
