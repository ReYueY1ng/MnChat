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
    if (level <= 0 && p == null && !isVip && tacit == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (level > 0) LevelBadge(level: level),
        if (tacit != null) ...[
          const SizedBox(width: AppSpacing.xs),
          TacitBadge(tacitnum: tacit, lab: tacitLab, levels: levels),
        ],
        if (isVip) ...[
          const SizedBox(width: AppSpacing.xs),
          const VipBadge(),
        ],
      ],
    );
  }
}

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
