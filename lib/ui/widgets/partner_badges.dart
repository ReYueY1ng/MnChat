/// 昵称旁的小徽标：平台等级 `Lv<N>`、默契度六边形、大会员 VIP。
///
/// 全部为内联小控件，不改变宿主行（ListTile）的高度与内边距；美术资源：
/// 游戏内的六边形 / VIP 图标位于 FGUI 图集（`bestpartner_atlas0.png` 等），
/// 未拆分为可直接打包的小图，故此处用 Material `Icons.hexagon` + 文本胶囊
/// 近似绘制。真实美术仍需从图集拆分后再替换。
library;

import 'package:material_ui/material_ui.dart';

import '../../core/services/partner.dart';
import '../theme/app_tokens.dart';

/// 等级配色表（覆盖 0..6，更高回退默认橙）。
///
/// 官方等级色表未从资源中导出 RGB，这里为近似值；数值协议不受影响。
const List<Color> _kLevelColors = <Color>[
  Color(0xFF9E9E9E), // 0
  Color(0xFF4CAF50), // 1
  Color(0xFF26A69A), // 2
  Color(0xFF29B6F6), // 3
  Color(0xFF7E57C2), // 4
  Color(0xFFEC407A), // 5
  Color(0xFFFF7043), // 6
];

/// 等级超出色表时的默认色（橙）。
const Color kLevelFallbackColor = Color(0xFFFF9800);

/// 等级徽标颜色；[level] < 0 或超出表长回退 [kLevelFallbackColor]。
Color levelBadgeColor(int level) =>
    (level >= 0 && level < _kLevelColors.length)
    ? _kLevelColors[level]
    : kLevelFallbackColor;

/// 默契度六边形颜色（按拍档类型 `lab` 着色，未知回退绿色）。
Color tacitBadgeColor(int lab) {
  switch (lab) {
    case 1:
      return const Color(0xFF43A047); // 挚友
    case 2:
      return const Color(0xFF00897B); // 知己
    case 3:
      return const Color(0xFFD81B60); // 姐妹
    case 4:
      return const Color(0xFF1E88E5); // 兄弟
    case 5:
      return const Color(0xFF8E24AA); // 闺蜜
    case 6:
      return const Color(0xFFFB8C00); // 兄妹
    case 7:
    case 100:
      return const Color(0xFF00A86B); // 最佳拍档
    default:
      return const Color(0xFF00A86B);
  }
}

/// `Lv<N>` 等级徽标。
class LevelBadge extends StatelessWidget {
  final int level;

  const LevelBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = levelBadgeColor(level);
    return _Pill(
      background: color.withValues(alpha: 0.16),
      border: color,
      child: Text(
        'Lv$level',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

/// 默契度徽标：六边形图标 + 数值（拍档类型决定颜色）。
///
/// [levels] 为关系等级阈值（升序）；非空时在数值右侧内联一条细进度条，
/// 高度不超过原胶囊，故不改变宿主行高。为空 / null 时只显示数值。
class TacitBadge extends StatelessWidget {
  final int tacitnum;
  final int lab;

  /// 关系等级阈值（升序）；空 / null → 不画进度条（配置未获取）。
  final List<(int level, int intimacyValue)>? levels;

  const TacitBadge({
    super.key,
    required this.tacitnum,
    this.lab = 0,
    this.levels,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tacitBadgeColor(lab);
    final cfg = levels ?? const <(int, int)>[];
    final (_, next) = partnerLevelFor(tacitnum, cfg);
    final ratio = next > 0 ? (tacitnum / next).clamp(0.0, 1.0) : null;
    return Tooltip(
      message: next <= 0
          ? '默契度 · ${PartnerLab.name(lab)}'
          : '默契度 · ${PartnerLab.name(lab)}（$tacitnum/$next）',
      child: _Pill(
        background: color.withValues(alpha: 0.16),
        border: color,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hexagon, size: 9, color: color),
            const SizedBox(width: 2),
            Text(
              '$tacitnum',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            if (ratio != null) ...[
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: 28,
                height: 4,
                child: ClipRRect(
                  borderRadius: AppRadius.pillR,
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 4,
                    backgroundColor: color.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 大会员徽标（昵称旁的金色 VIP 小胶囊）。
class VipBadge extends StatelessWidget {
  const VipBadge({super.key});

  static const Color _gold = Color(0xFFB8860B);
  static const Color _goldText = Color(0xFF8A6D00);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '大会员',
      child: _Pill(
        background: const Color(0xFFFFC107).withValues(alpha: 0.22),
        border: _gold,
        child: Text(
          'VIP',
          style: theme.textTheme.labelSmall?.copyWith(
            color: _goldText,
            fontWeight: FontWeight.w800,
            height: 1.0,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// 昵称后的一串徽标：`Lv<N>` + 默契度（仅拍档）+ VIP（仅大会员）。
///
/// 无任何徽标时渲染 `SizedBox.shrink`，不占宽度。
///
/// **名字优先**：列表行把它放进 `Flexible` 后，这里只按可用宽度装入装得下的
/// 徽标（用 [TextPainter] 实测文字宽度估算，按优先级依次降级），所以永远不会
/// 溢出、也不会反过来把同行的昵称挤成一个省略号 ——
/// 修的就是「默契度/VIP/等级把好友名字挤出屏幕」这个现象。
class PartnerNameBadges extends StatelessWidget {
  final int level;
  final PartnerInfo? partner;
  final bool isVip;

  /// 关系等级阈值（升序）；空 / null → 默契度徽标不画进度条。
  final List<(int level, int intimacyValue)>? levels;

  /// 显式指定默契度（**每个好友都有**，非拍档是 0/不显示拍档样式）。
  ///
  /// 传了就按它渲染（配色由 [lab] 决定）；不传则用 [partner] 自带的。
  final int? tacitnum;
  final int lab;

  const PartnerNameBadges({
    super.key,
    this.level = 0,
    this.partner,
    this.isVip = false,
    this.levels,
    this.tacitnum,
    this.lab = 0,
  });

  @override
  Widget build(BuildContext context) {
    final p = partner;
    // 没有拍档信息时也用显式传进来的默契度（游戏里每行都显示）。
    final tacit = tacitnum ?? p?.tacitnum;
    final tacitLab = tacitnum != null ? lab : (p?.lab ?? 0);
    final hasLevel = level > 0;
    final hasTacit = tacit != null;
    final hasVip = isVip;
    if (!hasLevel && !hasTacit && !hasVip) return const SizedBox.shrink();

    final style = Theme.of(context).textTheme.labelSmall;
    double textW(String s) => _measureText(context, s, style);

    Widget levelBadge() => LevelBadge(level: level);
    Widget tacitBadge({required bool bar}) =>
        TacitBadge(tacitnum: tacit!, lab: tacitLab, levels: bar ? levels : null);
    const Widget vipBadge = VipBadge();

    final levelW = _kPillChromeWidth + textW('Lv$level') + _kPillWidthSlack;
    final tacitNoBarW =
        _kPillChromeWidth + _kTacitIconWidth + textW('$tacit') + _kPillWidthSlack;
    final tacitBarW =
        tacitNoBarW + _kTacitBarWidth + _kPillWidthSlack;
    final vipW = _kPillChromeWidth + textW('VIP') + _kPillWidthSlack;

    /// 按优先级排列的候选组合：装不下就依次降级，最后只剩最有用的一项。
    final candidates = <List<(Widget, double)>>[
      [
        if (hasLevel) (levelBadge(), levelW),
        if (hasTacit) (tacitBadge(bar: true), tacitBarW),
        if (hasVip) (vipBadge, vipW),
      ],
      [
        if (hasLevel) (levelBadge(), levelW),
        if (hasTacit) (tacitBadge(bar: false), tacitNoBarW),
        if (hasVip) (vipBadge, vipW),
      ],
      [
        if (hasTacit) (tacitBadge(bar: false), tacitNoBarW),
        if (hasVip) (vipBadge, vipW),
      ],
      [
        if (hasTacit) (tacitBadge(bar: false), tacitNoBarW),
        if (hasLevel) (levelBadge(), levelW),
      ],
      [if (hasTacit) (tacitBadge(bar: false), tacitNoBarW)],
      [if (hasLevel) (levelBadge(), levelW)],
      [if (hasVip) (vipBadge, vipW)],
    ];

    Widget render(List<(Widget, double)> picked) {
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < picked.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            picked[i].$1,
          ],
        ],
      );
      // 兜底：估算再保守也挡不住字体细节差异（实测被 2.7dp 误差咬过一次）。
      // `FittedBox` 给子节点无界宽度布局，超出时整体轻微缩小（舍位），
      // 既不报 RenderFlex 溢出、也不像 OverflowBox 那样弄坏 semantics 几何。
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: row,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 无界宽（例如主页标题行）→ 全量渲染，由宿主自行约束。
        if (!constraints.hasBoundedWidth) return render(candidates.first);
        final budget = constraints.maxWidth;
        for (final c in candidates) {
          if (c.isEmpty) continue;
          final needed = c.fold<double>(
                0,
                (sum, e) => sum + e.$2,
              ) +
              AppSpacing.xs * (c.length - 1);
          if (needed <= budget) return render(c);
        }
        // 连一枚都放不下：让位给昵称。
        return const SizedBox.shrink();
      },
    );
  }
}

/// 列表行里的「徽标槽位」：按行宽给徽标设一个硬上限，把宽度让给昵称。
///
/// 为什么需要它：`Row` 给**非 flex 子节点**的是「主轴无界」约束，所以
/// [PartnerNameBadges] 内部的 `LayoutBuilder` 拿不到行宽（实测
/// `constraints=unconstrained`）→ 它会按固有宽度吃完一行，窄屏（360dp）实测
/// 把昵称挤到 **0 宽**。所以行宽必须由调用方（`LayoutBuilder`）显式传进来。
///
/// 上限 = `min(rowWidth * 0.4, rowWidth - 120)`：昵称 + 关系胶囊至少留 120dp。
class PartnerBadgeSlot extends StatelessWidget {
  const PartnerBadgeSlot({required this.rowWidth, required this.child, super.key});

  /// 同行可用总宽度（含昵称 / 徽标 / 关系胶囊）。
  final double rowWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ratio = (rowWidth * 0.4).clamp(0.0, 240.0);
    final reserved = (rowWidth - _kNameReserve).clamp(0.0, double.infinity);
    final max = ratio < reserved ? ratio : reserved;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: child,
    );
  }

  /// 给昵称 + 关系胶囊预留的宽度。
  static const double _kNameReserve = 120;
}

/// 用 [TextPainter] 实测一段单行文本的宽度（含系统字体缩放）。
///
/// 徽标取舍需要“放不放得下”的量化依据；直接量比写死阈值可靠。
double _measureText(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

/// 徽标估算用的尺寸常量（与 [_Pill] / [TacitBadge] 内部保持一致）。
///
/// `_Pill` 内边距 5×2 + 描边 0.8×2；默契度胶囊另有六边形 9 + 间距 2，
/// 带进度条时再加 [AppSpacing.xs] + 28。
const double _kPillChromeWidth = 11.6;
const double _kTacitIconWidth = 11;
const double _kTacitBarWidth = AppSpacing.xs + 28;

/// 每枚徽标估算宽度的余量（dp）。
///
/// 胶囊描边、`labelSmall` 的 letterSpacing、图标字体的行盒四舍五入都不在
/// [TextPainter] 的文字宽度里；实测（MiSans + 真机密度）风格差异能到 2.7dp，
/// 估算一旦偏小就会触发 RenderFlex 溢出。留 4dp 余量。
const double _kPillWidthSlack = 4;

/// 统一样式的小胶囊：细描边 + 半透明底 + 紧凑内边距。
class _Pill extends StatelessWidget {
  final Color background;
  final Color border;
  final Widget child;

  const _Pill({
    required this.background,
    required this.border,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.chipR,
        border: Border.all(color: border, width: 0.8),
      ),
      child: child,
    );
  }
}
