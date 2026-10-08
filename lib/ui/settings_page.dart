/// 设置页（顶层）—— 只有「账号卡 + 5 个分组入口 + 退出登录」。
///
/// 之前这里是一张 30 条的清单：9 个「功能入口」（个人资料 / 交友标签 / 关注与粉丝 /
/// 附近的人 / 聊天气泡 / 退群记录 / 聊天记录 …）和 14 个开关混在一屏里滚动。
/// 现在按「先搬入口、再拆子页」整理：
///
/// - 功能入口回到各自的宿主：资料类进「账号与安全」，聊天气泡进「通用与外观」，
///   社交发现类进好友页；
/// - 真设置按 5 个分组拆成子页；顶层每行右侧直接给出该组的当前状态摘要，
///   省掉「进去才知道现在是什么」的那一次点击。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_info.dart';
import '../core/models/nickname.dart' show plainNickname;
import '../state/providers.dart';
import 'settings_about_page.dart';
import 'settings_account_page.dart';
import 'settings_general_page.dart';
import 'settings_notification_page.dart';
import 'settings_privacy_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart';
import 'widgets/settings_tiles.dart';

/// 设置页：账号卡 + 分组入口（真正的内容在 5 个子页里）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 主题模式的中文名（顶层摘要用）。
  static String themeModeLabel(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => '跟随系统',
    AppThemeMode.light => '浅色',
    AppThemeMode.dark => '深色',
  };

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
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
    if (confirmed != true || !context.mounted) return;
    ref.read(authProvider.notifier).logout();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    final lockOn = ref.watch(lockEnabledProvider);
    final mode = ref.watch(appThemeModeProvider);
    final notifyOn = ref.watch(notifyEnabledProvider);
    final dndOn = ref.watch(dndEnabledProvider);
    final dndWindow = ref.watch(dndWindowProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _accountCard(context, ref, auth),

              const SettingsSectionHeader('账号'),
              SettingsNavTile(
                icon: Icons.manage_accounts_outlined,
                title: '账号与安全',
                subtitle: lockOn ? '应用锁已开启' : '个人资料 / 交友标签 / 自动登录',
                page: const SettingsAccountPage(),
              ),

              const SettingsSectionHeader('偏好'),
              SettingsNavTile(
                icon: Icons.palette_outlined,
                title: '通用与外观',
                subtitle: '${themeModeLabel(mode)} · 主题 / 字号 / 气泡 / 会话排序',
                page: const SettingsGeneralPage(),
              ),
              SettingsNavTile(
                icon: Icons.notifications_outlined,
                title: '消息与通知',
                subtitle: notifyOn
                    ? (dndOn ? '通知开 · 免打扰 ${dndWindow.label}' : '通知开 · 未设免打扰')
                    : '通知已关闭',
                page: const SettingsNotificationPage(),
              ),
              SettingsNavTile(
                icon: Icons.shield_outlined,
                title: '隐私与数据',
                subtitle: '加好友限制 / 访问踪迹 / 聊天记录 / 存储占用',
                page: const SettingsPrivacyPage(),
              ),

              const SettingsSectionHeader('其他'),
              SettingsNavTile(
                icon: Icons.info_outline,
                title: '关于 MnChat',
                subtitle: 'v$kAppVersion · 检查更新 / 开源许可 / 诊断导出',
                page: const SettingsAboutPage(),
              ),

              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: () => _logout(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  /// 账号卡：本人头像（与聊天页 / 侧栏同源：DIY 头像 / 头像本体 / 头像框）
  /// + 富文本昵称 + Uin。
  Widget _accountCard(BuildContext context, WidgetRef ref, AuthState auth) {
    final theme = Theme.of(context);
    final name = plainNickname(auth.auth?.name);
    // 本人头像与聊天页同源（DIY 头像 / 头像本体 / 头像框）—— 这个位置原先只画
    // 一个首字母 CircleAvatar，所以永远只显示首字，也没有头像框。
    final me = ref.watch(myAvatarInfoProvider).asData?.value;
    final ownName = me?.name ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            AvatarView(
              name: ownName.isNotEmpty ? ownName : name,
              avatarUrl: me?.avatarUrl,
              radius: 28,
              headType: me?.headType,
              headId: me?.headId,
              frameId: me?.frameId,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichTextView(
                    auth.auth?.name ?? '',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Uin: ${auth.auth?.uin ?? '-'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
