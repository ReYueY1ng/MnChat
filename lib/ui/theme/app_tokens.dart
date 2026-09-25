import 'package:material_ui/material_ui.dart';

/// 设计 token —— 间距 / 圆角 / 语义色 / 尺寸 的唯一来源。
///
/// 之前颜色、圆角（4/6/12/14/16/18/20 混用）、间距散落在各页面里各写各的，
/// 导致观感不统一。新代码请优先引用这里的常量；旧代码按需替换。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const EdgeInsets pagePadding = EdgeInsets.all(16);
  static const EdgeInsets cardPadding = EdgeInsets.all(16);
  static const EdgeInsets listTilePadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 8,
  );
}

abstract final class AppRadius {
  static const double chip = 8;
  static const double input = 12;
  static const double card = 18;
  static const double panel = 22;
  static const double pill = 999;

  static const BorderRadius chipR = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius inputR = BorderRadius.all(Radius.circular(input));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius panelR = BorderRadius.all(Radius.circular(panel));
  static const BorderRadius pillR = BorderRadius.all(Radius.circular(pill));
}

/// M3 色彩 seed —— 仅作为 ColorScheme.fromSeed 的输入，不再直接当作角色色。
abstract final class AppColors {
  /// 品牌 seed（MnChat 绿，取迷你世界启动器图标的方块材质绿）。
  static const Color brandSeed = Color(0xFF108850);

  /// M3 没有 success / warning 角色，用独立 seed 派生 tonal 语义色。
  static const Color successSeed = Color(0xFF4CAF50);
  static const Color warningSeed = Color(0xFFFFA000);
}

/// M3 语义色扩展 —— success / warning 在 M3 ColorScheme 里没有对应角色，
/// 因此用各自 seed 经 `ColorScheme.fromSeed` 派生出随 brightness 变化的
/// tonal 值，并通过 ThemeExtension 挂到主题上。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  factory AppSemanticColors.fromBrightness(Brightness brightness) {
    final s = ColorScheme.fromSeed(
      seedColor: AppColors.successSeed,
      brightness: brightness,
    );
    final w = ColorScheme.fromSeed(
      seedColor: AppColors.warningSeed,
      brightness: brightness,
    );
    return AppSemanticColors(
      success: s.primary,
      onSuccess: s.onPrimary,
      successContainer: s.primaryContainer,
      onSuccessContainer: s.onPrimaryContainer,
      warning: w.primary,
      onWarning: w.onPrimary,
      warningContainer: w.primaryContainer,
      onWarningContainer: w.onPrimaryContainer,
    );
  }

  /// 关键：测试里存在只用裸 MaterialApp（未套 buildAppTheme）的 widget 测试，
  /// 此时 extension 不存在。必须 fallback 到按当前 brightness 现算，禁止返回 null 崩溃。
  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        AppSemanticColors.fromBrightness(theme.brightness);
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
    );
  }
}

/// 宽屏内容约束：避免卡片在 2K/4K 下横向拉满。
abstract final class AppSizes {
  /// 设置 / 详情 / 个人主页等单列内容。
  static const double narrowContent = 760;

  /// 列表页内容。
  static const double listContent = 1000;
}

/// 是否为「紧凑宽度」（手机）。判据用最短边 < 600dp（Material 的 compact
/// width class）——横屏手机最短边仍是 ~400dp，故横屏也算手机，
/// 从而始终保住触控目标尺寸。
bool isCompactWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide < 600;

/// 自适应触控密度：手机用 [VisualDensity.standard]（保住 ≥48dp 触控目标），
/// 桌面 / 平板保留紧凑密度。
VisualDensity adaptiveDensity(BuildContext context) =>
    isCompactWidth(context) ? VisualDensity.standard : VisualDensity.compact;

/// 弹窗内容宽度：桌面用 [preferred]，窄屏不超出可用宽度。
///
/// `AlertDialog` 默认左右各留 40dp 边距，故可用宽度 = 屏宽 - 80；
/// 硬编码宽度（如 420）在 360dp 手机上会溢出。
double dialogContentWidth(BuildContext context, double preferred) {
  final available = MediaQuery.sizeOf(context).width - 80;
  if (available >= preferred) return preferred;
  return available > 0 ? available : 0;
}

/// 弹窗内容高度：桌面用 [preferred]，矮屏（手机横屏）按屏高的
/// [fraction]（默认一半）收敛，避免连同标题/按钮一起溢出。
double dialogContentHeight(
  BuildContext context,
  double preferred, {
  double fraction = 0.5,
}) {
  final available = MediaQuery.sizeOf(context).height * fraction;
  return available < preferred ? available : preferred;
}
