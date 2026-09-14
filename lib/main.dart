import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/messages.dart';
import 'core/services/app_lock.dart';
import 'core/services/chat_service.dart' show ChatEvent;
import 'core/services/native_bridge.dart';
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
  final db = AppDatabase(
    driftDatabase(
      name: 'mnchat',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );
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
    final closeToTray = await SettingsStore(
      db,
    ).getBool(SettingsKeys.closeToTray, fallback: true);
    await TrayService.init(closeToTray: closeToTray);
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

  /// 上一次的生命周期状态，用于判断"是否真的进过后台"。
  AppLifecycleState? _lastLifecycle;

  /// 后台通知订阅（dispose 时必须取消，否则泄漏）。
  StreamSubscription<ChatEvent>? _notifySub;

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
    // 后台新消息通知监听
    _subscribeNotifications();
    // 等设置读取完成后再尝试自动登录，消除与启动页的竞态
    await _tryAutoLogin();
  }

  /// 订阅 ChatService 事件流：收新消息 → 系统通知（仅后台时弹，避免打扰前台）。
  void _subscribeNotifications() {
    final service = ref.read(chatServiceProvider);
    _notifySub?.cancel();
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
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final inBackground =
          lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.detached ||
          lifecycle == AppLifecycleState.inactive;
      if (!inBackground) return; // 前台时由 UI 直接展示，不弹系统通知
      // 「通知隐藏内容」开启时只提示有新消息，不泄露正文
      final hide = ref.read(hideNotifyContentProvider);
      final name = hide
          ? '你有一条新消息'
          : (event.message.text.length > 30
                ? '${event.message.text.substring(0, 30)}…'
                : event.message.text);
      NativeBridge.showNotification(
        title: hide
            ? 'MnChat'
            : (event.sessionType == ChatSessionType.group ? '群聊新消息' : '新消息'),
        text: name,
        sessionKey: '${event.sessionType.name}_${event.sessionId}',
      );
    });
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前台：若 WS 断开则重连；活跃则强制心跳（防止账号在游戏端被标记离线）。
    if (state == AppLifecycleState.resumed) {
      ref.read(chatServiceProvider).ensureConnection();
      // 仅当确实进过后台（paused/hidden）才重新上锁；inactive 只是失焦。
      final wasBackground =
          _lastLifecycle == AppLifecycleState.paused ||
          _lastLifecycle == AppLifecycleState.hidden;
      if (wasBackground && _lockEnabled && !_locked && mounted) {
        setState(() => _locked = true);
      }
    }
    _lastLifecycle = state;
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
