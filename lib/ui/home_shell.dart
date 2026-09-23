import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../core/services/native_bridge.dart';
import '../state/providers.dart';
import 'chat_page.dart';
import 'dynamics_page.dart';
import 'friends_page.dart';
import 'session_list_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/account_menu.dart';

/// 主界面：会话 / 好友 / 动态 三入口。
///
/// - 竖屏：底部 NavigationBar 切换三个 tab；
/// - 横屏：左侧常驻 NavigationRail（会话/好友/动态），右侧内容区。
///
/// "会话"tab 保留原双栏体验：内容区宽时（会话列表 + 聊天并排），
/// 窄时 IndexedStack 在列表与聊天间切换（聊天打开时隐藏底部栏）。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// 当前 tab：0 会话 / 1 好友 / 2 动态。
  int _tab = 0;

  /// 缓存最近一次构建的聊天页，保证 IndexedStack 中状态不丢失。
  Widget? _chatInstance;

  @override
  void initState() {
    super.initState();
    // 按设置启停后台前台服务（保活收推送），并监听设置变化即时生效
    _applyKeepAlive(ref.read(keepAliveProvider));
    ref.listenManual(keepAliveProvider, (_, next) => _applyKeepAlive(next));
  }

  /// 后台保活设置变化：这里只负责「关掉时立刻停」。
  ///
  /// 前台服务**不再在这里启动** —— 应用在前台时通知栏必须是干净的（旧实现一进
  /// 主界面就挂常驻通知「MnChat 运行中」，用户明确不接受）。启动时机交给
  /// `MnChatApp` 的生命周期回调：退到后台才 start、回到前台就 stop。
  void _applyKeepAlive(bool enabled) {
    final svc = ref.read(notificationServiceProvider);
    if (!enabled) {
      svc.setBackgroundMode(false);
      return;
    }
    // 设置页在前台打开，正常不会命中；稳妥起见按当前生命周期判断一次。
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final background =
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.detached;
    svc.setBackgroundMode(background);
  }

  void _switchTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
  }

  /// 从好友/动态发起聊天：打开会话并跳回"会话"tab。
  void _openChat(ChatSessionType type, int id) {
    ref.read(activeSessionProvider.notifier).open(type, id);
    if (_tab != 0) setState(() => _tab = 0);
  }

  /// 点击会话卡片：已是当前会话则关闭聊天面板（桌面端再点一次收起），
  /// 否则打开该会话。
  ///
  /// 宽屏常驻聊天面板由 [_chatInstance] 渲染，关闭时一并清掉缓存实例，
  /// 否则面板仍显示上一次的聊天内容（只是选中高亮消失，看不到"关闭"）。
  void _toggleSession(ChatSession s) {
    final active = ref.read(activeSessionProvider);
    if (active != null && active.type == s.type && active.id == s.id) {
      ref.read(activeSessionProvider.notifier).close();
      setState(() => _chatInstance = null);
    } else {
      ref.read(activeSessionProvider.notifier).open(s.type, s.id);
    }
  }

  /// 会话列表：好友只显示已聊过天的，群全部保留。
  static List<ChatSession> _conversations(List<ChatSession> all) => [
    for (final s in all)
      if (s.type == ChatSessionType.group || s.lastMessage != null) s,
  ];

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
    final session =
        activeSession == null ? null : findActive(list, activeSession);
    // 有活动会话时更新/创建聊天页实例（同 key 时 Element 复用，State 保留）。
    if (activeSession != null) {
      _chatInstance = ChatPage(
        key: ValueKey('${activeSession.type.name}_${activeSession.id}'),
        type: activeSession.type,
        sessionId: activeSession.id,
        name: session?.name ?? '',
      );
    }
    final chatPane = _chatInstance ?? const _EmptyChatPlaceholder();

    return LayoutBuilder(builder: (context, constraints) {
      final isLandscape =
          MediaQuery.orientationOf(context) == Orientation.landscape &&
          constraints.maxWidth >= 800;
      // 会话 tab 是否双栏：内容区足够宽（≥760）才并排，否则单页切换。
      final convSessions = _conversations(list);
      final contentWidth = isLandscape
          ? constraints.maxWidth - 76 // NavigationRail 占宽
          : constraints.maxWidth;
      final chatOpen = activeSession != null;
      final sessionWide = contentWidth >= 760;

      final sessionsTab = _SessionsTab(
        sessions: convSessions,
        chatPane: chatPane,
        chatOpen: chatOpen,
        wide: sessionWide,
        onOpenSession: _toggleSession,
      );
      final friendsTab = FriendsPage(onOpenChat: (uin) {
        _openChat(ChatSessionType.friend, uin);
      });
      final dynamicsTab = const DynamicsPage();

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, Object? result) {
          if (didPop) return;
          // 一级返回：聊天打开 → 回会话列表；其他 tab → 回"会话"tab；
          // 会话列表 → 后台（不退出，前台服务继续收消息）
          if (chatOpen) {
            ref.read(activeSessionProvider.notifier).close();
          } else if (_tab != 0) {
            setState(() => _tab = 0);
          } else {
            NativeBridge.moveTaskToBack();
          }
        },
        child: isLandscape
            // 横屏：常驻侧边栏 + 内容区
            ? Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRail(),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _buildTabBody(
                        sessionsTab,
                        friendsTab,
                        dynamicsTab,
                      ),
                    ),
                  ],
                ),
              )
            // 竖屏：底部栏（聊天打开时隐藏，最大化聊天区域）
            : Scaffold(
                body: _buildTabBody(sessionsTab, friendsTab, dynamicsTab),
                bottomNavigationBar: chatOpen
                    ? null
                    : _buildBottomBar(),
              ),
      );
    });
  }

  Widget _buildRail() {
    return NavigationRail(
      selectedIndex: _tab,
      onDestinationSelected: _switchTab,
      labelType: NavigationRailLabelType.all,
      // 账号头像固定在侧栏顶部（点击显示本人的玩家信息浮窗）。
      leading: const Padding(
        padding: EdgeInsets.only(top: AppSpacing.sm),
        child: AccountAvatarButton(showSelfInfo: true),
      ),
      // 菜单按钮固定在侧栏底部，与顶部头像打开同一菜单（QQ/微信 风格）。
      // 与顶部头像对称加 AppSpacing.sm 底部留白，避免按钮贴住窗口底边。
      trailing: const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.sm),
        child: AccountMenuButton(),
      ),
      trailingAtBottom: true,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: Text('会话'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('好友'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.public_outlined),
          selectedIcon: Icon(Icons.public),
          label: Text('动态'),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: _switchTab,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: '会话',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: '好友',
        ),
        NavigationDestination(
          icon: Icon(Icons.public_outlined),
          selectedIcon: Icon(Icons.public),
          label: '动态',
        ),
      ],
    );
  }

  Widget _buildTabBody(Widget sessionsTab, Widget friendsTab, Widget dynamicsTab) {
    // IndexedStack 保活三个 tab（会话聊天状态/动态滚动位置不随切换丢失）
    return IndexedStack(
      index: _tab,
      children: [
        sessionsTab,
        friendsTab,
        dynamicsTab,
      ],
    );
  }
}

/// "会话"tab：宽屏会话列表 + 聊天并排；窄屏列表/聊天单页切换。
class _SessionsTab extends StatelessWidget {
  final List<ChatSession> sessions;
  final Widget chatPane;
  final bool chatOpen;
  final bool wide;

  /// 点击会话卡片的回调（HomeShell 负责"再次点击当前会话关闭"的切换）。
  final ValueChanged<ChatSession> onOpenSession;

  const _SessionsTab({
    required this.sessions,
    required this.chatPane,
    required this.chatOpen,
    required this.wide,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    if (wide) {
      // 宽屏：左会话列表 + 右聊天（双栏同时可见）
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 320,
            child: SessionListPage(
              sessions: sessions,
              onOpenChat: onOpenSession,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: chatPane),
        ],
      );
    }
    // 窄屏：IndexedStack 保留两个页面实例
    return IndexedStack(
      index: chatOpen ? 1 : 0,
      children: [
        SessionListPage(sessions: sessions, onOpenChat: onOpenSession),
        chatPane,
      ],
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
          Text('选择会话开始聊天', style: theme.textTheme.titleMedium),
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
