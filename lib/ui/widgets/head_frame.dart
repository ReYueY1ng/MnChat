import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/animated_frames.dart';
import '../../state/providers.dart' show animatedFramesProvider;

/// 游戏头像框资源路径。
///
/// 带骨骼动画的 id（[kAnimatedFrameIds]）返回 `assets/headframes_anim/<id>.webp`
/// 循环动画；其余返回 `assets/headframes/<id>.webp` 静态图（128×128 RGBA，
/// 中心透明，取自客户端 `res/resources/ui/headframes/`）。
///
/// 未收录的 id 由 [Image.errorBuilder] 静默忽略，因此不需要维护 id 白名单。
String headFrameAsset(int id) => kAnimatedFrameIds.contains(id)
    ? 'assets/headframes_anim/$id.webp'
    : 'assets/headframes/$id.webp';

/// 该头像框是否使用动画资源。
bool headFrameIsAnimated(int id) => kAnimatedFrameIds.contains(id);

/// 静态头像框资源路径（关闭动画时使用）。
String headFrameStaticAsset(int id) => 'assets/headframes/$id.webp';

/// 有头像框时，头像本体边长相对头像框盒的缩放比例（官方头像 70 : 框 92）。
///
/// 依据：
/// 1. 头像框资源为 128×128、图案铺满整块画布，其中间透明开口实测中位数约
///    85/128 ≈ 0.664；若头像与框同尺寸（`radius * 2`），圆环会被挤进头像内部，
///    无法真正包围头像（用户反馈「头像框没有完全包围头像」）。
/// 2. 官方客户端 UI XML 中头像框始终是与头像同心、零偏移且更大的兄弟节点，
///    最常见的一组为头像 70px / 框 92px，即头像 = 框盒的 70/92 ≈ 0.76
///    （`ui/mobile/mvc/commoncomp/uicommon.xml`、
///    `ui/mobile/mvc/home/.../homelandchat.xml`）；其余组介于 1.23x~1.45x，
///    从不存在 1:1。
///
/// 取 0.76 时，框内开口边缘（0.664）与头像外边缘（0.76）每侧重叠约 5%，
/// 与官方观感一致（框略微压住头像，无缝隙）。
const double kHeadFrameAvatarInset = 0.76;

/// 头像框槽位边长：头像本体始终为 `radius * 2`，框盒按 1 / [kHeadFrameAvatarInset]
/// 放大（≈1.316x），让 128×128 的框图案完整包围头像。
///
/// 由 [kHeadFrameAvatarInset] 的推导：框内透明开口仅约 0.664，而框外圈铺满画布，
/// 若框盒只与头像等大，圆环会压进头像内部；把槽位放大到 `radius * 2 / 0.76`
/// 后开口边缘才会略微压住头像本体。[radius] 保持原义（头像本体半边长），
/// 因此所有调用方都不需要改动自己的 `radius` 参数。
double headFrameSlotSize(double radius) => radius * 2 / kHeadFrameAvatarInset;

/// 承载带头像框头像的 `ListTile`（含 `CheckboxListTile`）所需的纵向密度。
///
/// `ListTile` 会把 leading / trailing / secondary 的高度上限钳制为
/// `(isDense ? 48 : 56) + visualDensity.dy`，且宽度是松约束；桌面默认紧凑
/// 密度为 (-2, -2)（dy = -8），上限只有 48，会把有框槽位
/// （[headFrameSlotSize]，radius=24 时约 63.2）压成非正方形，并被
/// `BoxFit.cover` 裁掉头像框外圈。
///
/// 把纵向提高到 +3（dy = +12）后上限为 68，足以容纳槽位；横向保持 -2，
/// 与主题一致，不改变横向间距。
///
/// 注意：不要用 `OverflowBox` 绕过钳制——它的自身尺寸会膨胀到父约束的
/// 最大宽度，触发 `ListTile` 的「Leading widget consumes the entire tile
/// width」断言（见 friends_page 的运行时崩溃）。
const VisualDensity kAvatarListTileDensity = VisualDensity(
  horizontal: -2,
  vertical: 3,
);

/// 叠加在头像之上的头像框（无框 / id 缺失时渲染为空）。
class HeadFrameOverlay extends ConsumerWidget {
  final int? frameId;
  final double size;

  const HeadFrameOverlay({super.key, required this.frameId, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = frameId;
    if (id == null || id <= 0) return const SizedBox.shrink();
    // 关闭「头像框动画」时统一退回静态 PNG（省电 / 省流）。
    final animated =
        headFrameIsAnimated(id) && ref.watch(animatedFramesProvider);
    return Image.asset(
      animated ? headFrameAsset(id) : headFrameStaticAsset(id),
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      // 动画 WebP 不设置 cacheWidth，避免解码缩放影响动画播放。
      cacheWidth: animated ? null : (size * 2).round(),
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
