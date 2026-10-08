/// 玩家简要信息浮窗（会话头像 / 侧栏本人头像共用）。
///
/// - [showSessionPlayerInfoPopup]：在头像附近弹出的浮动信息卡（等级 / 默契度 /
///   冒险家 / 称号 / 勋章 + 个人中心 / 置顶 / 赠送 / 更多），替代原先的全屏
///   底部弹窗；
/// - 「更多」接 `session_menu.dart` 的 [showSessionMenu]（新的会话浮动菜单，
///   与长按 / 右键同一套：上线通知 / 拍一拍 / 置顶 / 免打扰 / 标签 / 备注 /
///   删除好友），不再走已废弃的底部弹窗版本；
/// - 内容片段与会话缓存复用 `player_info_common.dart`。[SessionPlayerInfo]
///   由此文件继续对外暴露。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/messages.dart';
import '../../core/storage/settings_store.dart';
import '../../state/providers.dart';
import '../player_home_page.dart';
import '../profile_page.dart';
import '../theme/app_tokens.dart';
import 'gift_picker.dart' show showGiftPicker;
import 'player_info_common.dart';
import 'session_menu.dart' show showSessionMenu;

export 'player_info_common.dart' show SessionPlayerInfo;

/// 玩家卡的入口来源 —— 决定底部按钮。
///
/// 游戏里这套按钮不是写死的：`PlayerInfoCardMgr:ShowByParamFguiObj(funcBtns: ...)`
/// 由**每个调用点**自己传（`playerinfocardmgr.lua:19-35` 的 `def_funcBtn`）。
/// 对得上的两处：
///   - 动态信息流 / 动态详情的头像卡：`个人中心 / 加好友 / 赠送 / 关注`
///     （`dynamicsinfocard.lua:2087-2105`）；
///   - 好友列表的卡：只有 `个人中心`（`friendoldrely/friendmgr.lua:2746-2751`）。
/// 本客户端在 friends 来源保留了会话类的置顶/更多（游戏把它们放在会话菜单里，
/// 不在卡上）。
enum PlayerCardOrigin {
  /// 好友列表 / 会话列表 / 侧栏。
  friends,

  /// 动态信息流 / 动态详情。
  dynamics,
}

/// 在 [anchor]（头像的屏幕矩形）附近弹出玩家信息浮窗。
///
/// 采用 `showDialog` + `Stack/Positioned`：路由自带遮罩点击 / 返回键关闭，
/// 无需自行管理 OverlayEntry；卡片位置按锚点自动翻转（锚点在下半屏时向上
/// 弹），保证不越出屏幕。[anchor] 为空时落在左上角（无锚点 / 测试场景）。
Future<void> showSessionPlayerInfoPopup(
  BuildContext context,
  WidgetRef ref, {
  required int uin,
  required String name,
  Rect? anchor,
  String? avatarUrl,
  int? headType,
  int? headId,
  int? headFrameId,
  bool showActions = true,
  PlayerCardOrigin origin = PlayerCardOrigin.friends,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => _SessionPlayerInfoPopup(
      anchor: anchor,
      hostContext: context,
      ref: ref,
      uin: uin,
      name: name,
      avatarUrl: avatarUrl,
      headType: headType,
      headId: headId,
      headFrameId: headFrameId,
      showActions: showActions,
      origin: origin,
    ),
  );
}

/// 浮窗定位：只负责把信息卡摆到头像旁边，不承载内容。
class _SessionPlayerInfoPopup extends StatelessWidget {
  final Rect? anchor;

  /// 触发浮窗的宿主 context：浮窗关闭后继续用它打开菜单 / 页面。
  final BuildContext hostContext;

  final WidgetRef ref;
  final int uin;
  final String name;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? headFrameId;

  /// 是否展示底部操作行（本人信息卡只展示资料，不带好友操作）。
  final bool showActions;

  /// 入口来源（决定底部按钮）。
  final PlayerCardOrigin origin;

  const _SessionPlayerInfoPopup({
    required this.anchor,
    required this.hostContext,
    required this.ref,
    required this.uin,
    required this.name,
    this.avatarUrl,
    this.headType,
    this.headId,
    this.headFrameId,
    this.showActions = true,
    this.origin = PlayerCardOrigin.friends,
  });

  /// 浮窗最大宽度（与底部弹窗信息区相当的紧凑卡片）。
  static const double _maxWidth = 340;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rect = anchor ?? Rect.fromLTWH(AppSpacing.lg, AppSpacing.lg, 1, 1);
    final maxLeft = size.width - _maxWidth - AppSpacing.sm;
    final left = maxLeft <= AppSpacing.sm
        ? AppSpacing.sm
        : rect.left.clamp(AppSpacing.sm, maxLeft).toDouble();
    // 锚点在上半屏 → 向下展开；否则向上弹，避免越出底边。
    final below = rect.center.dy <= size.height / 2;
    final maxHeight = (size.height - AppSpacing.xxl).clamp(
      160.0,
      double.infinity,
    );
    return Stack(
      children: [
        Positioned(
          left: left,
          top: below ? rect.bottom + AppSpacing.sm : null,
          bottom: below ? null : size.height - rect.top + AppSpacing.sm,
          width: _maxWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: _SessionPlayerInfoCard(
                hostContext: hostContext,
                ref: ref,
                uin: uin,
                name: name,
                avatarUrl: avatarUrl,
                headType: headType,
                headId: headId,
                headFrameId: headFrameId,
                showActions: showActions,
                origin: origin,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 信息卡内容：头像 + 昵称 + 迷你号 + 等级/默契度/称号 + 勋章 + 操作行。
class _SessionPlayerInfoCard extends StatefulWidget {
  final BuildContext hostContext;
  final WidgetRef ref;
  final int uin;
  final String name;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? headFrameId;

  /// 是否展示底部操作行（本人信息卡为 false，只展示资料）。
  final bool showActions;

  /// 入口来源（决定底部按钮）。
  final PlayerCardOrigin origin;

  const _SessionPlayerInfoCard({
    required this.hostContext,
    required this.ref,
    required this.uin,
    required this.name,
    this.avatarUrl,
    this.headType,
    this.headId,
    this.headFrameId,
    this.showActions = true,
    this.origin = PlayerCardOrigin.friends,
  });

  @override
  State<_SessionPlayerInfoCard> createState() => _SessionPlayerInfoCardState();
}

class _SessionPlayerInfoCardState extends State<_SessionPlayerInfoCard> {
  /// 本地置顶状态；null = 读取中（按钮先按未置顶绘制）。
  bool? _pinned;

  /// 会话置顶 key（好友类型，与底部弹窗一致）。
  String get _pinKey =>
      SettingsKeys.sessionKey(ChatSessionType.friend.name, widget.uin);

  @override
  void initState() {
    super.initState();
    if (widget.showActions) _readPinned();
  }

  Future<void> _readPinned() async {
    try {
      final pinned = await widget.ref.read(settingsProvider).isPinned(_pinKey);
      if (mounted) setState(() => _pinned = pinned);
    } catch (_) {
      if (mounted) setState(() => _pinned = false);
    }
  }

  Future<void> _togglePinned() async {
    final next = !(_pinned ?? false);
    setState(() => _pinned = next);
    try {
      await widget.ref.read(settingsProvider).setPinned(_pinKey, next);
    } catch (_) {
      // 设置不可用（测试等）时忽略持久化失败，保持本地状态。
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(next ? '已置顶' : '已取消置顶')));
  }

  /// 是不是「我自己」——决定动作行内容与「个人主页」的去向。
  bool get _isSelf => widget.uin == widget.ref.read(myUinProvider);

  /// 本次卡内已经点过「关注」/「加好友」（点完就收起对应按钮）。
  bool _followedLocal = false;
  bool _friendRequestedLocal = false;

  /// 关系位（与会话列表同源：bit3=8 好友、bit4=16 关注）。
  int get _relation {
    try {
      final list = widget.ref.read(contactsProvider).value ?? const <Contact>[];
      for (final c in list) {
        if (c.uin == widget.uin) return c.relation;
      }
    } catch (_) {
      // 联系人未加载 / 环境不可用（测试）时按 0 处理。
    }
    return 0;
  }

  bool get _alreadyFriend => (_relation & 8) != 0;
  bool get _alreadyFollowing => (_relation & 16) != 0 || _followedLocal;

  /// 加好友（`applyFriend`，对齐游戏卡片 `def_funcBtn.AddFriend`）。
  Future<void> _addFriend() async {
    try {
      await widget.ref.read(chatServiceProvider).applyFriend(widget.uin);
      if (!mounted) return;
      setState(() => _friendRequestedLocal = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已发送好友申请')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('申请失败，请稍后重试')));
    }
  }

  /// 关注（`followPlayer`，对齐游戏卡片 `def_funcBtn.Focus`）。
  Future<void> _follow() async {
    try {
      await widget.ref
          .read(chatServiceProvider)
          .followPlayer(widget.uin, follow: true);
      if (!mounted) return;
      setState(() => _followedLocal = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已关注')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('关注失败')));
    }
  }

  /// 他人的操作行 —— 按钮按入口来源取，对齐游戏
  /// `PlayerInfoCardMgr:ShowByParamFguiObj(funcBtns: ...)`：
  /// 动态来源 = 个人中心 / 加好友 / 赠送 / 关注（`dynamicsinfocard.lua:2087-2105`）；
  /// 其余来源保留会话类的 置顶 / 更多（游戏放在会话菜单里，不在卡上）。
  List<Widget> _otherActions(bool pinned) {
    if (widget.origin == PlayerCardOrigin.dynamics) {
      return [
        PlayerCircleAction(
          icon: Icons.person_outline,
          label: '个人中心',
          onTap: _openHomePage,
        ),
        if (!_alreadyFriend && !_friendRequestedLocal)
          PlayerCircleAction(
            icon: Icons.person_add_alt_1_outlined,
            label: '加好友',
            onTap: () => unawaited(_addFriend()),
          ),
        PlayerCircleAction(
          icon: Icons.card_giftcard,
          label: '赠送',
          onTap: _gift,
        ),
        if (!_alreadyFollowing)
          PlayerCircleAction(
            icon: Icons.favorite_border,
            label: '关注',
            onTap: () => unawaited(_follow()),
          ),
      ];
    }
    return [
      PlayerCircleAction(
        icon: Icons.person_outline,
        label: '个人中心',
        onTap: _openHomePage,
      ),
      PlayerCircleAction(
        icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: pinned ? '取消置顶' : '置顶',
        highlighted: pinned,
        onTap: () => unawaited(_togglePinned()),
      ),
      PlayerCircleAction(
        icon: Icons.card_giftcard,
        label: '赠送',
        onTap: _gift,
      ),
      PlayerCircleAction(
        icon: Icons.more_horiz,
        label: '更多',
        onTap: () => unawaited(_openMoreMenu()),
      ),
    ];
  }

  /// 个人中心：先关浮窗，再推入主页。
  ///
  /// 自己 → 个人主页（[ProfilePage]，带编辑入口）；别人 → 他人主页
  /// （[PlayerHomePage]）。
  void _openHomePage() {
    final navigator = Navigator.of(context);
    final self = _isSelf;
    navigator.pop();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              self ? const ProfilePage() : PlayerHomePage(targetUin: widget.uin),
        ),
      ),
    );
  }

  /// 赠送：关掉浮窗后弹礼物面板（锚点沿用本浮窗的位置）。
  void _gift() {
    final navigator = Navigator.of(context);
    final anchor = _anchorRect(context);
    final hostRef = widget.ref;
    final uin = widget.uin;
    final name = widget.name;
    navigator.pop();
    unawaited(
      showGiftPicker(
        navigator.context,
        hostRef,
        uin: uin,
        name: name,
        anchor: anchor,
      ),
    );
  }

  /// 本浮窗当前的屏幕矩形（作为礼物面板的锚点）。
  Rect? _anchorRect(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 更多：关浮窗后打开**新版**会话浮动菜单（[showSessionMenu]，与长按 / 右键
  /// 同一套；它已替代原先的底部弹窗版本）。
  Future<void> _openMoreMenu() async {
    final anchor = _anchorRect(context);
    Navigator.of(context).pop();
    final host = widget.hostContext;
    if (!host.mounted) return;
    await showSessionMenu(
      host,
      widget.ref,
      session: ChatSession(
        id: widget.uin,
        type: ChatSessionType.friend,
        name: widget.name,
      ),
      globalPosition:
          anchor?.topLeft ?? const Offset(AppSpacing.lg, AppSpacing.lg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinned = _pinned ?? false;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: AppRadius.cardR,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：头像 + 昵称 + 迷你号（与底部弹窗共用）
            PlayerInfoHeader(
              uin: widget.uin,
              name: widget.name,
              avatarUrl: widget.avatarUrl,
              headType: widget.headType,
              headId: widget.headId,
              headFrameId: widget.headFrameId,
              radius: 32,
            ),
            const SizedBox(height: AppSpacing.md),
            // 等级 + 默契度 + 冒险家 + 称号 + 勋章（命中缓存时不重新请求）
            PlayerInfoStats(ref: widget.ref, uin: widget.uin),
            const SizedBox(height: AppSpacing.lg),
            if (widget.showActions) ...[
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              // 操作行：自己只有「个人主页」入口（置顶 / 赠送 / 更多是好友操作）；
              // 别人是 个人中心 / 置顶 / 赠送 / 更多。
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _isSelf
                    ? [
                        PlayerCircleAction(
                          icon: Icons.account_circle_outlined,
                          label: '个人主页',
                          onTap: _openHomePage,
                        ),
                      ]
                    : _otherActions(pinned),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
