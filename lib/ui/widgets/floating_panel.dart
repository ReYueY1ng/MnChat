/// 浮动面板 —— 贴着锚点弹出的圆角面板（游戏里的表情 / 礼物面板都是这种）。
///
/// 与整屏的 `showModalBottomSheet` 不同：
/// - 宽屏：面板**浮在锚点上方**并水平居中（对齐反编译 `ChatEmojiView:SetAligment`
///   —— `x = anchor.centerX - panelWidth/2`、`y = anchor.top - panelHeight`），
///   点面板外任意处关闭（透明遮罩）；
/// - 窄屏（手机）：没有"浮"的空间，铺满底部（保留圆角与拖手感）。
library;

import 'package:material_ui/material_ui.dart';

import '../theme/app_tokens.dart';

/// 窄屏阈值：低于此宽度就铺满底部。
const double kFloatingPanelWideWidth = 600;

/// 弹出浮动面板。[anchor] 为锚点（通常是触发按钮）的屏幕矩形；为 null 时
/// 居中弹出。返回 [builder] 通过 `close(value)` 关闭时带回的值。
Future<T?> showFloatingPanel<T>(
  BuildContext context, {
  required Widget Function(BuildContext ctx, void Function([T? value]) close)
  builder,
  Rect? anchor,
  double width = 460,
  double heightFactor = 0.55,
}) {
  final size = MediaQuery.sizeOf(context);
  final wide = size.width >= kFloatingPanelWideWidth;

  if (!wide) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: size.height * heightFactor,
          child: Builder(
            builder: (inner) =>
                builder(inner, ([v]) => Navigator.of(inner).pop(v)),
          ),
        ),
      ),
    );
  }

  final panelWidth = width.clamp(280.0, size.width - AppSpacing.lg * 2);
  final panelHeight = size.height * heightFactor;
  final rect = anchor ?? Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
  final left = (rect.center.dx - panelWidth / 2).clamp(
    AppSpacing.lg,
    (size.width - panelWidth - AppSpacing.lg).clamp(
      AppSpacing.lg,
      double.infinity,
    ),
  );
  // 锚点偏上 → 往下弹；否则浮在锚点上方（与玩家浮窗同一套翻转逻辑）。
  final below = rect.center.dy <= size.height / 2;

  return showDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => Stack(
      children: [
        Positioned(
          left: left,
          top: below ? rect.bottom + AppSpacing.sm : null,
          bottom: below ? null : size.height - rect.top + AppSpacing.sm,
          width: panelWidth,
          child: Material(
            elevation: 8,
            color: Theme.of(ctx).colorScheme.surfaceContainerLow,
            borderRadius: AppRadius.cardR,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: panelHeight),
              child: Builder(
                builder: (inner) =>
                    builder(inner, ([v]) => Navigator.of(inner).pop(v)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
