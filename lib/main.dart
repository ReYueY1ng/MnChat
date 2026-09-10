import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/messages.dart';
import 'core/services/chat_service.dart' show ChatEvent;
import 'core/services/native_bridge.dart';
import 'core/storage/app_database.dart';
import 'core/storage/settings_store.dart';
import 'state/providers.dart';
import 'ui/home_shell.dart' show MainShell;
import 'ui/login_page.dart';

void main() {
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
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MnChatApp(),
    ),
  );
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
    _prepareAutoLogin();
  }

  /// 启动即读取设置：若有自动登录凭据 → 直接走"正在自动登录"启动页。
  Future<void> _prepareAutoLogin() async {
    final settings = ref.read(settingsProvider);
    final enabled = await settings.getBool(SettingsKeys.autoLogin);
    final creds = enabled ? await settings.loadCredentials() : null;
    if (!mounted) return;
    setState(() {
      _autoLoginAvailable = creds != null;
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
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final inBackground =
          lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.detached ||
          lifecycle == AppLifecycleState.inactive;
      if (!inBackground) return; // 前台时由 UI 直接展示，不弹系统通知
      final name = event.message.text.length > 30
          ? '${event.message.text.substring(0, 30)}…'
          : event.message.text;
      NativeBridge.showNotification(
        title: event.sessionType == ChatSessionType.group ? '群聊新消息' : '新消息',
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: 'MnChat · 迷你世界外部聊天',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: auth.isLoggedIn || _autoLoginAvailable
          // 已登录或即将自动登录：直接进会话页，登录在后台完成
          ? const MainShell()
          : const LoginPage(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00BFFF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder()),
    );
  }
}
