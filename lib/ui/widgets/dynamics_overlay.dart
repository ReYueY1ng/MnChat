/// 打开「某人的动态」浮层。
///
/// 个人主页里的动态入口不该直接跳到全局动态页（那是四个分类的聚合页），
/// 而应该就地给一个只含对方动态的浮层：
/// - 窄屏（手机）：铺满整页 —— 手机上没有「浮」的空间；
/// - 宽屏：居中浮动卡片（带遮罩，点外面关掉）。
library;

import 'package:material_ui/material_ui.dart';

import '../dynamics_page.dart';
import '../theme/app_tokens.dart';

/// 宽屏阈值：与动态列表的瀑布流分栏阈值保持一致。
const double kDynamicsOverlayWideWidth = 700;

/// 展示 [authorUin] 的动态（[authorName] 只用于标题）。
Future<void> showAuthorDynamics(
  BuildContext context, {
  required int authorUin,
  String? authorName,
}) {
  final page = DynamicsPage(authorUin: authorUin, authorName: authorName);
  final wide = MediaQuery.sizeOf(context).width >= kDynamicsOverlayWideWidth;
  if (!wide) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: size.height * 0.82,
          ),
          // 复用整页实现：里面自带 AppBar（返回箭头会关掉这个浮层）。
          child: page,
        ),
      );
    },
  );
}
