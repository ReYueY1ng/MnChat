/// 设置页通用行组件 —— 分组标题 / 开关行 / 导航行。
///
/// 设置页拆成「顶层 + 5 个子页」后，这几行被 6 个文件共用，因此从
/// `settings_page.dart` 提出来放进 widgets/（见 lib/ui/AGENTS.md：
/// 共享组件放 widgets/，不要跟着页面走）。
///
/// 约定：
/// - 开关行用 `ListTile + 尾部 Switch`（而非 `SwitchListTile`），这样整行
///   `onTap` 仍然可用 —— 免打扰那种「点标题取时间段、点开关切启用」的行靠它；
/// - `onChanged == null` 表示不可交互（例如配置还没读完），同时把副标题换成
///   说明文案，避免「点了没反应」。
library;

import 'package:material_ui/material_ui.dart';

import '../theme/app_tokens.dart';

/// 设置页统一吐司（2 秒）—— 动作完成后给一句确定反馈。
void showSettingsToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
  );
}

/// 分组标题（账号与安全 / 通用与外观 / …）。
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
        6,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// 开关行。
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// 跳转到子页面（或触发任意动作）的行。
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.page,
    this.onTap,
  }) : assert(page != null || onTap != null, '至少给 page 或 onTap 之一');

  final IconData icon;
  final String title;
  final String subtitle;

  /// 点击后 push 的页面；与 [onTap] 二选一。
  final Widget? page;

  /// 自定义点击行为（对话框 / 需要 context 的动作）；
  /// 与 [page] 二选一，同时给出时以 [onTap] 为准。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ??
            () {
              final target = page;
              if (target == null) return;
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => target));
            },
      ),
    );
  }
}

/// 只读信息行（版本号 / 占用大小那种）。
class SettingsInfoTile extends StatelessWidget {
  const SettingsInfoTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
      ),
    );
  }
}
