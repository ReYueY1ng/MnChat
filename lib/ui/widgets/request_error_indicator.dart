/// 请求失败提示 UI：常驻角标 + 详情弹窗 + 失败吐司。
///
/// 解决「请求静默降级成空数据，不知道哪个请求挂了」：失败记录统一进
/// `RequestErrorBus`（见 core/services/request_errors.dart），这里负责展示：
///
/// - [RequestErrorIndicator]：有失败时显示一个角标按钮（`3 个请求失败`），
///   点开是详情弹窗（标签 / 地址 / 业务码 + 释义 / 服务端 msg / 时间 / 次数），
///   可一键清空。没有失败时完全不占位。
/// - [RequestErrorListener]：包住页面，每条**新**失败弹一次吐司，点「详情」看列表。
///
/// 挂载点：`MainShell`（两个 Scaffold 的 `floatingActionButton` + 外层包 listener）。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/request_errors.dart';
import '../../state/providers.dart' show requestErrorBusProvider;
import '../theme/app_tokens.dart';

/// 打开「最近的请求失败」详情弹窗。
Future<void> showRequestErrorsDialog(
  BuildContext context,
  RequestErrorBus bus,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _RequestErrorsDialog(bus: bus),
  );
}

/// 单条失败的完整信息：完整 URL + 可复制 + 可选中。
///
/// 列表行里的地址按行截断，而定位一个失败请求全靠查询串后半段
/// （`cmd` / 业务参数 / `ver`），截断了等于没信息。
Future<void> showRequestFailureDetail(
  BuildContext context,
  RequestFailure f,
) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(f.summary),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  f.endpoint.isEmpty ? '(无请求地址)' : f.endpoint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                if (f.message.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(f.message, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${f.label} · ${f.code == null ? '无业务码' : 'code=${f.code}'}'
                  '${f.count > 1 ? ' · 出现 ${f.count} 次' : ''} · ${f.at}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: f.endpoint.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: f.endpoint));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('已复制请求地址')),
                    );
                  },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制地址'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

/// 常驻角标：无失败时不显示（返回 `null`，可直接放进 Scaffold 的
/// `floatingActionButton`）。
class RequestErrorIndicator extends ConsumerWidget {
  const RequestErrorIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bus = ref.watch(requestErrorBusProvider);
    return ValueListenableBuilder<List<RequestFailure>>(
      valueListenable: bus.failures,
      builder: (context, failures, _) {
        if (failures.isEmpty) return const SizedBox.shrink();
        final colors = AppSemanticColors.of(context);
        final total = failures.fold<int>(0, (n, f) => n + f.count);
        return FloatingActionButton.extended(
          heroTag: 'request-error-indicator',
          backgroundColor: colors.warningContainer,
          foregroundColor: colors.onWarningContainer,
          icon: const Icon(Icons.error_outline),
          label: Text('$total 个请求失败'),
          tooltip: failures.first.summary,
          onPressed: () => showRequestErrorsDialog(context, bus),
        );
      },
    );
  }
}

/// 监听失败流并弹吐司。包住需要提示的子树即可。
class RequestErrorListener extends ConsumerStatefulWidget {
  const RequestErrorListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RequestErrorListener> createState() =>
      _RequestErrorListenerState();
}

class _RequestErrorListenerState extends ConsumerState<RequestErrorListener> {
  StreamSubscription<RequestFailure>? _sub;

  @override
  void initState() {
    super.initState();
    // 延到首帧后再订阅：initState 里 ScaffoldMessenger 还不能用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bus = ref.read(requestErrorBusProvider);
      _sub = bus.stream.listen(_onFailure);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onFailure(RequestFailure f) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${f.summary}${f.message.isEmpty ? '' : '：${f.message}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 6),
          // 浮起 + 抬高底边：本监听器包在 MainShell 的 Scaffold **外面**，
          // 应用级 ScaffoldMessenger 并不知道里层 Scaffold 的 FAB，默认的
          // fixed 行为会把 toast 直接压在右下角「N 个请求失败」角标上
          // （实测那段时间角标点不动）。76 = FAB 底距 16 + 高度 48 + 间距 12。
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: 76,
          ),
          action: SnackBarAction(
            label: '详情',
            onPressed: () =>
                showRequestErrorsDialog(context, ref.read(requestErrorBusProvider)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RequestErrorsDialog extends StatelessWidget {
  const _RequestErrorsDialog({required this.bus});

  final RequestErrorBus bus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('请求失败记录'),
      content: SizedBox(
        width: 560,
        // 高度随内容收缩（shrinkWrap + maxHeight）：只有一条记录时不再撑出
        // 一大片空白。
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ValueListenableBuilder<List<RequestFailure>>(
            valueListenable: bus.failures,
            builder: (context, failures, _) {
              if (failures.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: Text('暂无失败记录')),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: failures.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final f = failures[i];
                  return ListTile(
                    dense: true,
                    onTap: () => showRequestFailureDetail(context, f),
                    title: Text(
                      f.count > 1 ? '${f.summary} ×${f.count}' : f.summary,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (f.endpoint.isNotEmpty)
                          Text(
                            f.endpoint,
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (f.message.isNotEmpty)
                          Text(
                            f.message,
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          _formatTime(f.at),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => bus.clear(),
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
