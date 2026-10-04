import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/messages.dart';
import '../core/models/session_key.dart' show sessionKeyOf;
import '../core/services/native_bridge.dart';
import '../state/providers.dart';
import 'chat_page.dart';
import 'dynamics_page.dart';
import 'friends_page.dart';
import 'session_list_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/account_menu.dart';
import 'widgets/request_error_indicator.dart'
    show RequestErrorIndicator, RequestErrorListener;

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

  /// 宽屏下会话列表栏的宽度（桌面端可拖拽调整）。
  double _chatListWidth = AppSizes.chatListWidth;

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

  /// 是否使用左侧常驻导航栏。
  ///
  /// 桌面端（有鼠标键盘、窗口通常够高）只要窗口不是极端窄就用侧栏 —— 以前用
  /// 「横屏 && ≥800」判定，窄而高的桌面窗口会退化成底部导航栏，很别扭。
  /// 移动端仍按宽度判定：竖屏手机保持底部栏，横屏手机（≥800）用侧栏。
  bool _useRail(double maxWidth) => isDesktopPlatform
      ? maxWidth >= AppSizes.railMinWindow
      : maxWidth >= AppSizes.railBreakpoint;

  /// 返回上一级：聊天打开 → 回会话列表；其他 tab → 回「会话」tab。
  ///
  /// [background] 为 true 时（系统返回键一路退到会话列表）才把应用退到后台；
  /// ESC 不在其列 —— 把应用藏起来不该是键盘快捷键的后果。
  ///
  /// 关闭会话时必须一并清掉 [_chatInstance]，否则宽屏常驻聊天面板仍显示上一次
  /// 的会话内容（见 lib/ui/AGENTS.md 的同名反模式）。
  void _handleBack(bool chatOpen, {bool background = true}) {
    if (chatOpen) {
      ref.read(activeSessionProvider.notifier).close();
      setState(() => _chatInstance = null);
    } else if (_tab != 0) {
      setState(() => _tab = 0);
    } else if (background) {
      NativeBridge.moveTaskToBack();
    }
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
        key: ValueKey(sessionKeyOf(activeSession.type, activeSession.id)),
        type: activeSession.type,
        sessionId: activeSession.id,
        name: session?.name ?? '',
      );
    }
    final chatPane = _chatInstance ?? const _EmptyChatPlaceholder();

    return LayoutBuilder(builder: (context, constraints) {
      final useRail = _useRail(constraints.maxWidth);
      final chatOpen = activeSession != null;

      // 内容区宽度 = 窗口宽 - 侧栏宽，而侧栏宽度由 Material 内部决定。这里不再
      // 用硬编码的 76 去推算（rail 一改宽就错位），双栏判定交给内层
      // LayoutBuilder 用实测的内容区宽度（见下面的 useRail 分支）。
      Widget buildTabs(double availableWidth) {
        final sessionsTab = _SessionsTab(
          sessions: _conversations(list),
          chatPane: chatPane,
          chatOpen: chatOpen,
          wide: availableWidth >= AppSizes.chatSplitBreakpoint,
          listWidth: _chatListWidth,
          onListWidthChanged: (w) => setState(() => _chatListWidth = w),
          onOpenSession: _toggleSession,
        );
        final friendsTab = FriendsPage(
          onOpenChat: (uin) => _openChat(ChatSessionType.friend, uin),
        );
        final dynamicsTab = const DynamicsPage();
        return _buildTabBody(sessionsTab, friendsTab, dynamicsTab);
      }

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, Object? result) {
          if (didPop) return;
          // 一级返回：聊天打开 → 回会话列表；其他 tab → 回"会话"tab；
          // 会话列表 → 后台（不退出，前台服务继续收消息）
          _handleBack(chatOpen);
        },
        child: CallbackShortcuts(
          // 桌面端 ESC 与系统返回键同义，只是不会把应用退到后台。
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _handleBack(chatOpen, background: false),
          },
          child: Focus(
            autofocus: true,
            child: RequestErrorListener(
              child: useRail
                  // 宽屏：常驻侧边栏 + 内容区
                  ? Scaffold(
                      floatingActionButton: const RequestErrorIndicator(),
                      body: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildRail(),
                          const VerticalDivider(width: 1),
                          Expanded(
                            // 用内层约束实测内容区宽度，双栏判定不再依赖魔法数。
                            child: LayoutBuilder(
                              builder: (context, content) =>
                                  buildTabs(content.maxWidth),
                            ),
                          ),
                        ],
                      ),
                    )
                  // 窄屏：底部栏（聊天打开时隐藏，最大化聊天区域）
                  : Scaffold(
                      floatingActionButton: const RequestErrorIndicator(),
                      body: buildTabs(constraints.maxWidth),
                      bottomNavigationBar: chatOpen
                          ? null
                          : _buildBottomBar(),
                    ),
            ),
          ),
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

  /// 宽屏下会话列表栏的宽度，以及拖拽调整它的回调。
  final double listWidth;
  final ValueChanged<double> onListWidthChanged;

  /// 点击会话卡片的回调（HomeShell 负责"再次点击当前会话关闭"的切换）。
  final ValueChanged<ChatSession> onOpenSession;

  const _SessionsTab({
    required this.sessions,
    required this.chatPane,
    required this.chatOpen,
    required this.wide,
    required this.listWidth,
    required this.onListWidthChanged,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    if (wide) {
      // 宽屏：左会话列表 + 右聊天（双栏同时可见），中间的分隔线可拖拽调宽。
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: listWidth,
            child: SessionListPage(
              sessions: sessions,
              onOpenChat: onOpenSession,
            ),
          ),
          _ChatListResizeHandle(
            width: listWidth,
            onChanged: onListWidthChanged,
          ),
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

/// 会话列表栏与聊天面板之间的拖拽手柄。
///
/// 视觉上仍是一条 1px 分隔线，但命中区域加宽到 7px，并给出左右缩放光标 ——
/// 1px 的线在桌面上根本抓不住。宽度收敛在 [AppSizes.chatListMinWidth] 与
/// [AppSizes.chatListMaxWidth] 之间，避免把聊天面板挤没或把列表拉满整屏。
class _ChatListResizeHandle extends StatelessWidget {
  const _ChatListResizeHandle({required this.width, required this.onChanged});

  final double width;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onChanged(
          (width + details.delta.dx).clamp(
            AppSizes.chatListMinWidth,
            AppSizes.chatListMaxWidth,
          ),
        ),
        child: const SizedBox(
          width: 7,
          child: Center(child: VerticalDivider(width: 1)),
        ),
      ),
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
          const SizedBox(height: AppSpacing.lg),
          Text('选择会话开始聊天', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
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
