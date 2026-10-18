/// 统一空态与错误重试卡片。
///
/// 仓库里各页此前各写各的空态（图标 + 标题 + 副标题），字号/间距/颜色不一致；
/// 这里收敛成一个组件，全部走 `AppSpacing` / `AppSemanticColors` token。
///
/// 错误态刻意做成"可见的失败 + 明确的重试"：本项目明确不接受"数据静默降级成
/// 空列表"（见 `widgets/request_error_indicator.dart` 的既有口径），因此渲染
/// 错误文案本身，而不是伪装成空数据。
library;

import 'package:material_ui/material_ui.dart';

import '../theme/app_tokens.dart';
/// 空状态：图标 + 一句人话 + 可选提示 + 可选主行动。
class EmptyState extends StatelessWidget {
  /// 顶部图标。
  final IconData icon;

  /// 主文案（一句人话，如「还没有收藏的消息」）。
  final String title;

  /// 副文案（可选，告诉用户下一步怎么做）。
  final String? hint;

  /// 主行动（可选按钮）。
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误 + 重试卡片：显示真正的失败原因（含可选的技术细节）与一个重试按钮。
class ErrorRetryCard extends StatelessWidget {
  /// 面向用户的一句话（如「加载失败」）。
  final String message;

  /// 技术细节（错误码 / 端点 / 原始异常），可折叠展示。
  final String? detail;

  /// 重试回调。
  final VoidCallback onRetry;

  const ErrorRetryCard({
    super.key,
    required this.message,
    required this.onRetry,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 44,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            if (detail != null && detail!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                detail!.trim(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
