import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/nickname.dart' show plainNickname;
import '../../state/providers.dart';
import '../family_page.dart';
import '../mail_page.dart';
import '../profile_page.dart';
import '../settings_page.dart';
import '../theme/app_tokens.dart';
import 'avatar_view.dart';
import 'session_player_info_popup.dart';

/// 账号菜单操作项。
enum _AccountAction {
  profile,
  refresh,
  createGroup,
  family,
  mail,
  settings,
  switchAccount,
  logout,
}

/// 弹出账号菜单（侧边栏底部头像 / 竖屏 AppBar 头像共用）。
///
/// [anchor] 为头像在屏幕坐标系中的矩形，菜单贴其左缘展开，并在底部空间
/// 不足时自动上移，避免超出屏幕。选中后执行对应操作。
Future<void> showAccountMenu(
  BuildContext context,
  WidgetRef ref, {
  Rect? anchor,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject();
  final overlaySize = overlay is RenderBox
      ? overlay.size
      : MediaQuery.sizeOf(context);
  final position = RelativeRect.fromRect(
    anchor ?? Rect.fromLTWH(AppSpacing.sm, AppSpacing.sm, 1, 1),
    Offset.zero & overlaySize,
  );
  final errorColor = Theme.of(context).colorScheme.error;

  final action = await showMenu<_AccountAction>(
    context: context,
    position: position,
    items: [
      _menuItem(_AccountAction.profile, Icons.badge_outlined, '个人资料'),
      _menuItem(_AccountAction.refresh, Icons.refresh, '刷新会话'),
      _menuItem(_AccountAction.createGroup, Icons.group_add_outlined, '创建群'),
      _menuItem(_AccountAction.family, Icons.home_outlined, '家族'),
      _menuItem(
        _AccountAction.mail,
        Icons.mark_email_unread_outlined,
        '消息中心',
      ),
      _menuItem(_AccountAction.settings, Icons.settings_outlined, '设置'),
      const PopupMenuDivider(),
      _menuItem(
        _AccountAction.switchAccount,
        Icons.switch_account_outlined,
        '切换账号',
      ),
      _menuItem(
        _AccountAction.logout,
        Icons.logout,
        '退出登录',
        color: errorColor,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  await _runAccountAction(context, ref, action);
}

/// 菜单项：图标 + 文案，[color] 用于危险项（如退出登录）。
PopupMenuItem<_AccountAction> _menuItem(
  _AccountAction action,
  IconData icon,
  String label, {
  Color? color,
}) {
  return PopupMenuItem<_AccountAction>(
    value: action,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.md),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );
}

/// 执行选中的账号菜单操作（行为与原侧边栏 Drawer 一致）。
Future<void> _runAccountAction(
  BuildContext context,
  WidgetRef ref,
  _AccountAction action,
) async {
  switch (action) {
    case _AccountAction.profile:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
      );
    case _AccountAction.refresh:
      await ref.read(chatServiceProvider).loadSessions();
    case _AccountAction.createGroup:
      await _showCreateGroupDialog(context, ref);
    case _AccountAction.family:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FamilyPage()),
      );
    case _AccountAction.mail:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MailPage()),
      );
    case _AccountAction.settings:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
      );
    case _AccountAction.switchAccount:
      ref.read(authProvider.notifier).logout();
    case _AccountAction.logout:
      await _confirmLogout(context, ref);
  }
}

/// 退出登录二次确认：确认后登出。
Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('退出登录'),
      content: const Text('确定要退出当前账号吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('退出'),
        ),
      ],
    ),
  );
  if (confirmed == true) ref.read(authProvider.notifier).logout();
}

/// 创建群对话框：输入群名 + 勾选好友成员 → create_group。
Future<void> _showCreateGroupDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final nameCtrl = TextEditingController();
  final service = ref.read(chatServiceProvider);
  final contacts =
      service.contacts.where((c) => (c.relation & 8) != 0).toList()..sort(
        (a, b) => a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase()),
      );
  final selected = <int>{};

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('创建群'),
        content: SizedBox(
          // 手机上收敛到可用宽度（360dp 机型放不下 420）。
          width: dialogContentWidth(ctx, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '群名称',
                  hintText: '输入群名称',
                ),
              ),
              if (contacts.isNotEmpty)
                Flexible(
                  child: SizedBox(
                    height: 260,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Text(
                            '选择成员（可选）',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ...contacts.map((c) {
                          // 昵称来自服务端，可能带 `[i][color][b]` 这类标记；
                          // 这是纯文本，洗完为空才回退迷你号。
                          final plainName = plainNickname(c.nickname);
                          final name = plainName.isEmpty
                              ? '${c.uin}'
                              : plainName;
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(c.uin),
                            title: Text(name),
                            subtitle: Text('迷你号 ${c.uin}'),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selected.add(c.uin);
                              } else {
                                selected.remove(c.uin);
                              }
                            }),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final name = nameCtrl.text.trim();
  if (name.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入群名称')));
    }
    return;
  }
  try {
    final group = service.group;
    if (group == null) throw StateError('未登录');
    final members = <int>{service.myUin, ...selected}.toList();
    final resp = await group.createGroupWithMembers(
      groupName: name,
      members: members,
    );
    if (!context.mounted) return;
    final ret = resp['ret'];
    if (ret is num && ret != 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败: ret=$ret')));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('群已创建')));
    service.loadSessions(); // 刷新群列表
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }
}

/// 账号头像按钮：点击默认在自身位置弹出 [showAccountMenu]。
///
/// 横屏侧边栏顶部与竖屏 AppBar 共用，悬停提示为"账号"。
/// [showSelfInfo] 为 true 时改弹当前账号的玩家信息浮窗（横屏侧栏头像），
/// 竖屏 AppBar 保持账号菜单行为不变。
class AccountAvatarButton extends ConsumerStatefulWidget {
  /// true：点击显示本人玩家信息浮窗；false（默认）：打开账号菜单。
  final bool showSelfInfo;

  const AccountAvatarButton({super.key, this.showSelfInfo = false});

  @override
  ConsumerState<AccountAvatarButton> createState() =>
      _AccountAvatarButtonState();
}

class _AccountAvatarButtonState extends ConsumerState<AccountAvatarButton> {
  /// 用于取得头像在屏幕上的矩形，作为菜单锚点。
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    // 侧栏头像：显示本人玩家信息浮窗；未登录（uin=0）时退回账号菜单。
    if (widget.showSelfInfo) {
      final uin = ref.read(myUinProvider);
      if (uin > 0) {
        // 与侧栏头像同源（DIY 头像 / 头像本体 / 头像框）：不给的话卡片头部
        // 只能画首字占位（头像本体 / 头像框都缺）。
        final me = ref.read(myAvatarInfoProvider).asData?.value;
        final ownName = me?.name ?? '';
        await showSessionPlayerInfoPopup(
          context,
          ref,
          uin: uin,
          name: ownName.isNotEmpty
              ? ownName
              : (ref.read(authProvider).auth?.name ?? ''),
          anchor: anchor,
          avatarUrl: me?.avatarUrl,
          headType: me?.headType,
          headId: me?.headId,
          headFrameId: me?.frameId,
          // 本人卡片的动作行只剩「个人主页」（见 session_player_info_popup：
          // 自己的卡不带置顶 / 赠送 / 更多这些好友操作）—— 没有它，侧边栏
          // 「我的资料」点进来就没有通往个人主页的入口。
        );
        return;
      }
    }
    await showAccountMenu(context, ref, anchor: anchor);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    // 本人头像与聊天页同源（DIY 头像 / 头像本体 / 头像框）—— 这个位置原先只传
    // 昵称，所以永远只显示首字母，也没有头像框。
    final me = ref.watch(myAvatarInfoProvider).asData?.value;
    final ownName = me?.name ?? '';
    return Tooltip(
      message: widget.showSelfInfo ? '我的资料' : '账号',
      child: InkWell(
        onTap: _open,
        customBorder: const CircleBorder(),
        child: Padding(
          key: _anchorKey,
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AvatarView(
            name: ownName.isNotEmpty ? ownName : (auth.auth?.name ?? ''),
            avatarUrl: me?.avatarUrl,
            radius: 18,
            headType: me?.headType,
            headId: me?.headId,
            frameId: me?.frameId,
          ),
        ),
      ),
    );
  }
}

/// 账号菜单按钮：点击在自身位置弹出 [showAccountMenu]。
///
/// 横屏侧边栏底部使用（QQ/微信 风格：头像在上、菜单在下），与
/// [AccountAvatarButton] 打开同一菜单，仅外观不同；悬停提示为"菜单"。
/// 锚点矩形同样在点击时从自身 RenderBox 计算，逻辑与头像按钮保持一致。
class AccountMenuButton extends ConsumerStatefulWidget {
  const AccountMenuButton({super.key});

  @override
  ConsumerState<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState extends ConsumerState<AccountMenuButton> {
  /// 用于取得按钮在屏幕上的矩形，作为菜单锚点（逻辑同头像按钮）。
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await showAccountMenu(context, ref, anchor: anchor);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '菜单',
      child: IconButton(
        key: _anchorKey,
        onPressed: _open,
        icon: const Icon(Icons.menu),
      ),
    );
  }
}
