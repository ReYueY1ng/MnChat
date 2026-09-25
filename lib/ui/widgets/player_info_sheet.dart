/// 好友信息卡与好友操作菜单。
///
/// - [showPlayerInfoSheet]：点击头像弹出的玩家简要信息底部弹窗
///   （头像/昵称/迷你号/称号占位 + 个人中心/置顶/赠送/更多）。
/// - [showFriendMenu]：长按 / 右键 / 信息卡「更多」共用的操作菜单
///   （上线通知/置顶/备注/家园/删除好友，会话列表另带免打扰）。
///
/// 备注 / 上线通知 / 置顶均走本地设置 [SettingsStore]，删除好友走
/// `buddysvr.buddy_rm`；不涉及服务端的 set_note / set_online_notify_flag。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/messages.dart';
import '../../core/models/medal_catalog.dart';
import '../../core/storage/settings_store.dart';
import '../../state/providers.dart';
import '../player_home_page.dart';
import '../theme/app_tokens.dart';
import 'avatar_view.dart';
import 'rich_text_view.dart';

/// 显示玩家简要信息底部弹窗。
///
/// 点击好友头像时调用：头像（含头像框）+ 昵称 + 迷你号 + 称号占位，
/// 下排四个操作按钮：个人中心 / 置顶 / 赠送 / 更多。
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
      final theme = Theme.of(ctx);
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
              // 头部：头像 + 昵称 + 迷你号 + 称号
              Row(
                children: [
                  AvatarView(
                    avatarUrl: avatarUrl,
                    name: name,
                    radius: 40,
                    headType: headType,
                    headId: headId,
                    frameId: headFrameId,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichTextView(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Uin: $uin',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // 称号名称在下方信息行展示（需远程 visual-cfg）
                        const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // 等级 + 默契度 + 冒险家 + 称号（远程 visual-cfg）
              FutureBuilder<
                (int, Map<String, Object?>?, Map<String, Object?>?, String?)
              >(
                future: () async {
                  final svc = ref.read(chatServiceProvider);
                  final level = await svc.platformLevel(uin);
                  final home = await svc.userHomepage(uin);
                  final score = await svc.otherPlayerScore(uin);
                  final tid = _useTitleId(home);
                  final title = tid > 0 ? await svc.titleName(tid) : null;
                  return (level, home, score, title);
                }(),
                builder: (ctx2, snap) {
                  final level = snap.data?.$1 ?? 0;
                  final home = snap.data?.$2;
                  final score = snap.data?.$3;
                  final title = snap.data?.$4;
                  final tacit = _tacitnumFor(home, uin);
                  final adv = score == null
                      ? '--'
                      : '${score['name'] ?? ''} ${score['level'] ?? ''}'.trim();
                  final medals = _medalList(home);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (level > 0)
                            _infoChip(
                              theme,
                              Icons.workspace_premium_outlined,
                              'Lv$level',
                              color: theme.colorScheme.tertiary,
                            ),
                          _infoChip(
                            theme,
                            Icons.favorite_border,
                            '默契度：$tacit',
                            color: Colors.pinkAccent,
                          ),
                          _infoChip(
                            theme,
                            Icons.military_tech_outlined,
                            '冒险家：$adv',
                            color: theme.colorScheme.primary,
                          ),
                          _infoChip(
                            theme,
                            Icons.local_police_outlined,
                            '称号：${title ?? '未佩戴'}',
                            color: theme.colorScheme.tertiary,
                          ),
                        ],
                      ),
                      // 勋章行（最多 6 枚，图标 + 等级边框）
                      if (medals.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final m in medals.take(6))
                                _medalBadge(theme, m.$1, m.$2),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              // 操作行：个人中心 / 置顶 / 赠送 / 更多
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _CircleAction(
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
                  _CircleAction(
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
                  _CircleAction(
                    icon: Icons.card_giftcard,
                    label: '赠送',
                    onTap: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('暂未开放')));
                    },
                  ),
                  _CircleAction(
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
      await settings.setFriendOnlineNotify(uin, !notifyOn);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(notifyOn ? '已关闭上线通知' : '已开启上线通知')),
        );
      }
    case 'pin':
      await settings.setPinned(key, !pinned);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pinned ? '已取消置顶' : '已置顶')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('备注已保存')));
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

/// 从主页 `partner` 模块取与指定好友的默契度（无匹配则退回首项，仍无则 0）。
int _tacitnumFor(Map<String, Object?>? home, int uin) {
  final partner = home?['partner'];
  if (partner is! List) return 0;
  int? fallback;
  for (final e in partner) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final t = m['tacitnum'];
    final tv = t is num ? t.toInt() : int.tryParse('$t') ?? 0;
    final bu = m['bestUin'];
    final buv = bu is num ? bu.toInt() : int.tryParse('$bu') ?? 0;
    if (buv == uin) return tv;
    fallback ??= tv;
  }
  return fallback ?? 0;
}

/// 从主页 `title` 模块取当前佩戴称号 id（`title.data.match_title.use_title.id`）。
int _useTitleId(Map<String, Object?>? home) {
  final title = home?['title'];
  if (title is! Map) return 0;
  final data = title['data'];
  if (data is! Map) return 0;
  final match = data['match_title'];
  if (match is! Map) return 0;
  final use = match['use_title'];
  if (use is! Map) return 0;
  final id = use['id'] ?? use['ID'];
  if (id is num) return id.toInt();
  return int.tryParse('$id') ?? 0;
}

/// 信息行内的小项：图标 + 文本。
Widget _infoChip(ThemeData theme, IconData icon, String text, {Color? color}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
      const SizedBox(width: 4),
      Text(text, style: theme.textTheme.bodySmall),
    ],
  );
}

/// 从主页 `achieve` 模块取勋章列表（`achieve.data.medal_list` → [(id, level)]）。
List<(int, int)> _medalList(Map<String, Object?>? home) {
  final achieve = home?['achieve'];
  if (achieve is! Map) return const [];
  final data = achieve['data'];
  if (data is! Map) return const [];
  final list = data['medal_list'];
  if (list is! List) return const [];
  final out = <(int, int)>[];
  for (final e in list) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final id = m['id'];
    final lv = m['level'];
    final idv = id is num ? id.toInt() : int.tryParse('$id') ?? 0;
    final lvv = lv is num ? lv.toInt() : int.tryParse('$lv') ?? 0;
    if (idv > 0) out.add((idv, lvv));
  }
  return out;
}

/// 单枚勋章：普通勋章=图标+等级边框；isNew 勋章=按等级的徽章图标（40×40）。
Widget _medalBadge(ThemeData theme, int id, int level) {
  final lvlIcons = kMedalLevelIcons[id];
  if (lvlIcons != null && lvlIcons.isNotEmpty) {
    final idx = (level >= 1 && level <= lvlIcons.length) ? level - 1 : 0;
    return SizedBox(
      width: 40,
      height: 40,
      child: Image.asset(
        medalIconAsset(lvlIcons[idx]),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
  final icon = kMedalIconName[id];
  final frame = (level >= 1 && level <= kMedalFrameByLevel.length)
      ? kMedalFrameByLevel[level - 1]
      : null;
  return SizedBox(
    width: 40,
    height: 40,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (icon != null)
          Image.asset(
            medalIconAsset(icon),
            width: 30,
            height: 30,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (frame != null)
          Image.asset(
            medalIconAsset(frame),
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
      ],
    ),
  );
}

/// 信息卡操作按钮：圆形图标 + 文字标签。
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 激活态（如已置顶）用主题色高亮。
  final bool highlighted;

  const _CircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onTap,
          tooltip: label,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: highlighted
                ? theme.colorScheme.primaryContainer
                : null,
            foregroundColor: highlighted
                ? theme.colorScheme.onPrimaryContainer
                : null,
          ),
          icon: Icon(icon),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}
