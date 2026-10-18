import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';

import 'app_tokens.dart';

/// 全局滚动行为：**关闭过度滚动（overscroll）指示器**。
///
/// Android + M3 下默认是 `StretchOverscrollIndicator`：在列表顶部继续下拉会把
/// 整个列表内容**纵向拉伸** —— 卡片被拉长、头像变成长方形、文字与卡片背景看起来
/// 互相错位，相邻的工具栏 / 分类栏附近也会出现内容外溢的观感（「内容与卡片错位」、
/// 「列表穿透到分类栏下面」）。这里返回 child 即不自带指示器，滚到边界即止。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// 全局主题：M3 tonal 色彩系统 + 统一圆角与描边。
///
/// 策略：
/// - 用 `ColorScheme.fromSeed` 从 [AppColors.brandSeed] 生成全部角色色
///   （`tonalSpot` variant），不再 copyWith 覆盖 primary/tertiary/on*；
///   高饱和 raw 色直接当角色色会破坏 M3 tonal palette，观感偏"霓虹"。
/// - 仅覆盖 `outlineVariant`，用于卡片 / 分隔线的低对比描边；
/// - M3 没有 success / warning 角色，由 [AppSemanticColors] ThemeExtension
///   从各自 seed 派生 tonal 语义色（随 brightness 变化）；
/// - 其余表面角色（surfaceContainer* 等）全部交给 `fromSeed` 生成。
///
/// 参数：
/// - [seedColor] 主题强调色（默认 [AppColors.brandSeed]）；由设置页选择，或在
///   「跟随系统取色」开启时由 `dynamicColorSeedProvider` 提供系统色（动态色作为
///   seed 再经 `fromSeed` 派生，即 M3 的 harmonize 语义：系统色胜出）。
/// - [contrastLevel] M3 对比度档位（[AppContrast]）；默认 [AppContrast.standard]
///   即 `0.0`，与旧输出逐位一致。
/// - [amoled] 纯黑模式：**仅深色模式生效**，把 `surface` 与整个 `surfaceContainer*`
///   家族压到 [AppColors.amoledBlack]，同时把 `surfaceTint` 置透明 —— 否则 M3 会按
///   高度叠加 primary 色调，纯黑会被染成灰色（`background` 已废弃、等价于 `surface`，
///   不再单独设置）。
///
/// 手选的强调色（`SettingsKeys.seedColor`）只在「跟随系统取色」关闭时生效。
ThemeData buildAppTheme(
  Brightness brightness, {
  Color? seedColor,
  bool amoled = false,
  double contrastLevel = AppContrast.standard,
}) {
  final isDark = brightness == Brightness.dark;

  var scheme =
      ColorScheme.fromSeed(
        seedColor: seedColor ?? AppColors.brandSeed,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
        contrastLevel: contrastLevel,
      ).copyWith(
        outlineVariant: isDark
            ? const Color(0x1FFFFFFF)
            : const Color(0x1F000000),
      );

  if (amoled && isDark) {
    scheme = scheme.copyWith(
      surface: AppColors.amoledBlack,
      surfaceDim: AppColors.amoledBlack,
      surfaceContainerLowest: AppColors.amoledBlack,
      surfaceContainerLow: AppColors.amoledBlack,
      surfaceContainer: AppColors.amoledBlack,
      surfaceContainerHigh: AppColors.amoledBlack,
      surfaceContainerHighest: AppColors.amoledBlack,
      surfaceTint: Colors.transparent,
    );
  }

  final border = BorderSide(color: scheme.outlineVariant);

  return ThemeData(
    useMaterial3: true,
    // 页面转场：M3 官方 animations 包的 SharedAxis 家族（横向推入，符合
    // "同级页面前进/返回"的语义）。桌面端也走同一套：默认的 Zoom 转场在宽屏上
    // 会整页缩放，观感突兀；iOS/macOS 保留系统式横向转场。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
        TargetPlatform.linux: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
        TargetPlatform.windows: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
        TargetPlatform.fuchsia: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
      },
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [AppSemanticColors.fromBrightness(brightness)],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // 标题栏整体压小一档：默认 M3 的 56 高度 + 22px 标题在手机上偏大。
      toolbarHeight: 48,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardR, side: border),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.panelR),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: const OutlineInputBorder(
        borderRadius: AppRadius.inputR,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: AppRadius.inputR,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputR,
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.55)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillR),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillR),
        side: border,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillR),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.chipR),
      side: border,
      backgroundColor: scheme.surfaceContainerHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.inputR),
    ),
  );
}
