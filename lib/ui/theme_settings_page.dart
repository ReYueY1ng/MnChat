import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/settings_tiles.dart';

/// 主题显示设置页：集中调整主题模式、强调色与聊天字号。
///
/// 顶部预览卡片会跟随当前强调色、明暗模式与聊天字号即时刷新：
/// 用户切换任意选项时无需离开页面，就能看到聊天气泡配色和字号的变化。
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  /// 强调色预设；首项为品牌绿（与 [AccentColorNotifier.defaultSeed] 一致）。
  static const List<Color> _accentPresets = [
    Color(0xFF108850),
    Color(0xFF6750A4),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(appThemeModeProvider);
    final accent = ref.watch(accentColorProvider);
    final fontScale = ref.watch(chatFontScaleProvider);
    final rawText = ref.watch(richTextRawProvider);

    // 用当前强调色 + 当前明暗模式现算预览配色，无需等待全局主题重建。
    final previewScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: theme.brightness,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('主题显示设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _previewCard(context, previewScheme, fontScale),
              const SizedBox(height: AppSpacing.md),
              _themeModeCard(context, ref, mode),
              const SizedBox(height: AppSpacing.md),
              _accentCard(context, ref, accent),
              const SizedBox(height: AppSpacing.md),
              _appearanceCards(context, ref, theme.brightness),
              const SizedBox(height: AppSpacing.md),
              _fontScaleCard(context, ref, fontScale),
              const SizedBox(height: AppSpacing.md),
              _rawTextCard(context, ref, rawText),
            ],
          ),
        ),
      ),
    );
  }

  /// 实时预览卡片：用当前配色画一对模拟聊天气泡。
  Widget _previewCard(
    BuildContext context,
    ColorScheme scheme,
    double fontScale,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview_outlined, color: scheme.primary),
                const SizedBox(width: AppSpacing.md),
                Text('实时预览', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: _bubble(
                scheme.surfaceContainerHighest,
                scheme.onSurface,
                '你好，这是对方的示例消息。',
                fontScale,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: _bubble(
                scheme.primary,
                scheme.onPrimary,
                '收到！这是我的回复。',
                fontScale,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个模拟气泡。
  Widget _bubble(
    Color background,
    Color foreground,
    String text,
    double fontScale,
  ) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.inputR,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 15 * fontScale, color: foreground),
      ),
    );
  }

  /// 主题模式：跟随系统 / 浅色 / 深色。
  Widget _themeModeCard(BuildContext context, WidgetRef ref, AppThemeMode mode) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.brightness_6_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Text('主题模式', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text('跟随系统'),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('浅色'),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('深色'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => ref
                    .read(appThemeModeProvider.notifier)
                    .setMode(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 强调色：一组圆形色块，选中项加边框与对勾。
  Widget _accentCard(BuildContext context, WidgetRef ref, Color selected) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.md),
                Text('强调色', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final color in _accentPresets)
                  _accentSwatch(context, ref, color, selected),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 单个强调色圆形色块。
  Widget _accentSwatch(
    BuildContext context,
    WidgetRef ref,
    Color color,
    Color selected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = color == selected;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Tooltip(
      message: _hex(color),
      child: InkWell(
        onTap: () => ref.read(accentColorProvider.notifier).set(color),
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? scheme.primary
                  : scheme.outlineVariant,
              width: isSelected ? 3 : 1,
            ),
          ),
          child: isSelected
              ? Icon(Icons.check, size: 20, color: onColor)
              : null,
        ),
      ),
    );
  }

  /// 外观增强：AMOLED 纯黑（仅深色）/ M3 高对比度 / 跟随系统取色。
  ///
  /// 三行都复用 `widgets/settings_tiles.dart` 的 [SettingsSwitchTile]（自带 Card），
  /// 与其余设置子页保持同一套行样式。
  Widget _appearanceCards(BuildContext context, WidgetRef ref, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final amoled = ref.watch(appAmoledProvider);
    final highContrast = ref.watch(appHighContrastProvider);
    final dynamicColor = ref.watch(dynamicColorEnabledProvider);
    return Column(
      children: [
        SettingsSwitchTile(
          icon: Icons.contrast,
          title: '纯黑模式（AMOLED）',
          subtitle: isDark
              ? '深色模式下背景改用纯黑，OLED 屏更省电、观感更沉'
              : '仅深色模式生效（当前为浅色模式）',
          value: amoled,
          onChanged: isDark
              ? (v) => ref.read(appAmoledProvider.notifier).set(v)
              : null,
        ),
        SettingsSwitchTile(
          icon: Icons.brightness_high_outlined,
          title: '高对比度',
          subtitle: '提高前景 / 背景对比（M3 高对比档），弱视或强光下更易读',
          value: highContrast,
          onChanged: (v) =>
              ref.read(appHighContrastProvider.notifier).set(v),
        ),
        SettingsSwitchTile(
          icon: Icons.auto_awesome_outlined,
          title: '跟随系统取色',
          subtitle: 'Android 跟随壁纸取色、Linux 跟随桌面主题色；开启后上面的强调色不再生效',
          value: dynamicColor,
          onChanged: (v) =>
              ref.read(dynamicColorEnabledProvider.notifier).set(v),
        ),
      ],
    );
  }

  /// 聊天字号：0.8 ~ 1.6 缩放，含实时示例与恢复默认。
  Widget _fontScaleCard(
    BuildContext context,
    WidgetRef ref,
    double fontScale,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_size, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.md),
                Text('聊天字号', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${fontScale.toStringAsFixed(1)}×',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            Slider(
              value: fontScale,
              min: ChatFontScaleNotifier.min,
              max: ChatFontScaleNotifier.max,
              divisions: 8,
              label: '${fontScale.toStringAsFixed(1)}×',
              onChanged: (v) => ref.read(chatFontScaleProvider.notifier).set(v),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.inputR,
              ),
              child: Text(
                '示例：这条消息会随字号缩放。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16 * fontScale,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: fontScale == 1.0
                    ? null
                    : () => ref.read(chatFontScaleProvider.notifier).set(1.0),
                icon: const Icon(Icons.restart_alt),
                label: const Text('恢复默认'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 富文本显示原文本：开启后昵称等不再解析标签，直接显示源字符串。
  Widget _rawTextCard(BuildContext context, WidgetRef ref, bool rawText) {
    final theme = Theme.of(context);
    return Card(
      child: SwitchListTile(
        secondary: Icon(Icons.code, color: theme.colorScheme.primary),
        title: const Text('富文本显示原文本'),
        subtitle: const Text('开启后，[i][color][b] 等游戏标签原样显示，不再渲染颜色、加粗或表情'),
        value: rawText,
        onChanged: (v) => ref.read(richTextRawProvider.notifier).set(v),
      ),
    );
  }

  /// 颜色转 `#RRGGBB` 文本。
  static String _hex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
