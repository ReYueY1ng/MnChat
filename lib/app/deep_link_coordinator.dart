/// 深链与桌面快捷方式的路由协调器。
///
/// 从 `MnChatApp` 的状态里拆出：解析、待落地缓存、登录后再落地、以及固定页面的
/// push。会话仍然走 `activeSessionProvider`（不压栈），坐标与之前完全一致。
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show MaterialPageRoute;
import 'package:quick_actions/quick_actions.dart';

import '../core/models/deep_link.dart';
import '../core/models/messages.dart' show ChatSessionType;
import '../core/utils/log.dart';
import '../ui/chat_search_page.dart' show ChatSearchPage;
import '../ui/favorites_page.dart' show FavoritesPage;
import '../ui/partners_page.dart' show PartnersPage;
import '../ui/video_player_page.dart' show VideoPlayerPage;

const String _logTag = 'DeepLink';

class DeepLinkCoordinator {
  DeepLinkCoordinator({
    required this.navKey,
    required this.isDesktop,
    required this.isReady,
    required this.isAlive,
    required this.openSession,
  });

  final GlobalKey<NavigatorState> navKey;

  /// 桌面端只认命令行参数（由 main 传入初始链接），不走 app_links。
  final bool isDesktop;

  /// 登录态就绪（已登录，或存在可自动登录的凭据）。
  final bool Function() isReady;

  /// 应用状态是否仍挂着（避免 await 之后 setState/push）。
  final bool Function() isAlive;

  final void Function(ChatSessionType type, int id) openSession;

  DeepLink? _pending;
  StreamSubscription<Uri>? _linkSub;

  void setInitial(DeepLink? link) => _pending = link;

  /// 移动端：初始 intent + 流；桌面端：no-op。
  Future<void> init() async {
    if (isDesktop) return;
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) handle(initial.toString());
      _linkSub = links.uriLinkStream.listen(
        (uri) => handle(uri.toString()),
        onError: (Object e) => log.warn('深链条出错（已忽略）：$e', tag: _logTag),
      );
    } catch (e) {
      log.warn('深链初始化失败（已忽略）：$e', tag: _logTag);
    }
    await _initQuickActions();
  }

  Future<void> _initQuickActions() async {
    if (isDesktop) return;
    try {
      const quickActions = QuickActions();
      await quickActions.setShortcutItems(const <ShortcutItem>[
        ShortcutItem(type: 'mnchat://search', localizedTitle: '搜索聊天记录'),
        ShortcutItem(type: 'mnchat://favorites', localizedTitle: '收藏'),
        ShortcutItem(type: 'mnchat://partners', localizedTitle: '我的搭子'),
      ]);
      await quickActions.initialize(handle);
    } catch (e) {
      log.warn('快捷方式初始化失败（已忽略）：$e', tag: _logTag);
    }
  }

  /// 收到一条深链：先记下再尝试落地（未登录时留给 [apply]）。
  void handle(String url) {
    final link = parseDeepLink(url);
    if (link == null) return;
    _pending = link;
    apply();
  }

  /// 落地待处理的深链。登录态未就绪时保持挂起。
  void apply() {
    final link = _pending;
    if (link == null || !isAlive() || !isReady()) return;
    _pending = null;
    if (link.isSession) {
      final key = link.sessionKey!;
      final sep = key.lastIndexOf('_');
      final id = int.tryParse(key.substring(sep + 1)) ?? 0;
      if (id == 0) return;
      openSession(link.sessionType!, id);
      return;
    }
    if (link.isVideo) {
      final source = link.videoUrl!;
      _pushAfterFrame(link, () => VideoPlayerPage(source: source));
      return;
    }
    final view = link.view;
    if (view == null) return;
    _pushAfterFrame(
      link,
      () => switch (view) {
        DeepLinkView.favorites => const FavoritesPage(),
        DeepLinkView.search => const ChatSearchPage(),
        DeepLinkView.partners => const PartnersPage(),
      },
    );
  }

  void _pushAfterFrame(DeepLink link, Widget Function() builder) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isAlive()) return;
      final nav = navKey.currentState;
      if (nav == null) {
        _pending = link;
        return;
      }
      nav.push(MaterialPageRoute<void>(builder: (_) => builder()));
    });
  }

  void dispose() {
    _linkSub?.cancel();
    _linkSub = null;
  }
}
