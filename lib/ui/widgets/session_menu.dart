/// 会话卡片的浮动操作菜单（长按 / 桌面右键 / 头像信息卡「更多」入口）。
///
/// [showSessionMenu] 用 `showMenu` + 指针位置换算的 `RelativeRect` 弹出真正
/// 的浮动菜单（替代原底部弹窗），保留原有全部操作并新增「移除会话」：
/// 好友会话 = 上线通知 / 置顶 / 免打扰 / 备注 / 家园 / 移除会话 / 删除好友，
/// 群会话 = 置顶 / 免打扰 / 移除会话。
///
/// 移除会话由调用方通过 [onRemoved] 落库 / 刷新（本文件不持有会话列表状态）。
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/messages.dart';
import '../../core/storage/settings_store.dart';
import '../../state/providers.dart';
import '../player_home_page.dart';
import '../theme/app_tokens.dart';

/// 会话菜单操作项。
enum _SessionMenuAction { notify, pin, mute, note, home, remove, deleteFriend }

/// 在 [globalPosition]（长按 / 右键的指针全局坐标）弹出会话浮动菜单。
///
/// [onRemoved] 在用户选择「移除会话」后回调（由会话列表把该会话加入本地
/// 隐藏集合），其余操作就地完成。
Future<void> showSessionMenu(
  BuildContext context,
  WidgetRef ref, {
  required ChatSession session,
  required Offset globalPosition,
  VoidCallback? onRemoved,
}) async {
  final type = session.type;
  final uin = session.id;
  final isFriend = type == ChatSessionType.friend;
  // 锚点 / 主题在异步读取设置前先取好：await 之后只剩 showMenu 一处使用
  // context（由 context.mounted 守住），避免跨异步间隙继续解引用 context。
  final overlay = Overlay.of(context).context.findRenderObject();
  final overlaySize = overlay is RenderBox
      ? overlay.size
      : MediaQuery.sizeOf(context);
  final position = RelativeRect.fromRect(
    Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
    Offset.zero & overlaySize,
  );
  final theme = Theme.of(context);
  final errorColor = theme.colorScheme.error;

  final settings = ref.read(settingsProvider);
  final sessionKey2 = SettingsKeys.sessionKey(type.name, uin);
  final pinned = await settings.isPinned(sessionKey2);
  final muted = await settings.isMuted(sessionKey2);
  final notifyOn = isFriend ? await settings.friendOnlineNotify(uin) : false;
  if (!context.mounted) return;

  final action = await showMenu<_SessionMenuAction>(
    context: context,
    position: position,
    items: [
      // 上线通知（仅好友）
      if (isFriend)
        _menuItem(
          _SessionMenuAction.notify,
          notifyOn ? Icons.notifications_active : Icons.notifications_none,
          notifyOn ? '取消上线通知' : '上线通知',
          color: notifyOn ? theme.colorScheme.primary : null,
        ),
      // 置顶
      _menuItem(
        _SessionMenuAction.pin,
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        pinned ? '取消置顶' : '置顶',
        color: pinned ? theme.colorScheme.primary : null,
      ),
      // 免打扰
      _menuItem(
        _SessionMenuAction.mute,
        muted ? Icons.notifications_off : Icons.notifications_outlined,
        muted ? '取消免打扰' : '免打扰',
        color: muted ? theme.colorScheme.error : null,
      ),
      // 以下仅好友会话
      if (isFriend) ...[
        const PopupMenuDivider(),
        _menuItem(_SessionMenuAction.note, Icons.edit_note, '备注'),
        _menuItem(_SessionMenuAction.home, Icons.home_outlined, '家园'),
      ],
      const PopupMenuDivider(),
      _menuItem(_SessionMenuAction.remove, Icons.delete_outline, '移除会话'),
      if (isFriend)
        _menuItem(
          _SessionMenuAction.deleteFriend,
          Icons.person_remove_outlined,
          '删除好友',
          color: errorColor,
        ),
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _SessionMenuAction.notify:
      await settings.setFriendOnlineNotify(uin, !notifyOn);
      if (context.mounted) {
        _toast(context, notifyOn ? '已关闭上线通知' : '已开启上线通知');
      }
    case _SessionMenuAction.pin:
      await settings.setPinned(sessionKey2, !pinned);
      if (context.mounted) {
        _toast(context, pinned ? '已取消置顶' : '已置顶');
      }
    case _SessionMenuAction.mute:
      await settings.setMuted(sessionKey2, !muted);
      if (context.mounted) {
        _toast(context, muted ? '已取消免打扰' : '已开启免打扰');
      }
    case _SessionMenuAction.note:
      await _editFriendNote(context, ref, uin);
    case _SessionMenuAction.home:
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerHomePage(targetUin: uin),
          ),
        ),
      );
    case _SessionMenuAction.remove:
      onRemoved?.call();
    case _SessionMenuAction.deleteFriend:
      await _confirmRemoveFriend(context, ref, uin: uin, name: session.name);
  }
}

/// 菜单项：图标 + 文案，[color] 用于状态激活 / 危险项（如删除好友）。
PopupMenuItem<_SessionMenuAction> _menuItem(
  _SessionMenuAction action,
  IconData icon,
  String label, {
  Color? color,
}) {
  return PopupMenuItem<_SessionMenuAction>(
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

/// 轻提示。
void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

/// 备注编辑对话框：预填当前备注，确认后写入本地设置。
Future<void> _editFriendNote(
  BuildContext context,
  WidgetRef ref,
  int uin,
) async {
  final settings = ref.read(settingsProvider);
  final current = await settings.friendNote(uin);
  if (!context.mounted) return;
  final ctrl = TextEditingController(text: current ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('备注'),
      content: TextField(
        controller: ctrl,
        maxLength: 20,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '备注名',
          hintText: '输入备注名，留空则清除',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await settings.setFriendNote(uin, ctrl.text);
    if (context.mounted) {
      _toast(context, '备注已保存');
    }
  }
  ctrl.dispose();
}

/// 删除好友确认框；确认后调用 `buddysvr.buddy_rm`。
Future<void> _confirmRemoveFriend(
  BuildContext context,
  WidgetRef ref, {
  required int uin,
  required String name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除好友「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      );
    },
  );
  if (ok != true || !context.mounted) return;
  final removed = await ref.read(chatServiceProvider).removeFriend(uin);
  if (context.mounted) {
    _toast(context, removed ? '已删除好友' : '删除失败');
  }
}
