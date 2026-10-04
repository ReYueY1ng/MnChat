/// 设置 · 通用与外观子页。
///
/// 内容：主题显示设置入口、聊天气泡、会话排序、头像框动画，桌面端另有
/// 「关闭到托盘」。「聊天气泡」原本挂在设置页的「社交」分组下，但它本质是外观，
/// 归到这里。
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/services/tray_service.dart';
import '../state/providers.dart';
import 'bubble_page.dart';
import 'theme/app_tokens.dart';
import 'theme_settings_page.dart';
import 'widgets/settings_tiles.dart';

class SettingsGeneralPage extends ConsumerWidget {
  const SettingsGeneralPage({super.key});

  /// 桌面端（linux / windows）才显示托盘相关项。
  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _pickSortMode(BuildContext context, WidgetRef ref) async {
    final current = ref.read(sessionSortModeProvider);
    final picked = await showDialog<SessionSortMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('会话排序'),
        children: [
          for (final m in SessionSortMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Row(
                children: [
                  Expanded(child: Text(m.label)),
                  if (m == current) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(sessionSortModeProvider.notifier).setMode(picked);
    }
  }

  Future<void> _toggleCloseToTray(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    await ref.read(closeToTrayProvider.notifier).set(value);
    await TrayService.setCloseToTray(value);
    if (context.mounted) {
      showSettingsToast(
        context,
        value ? '关闭窗口时将最小化到托盘' : '关闭窗口时将直接退出',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('通用与外观')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SettingsSectionHeader('外观'),
              SettingsNavTile(
                icon: Icons.palette_outlined,
                title: '主题显示设置',
                subtitle: '明暗模式 / 强调色 / 聊天字号',
                page: const ThemeSettingsPage(),
              ),
              SettingsNavTile(
                icon: Icons.chat_bubble_outline,
                title: '聊天气泡',
                subtitle: '切换已拥有的聊天气泡',
                page: const BubblePage(),
              ),
              SettingsSwitchTile(
                icon: Icons.animation,
                title: '头像框动画',
                subtitle: '关闭后仅显示静态头像框，省电省流',
                value: ref.watch(animatedFramesProvider),
                onChanged: (v) =>
                    ref.read(animatedFramesProvider.notifier).set(v),
              ),

              const SettingsSectionHeader('会话'),
              SettingsNavTile(
                icon: Icons.sort,
                title: '会话排序',
                subtitle: ref.watch(sessionSortModeProvider).label,
                onTap: () => _pickSortMode(context, ref),
              ),

              if (_isDesktop) ...[
                const SettingsSectionHeader('桌面'),
                SettingsSwitchTile(
                  icon: Icons.close_fullscreen_outlined,
                  title: '关闭到托盘',
                  // 托盘注册失败时（Linux 上没跑 StatusNotifierWatcher）启动阶段已
                  // 自动关掉它；这里把原因写出来，否则用户会以为是设置没保存。
                  subtitle: TrayService.trayAvailable
                      ? '关闭窗口时最小化到系统托盘而非退出'
                      : '当前桌面没有可用的系统托盘，关闭窗口会直接退出（已自动关闭）',
                  value: ref.watch(closeToTrayProvider),
                  // 没有托盘就不允许打开：否则关窗后应用既不可见也召不回来。
                  onChanged: TrayService.trayAvailable
                      ? (v) => _toggleCloseToTray(context, ref, v)
                      : null,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
