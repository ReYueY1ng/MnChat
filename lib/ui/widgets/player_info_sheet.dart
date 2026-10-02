/// 好友信息卡与好友操作菜单。
///
/// - [showPlayerInfoSheet]：点击头像弹出的玩家简要信息底部弹窗
///   （头像/昵称/迷你号 + 等级/默契度/冒险家/称号/勋章 + 个人中心/置顶/赠送/更多）。
///   内容片段复用 `player_info_common.dart`（与浮窗同源）。
/// - [showFriendMenu]：长按 / 右键 / 信息卡「更多」共用的操作菜单
///   （上线通知/拍一拍/置顶/备注/家园/删除好友，会话列表另带免打扰）。
///
/// 备注（`cmd=set_note`）/ 上线通知（`cmd=set_online_notify_flag`）/ 置顶
/// （`cmd=set_sort_flag`）走**服务端同步**，同时写一份本地设置作为离线兜底；
/// 删除好友走 `buddysvr.buddy_rm`，拍一拍走 `cmd=take_pat`。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/messages.dart';
import '../../core/storage/settings_store.dart';
import '../../state/providers.dart';
import '../player_home_page.dart';
import '../theme/app_tokens.dart';
import 'gift_picker.dart' show showGiftPicker;
import 'player_info_common.dart';
import 'rich_text_view.dart';

/// 显示玩家简要信息底部弹窗。
///
/// 点击好友头像时调用：头像（含头像框）+ 昵称 + 迷你号 + 等级/默契度/
/// 冒险家/称号/勋章，下排四个操作按钮：个人中心 / 置顶 / 赠送 / 更多。
Future<void> showPlayerInfoSheet(
  BuildContext context,
  WidgetRef ref, {
  required int uin,
  required String name,
  String? avatarUrl,
  int? headType,
  int? headId,
  int? headFrameId,
}) async {
  final settings = ref.read(settingsProvider);
  final key = SettingsKeys.sessionKey(ChatSessionType.friend.name, uin);
  final pinned = await settings.isPinned(key);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerInfoHeader(
                uin: uin,
                name: name,
                avatarUrl: avatarUrl,
                headType: headType,
                headId: headId,
                headFrameId: headFrameId,
                radius: 40,
                reserveTitleLine: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              // 等级 + 默契度 + 冒险家 + 称号 + 勋章（与浮窗共用资料区）
              PlayerInfoStats(ref: ref, uin: uin),
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              // 操作行：个人中心 / 置顶 / 赠送 / 更多
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  PlayerCircleAction(
                    icon: Icons.person_outline,
                    label: '个人中心',
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerHomePage(targetUin: uin),
                          ),
                        ),
                      );
                    },
                  ),
                  PlayerCircleAction(
                    icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: pinned ? '取消置顶' : '置顶',
                    highlighted: pinned,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await settings.setPinned(key, !pinned);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(pinned ? '已取消置顶' : '已置顶')),
                      );
                    },
                  ),
                  PlayerCircleAction(
                    icon: Icons.card_giftcard,
                    label: '赠送',
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(
                        showGiftPicker(context, ref, uin: uin, name: name),
                      );
                    },
                  ),
                  PlayerCircleAction(
                    icon: Icons.more_horiz,
                    label: '更多',
                    // 与长按/右键共用同一套好友操作菜单
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(
                        showFriendMenu(context, ref, uin: uin, name: name),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 好友/会话操作菜单（长按 / 右键 / 信息卡「更多」共用）。
///
/// [type] 决定菜单项：好友会话额外提供上线通知 / 备注 / 家园 / 删除好友，
/// 群会话只保留置顶（[showMute] 为 true 时再带免打扰，供会话列表沿用旧入口）。
Future<void> showFriendMenu(
  BuildContext context,
  WidgetRef ref, {
  required int uin,
  required String name,
  ChatSessionType type = ChatSessionType.friend,
  bool showMute = false,
}) async {
  final settings = ref.read(settingsProvider);
  final key = SettingsKeys.sessionKey(type.name, uin);
  final isFriend = type == ChatSessionType.friend;
  final pinned = await settings.isPinned(key);
  final muted = showMute ? await settings.isMuted(key) : false;
  final notifyOn = isFriend ? await settings.friendOnlineNotify(uin) : false;
  if (!context.mounted) return;

  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: RichTextView(name), dense: true, enabled: false),
            const Divider(height: 1),
            // 上线通知（仅好友）
            if (isFriend)
              ListTile(
                leading: Icon(
                  notifyOn
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  color: notifyOn ? theme.colorScheme.primary : null,
                ),
                title: Text(notifyOn ? '取消上线通知' : '上线通知'),
                onTap: () => Navigator.pop(ctx, 'notify'),
              ),
            // 置顶
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: pinned ? theme.colorScheme.primary : null,
              ),
              title: Text(pinned ? '取消置顶' : '置顶'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            // 免打扰（会话列表原有入口，保留）
            if (showMute)
              ListTile(
                leading: Icon(
                  muted
                      ? Icons.notifications_off
                      : Icons.notifications_outlined,
                  color: muted ? theme.colorScheme.error : null,
                ),
                title: Text(muted ? '取消免打扰' : '免打扰'),
                onTap: () => Navigator.pop(ctx, 'mute'),
              ),
            // 以下仅好友会话
            if (isFriend) ...[
              ListTile(
                leading: const Icon(Icons.touch_app_outlined),
                title: const Text('拍一拍'),
                onTap: () => Navigator.pop(ctx, 'pat'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('备注'),
                onTap: () => Navigator.pop(ctx, 'note'),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('家园'),
                onTap: () => Navigator.pop(ctx, 'home'),
              ),
              ListTile(
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  '删除好友',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ],
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'notify':
      final on = !notifyOn;
      await settings.setFriendOnlineNotify(uin, on);
      final synced = await _serverSync(
        () => ref.read(chatServiceProvider).setFriendOnlineNotify(uin, on: on),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              synced
                  ? (on ? '已开启上线通知' : '已关闭上线通知')
                  : '上线通知同步失败（已本地生效）',
            ),
          ),
        );
      }
    case 'pat':
      var ok = false;
      try {
        ok = await ref.read(chatServiceProvider).patFriend(uin);
      } catch (_) {
        ok = false;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '已拍一拍' : '拍一拍失败')),
        );
      }
    case 'pin':
      final top = !pinned;
      await settings.setPinned(key, top);
      final synced = await _serverSync(
        () => ref.read(chatServiceProvider).setFriendTop(uin, top: top),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              synced
                  ? (top ? '已置顶' : '已取消置顶')
                  : '置顶同步失败（已本地生效）',
            ),
          ),
        );
      }
    case 'mute':
      await settings.setMuted(key, !muted);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(muted ? '已取消免打扰' : '已开启免打扰')));
      }
    case 'note':
      await _editFriendNote(context, ref, uin);
    case 'home':
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlayerHomePage(targetUin: uin)),
        ),
      );
    case 'remove':
      await _confirmRemoveFriend(context, ref, uin: uin, name: name);
  }
}

/// 执行一次服务端同步；成功返回 true，失败返回 false（不抛出）。
/// 调用方负责在 await 后用 `context.mounted` 守卫再提示。
Future<bool> _serverSync(Future<Object?> Function() call) async {
  try {
    await call();
    return true;
  } catch (_) {
    return false;
  }
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
    final synced = await _serverSync(
      () => ref.read(chatServiceProvider).setFriendNote(uin, ctrl.text.trim()),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(synced ? '备注已保存' : '备注同步失败（已本地保存）')),
      );
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(removed ? '已删除好友' : '删除失败')));
  }
}
