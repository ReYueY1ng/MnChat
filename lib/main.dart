import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/messages.dart';
import 'core/services/native_bridge.dart';
import 'core/storage/app_database.dart';
import 'core/storage/settings_store.dart';
import 'state/providers.dart';
import 'ui/chat_page.dart';
import 'ui/login_page.dart';
import 'ui/session_list_page.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLogin());
    // 后台新消息通知监听
    _subscribeNotifications();
  }

  /// 订阅 ChatService 事件流：收新消息 → 系统通知（仅后台时弹，避免打扰前台）。
  void _subscribeNotifications() {
    final service = ref.read(chatServiceProvider);
    service.eventStream.listen((event) {
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

/// 登录后的主界面：宽屏双栏（会话列表 + 聊天），窄屏单页切换。
/// 窄屏用 IndexedStack 保持聊天页实例存活（返回列表后聊天状态保留）。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// 缓存最近一次构建的聊天页，保证 IndexedStack 中状态不丢失。
  Widget? _chatInstance;

  @override
  void initState() {
    super.initState();
    // 进入会话页后启动后台前台服务（保活收推送）
    NativeBridge.startBackgroundService();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeSessionProvider);
    final sessions = ref.watch(sessionListProvider);

    final list = sessions.when(
      data: (snap) => snap.sessions,
      loading: () => <ChatSession>[],
      error: (_, _) => <ChatSession>[],
    );
    ChatSession? findActive(List<ChatSession> list, ActiveSession active) {
      for (final s in list) {
        if (s.type == active.type && s.id == active.id) return s;
      }
      return null;
    }

    final activeSession = active;
    final session = activeSession == null
        ? null
        : findActive(list, activeSession);
    // 有活动会话时更新/创建聊天页实例（同 key 时 Element 复用，State 保留）
    if (activeSession != null) {
      _chatInstance = ChatPage(
        key: ValueKey('${activeSession.type.name}_${activeSession.id}'),
        type: activeSession.type,
        sessionId: activeSession.id,
        name: session?.name ?? '',
      );
    }
    final chatPane = _chatInstance ?? const _EmptyChatPlaceholder();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        return PopScope(
          // 一级返回：聊天打开时回会话列表；列表页返回 → 隐藏到后台
          canPop: false,
          onPopInvokedWithResult: (didPop, Object? result) {
            if (didPop) return;
            if (activeSession != null) {
              ref.read(activeSessionProvider.notifier).close();
            } else {
              // 列表页按返回 → 后台（不退出，前台服务继续收消息）
              NativeBridge.moveTaskToBack();
            }
          },
          child: Scaffold(
            body: isWide
                // 宽屏：左会话列表 + 右聊天（双栏同时可见）
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 300,
                        child: SessionListPage(sessions: list),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: chatPane),
                    ],
                  )
                // 窄屏（手机）：IndexedStack 保留两个页面实例
                : IndexedStack(
                    index: activeSession == null ? 0 : 1,
                    children: [
                      SessionListPage(sessions: list),
                      chatPane,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _EmptyChatPlaceholder extends StatelessWidget {
  const _EmptyChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 80,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('选择左侧会话开始聊天', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '好友 / 群聊 · 无需进入房间',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
