/// 主题矩阵 golden 测试 —— 证明 `buildAppTheme` 在「强调色 seed × 亮度」上都稳定渲染。
///
/// 覆盖 3 个 seed（brand / success / warning，均取自 `AppColors`）× 2 种亮度，
/// 每格都是同一个**只用设计 token** 拼出的代表性表面：AppBar（标题）+
/// Card（两个 ListTile）+ FilledButton + Chip（含 `AppSemanticColors` 语义色）
/// + TextField。不依赖任何 `*_page.dart`，因此不需要 provider / 数据库。
///
/// 字体（CJK）决策：`flutter_test` 默认只注册 FlutterTest 字体（每个字形都画成
/// 方块）。为了让 golden 里出现真字形，这里依赖 alchemist 自带的
/// `loadFonts()`：它读取测试资产包的 `FontManifest.json`，把 alchemist 包声明的
/// `packages/alchemist/Roboto` 注册成 `Roboto` 族（字体字节随 alchemist 版本固定，
/// 与本机系统字体无关），而 Material 默认排版族就是 `Roboto`，正好命中。
/// 代价是 **Roboto 不含 CJK 字形**：本文件所有文案只用 ASCII，写中文会渲染成
/// 豆腐块。等 lead 的 amoled / contrastLevel 参数落地后，矩阵在这里追加变体即可。
///
/// golden 落在 `test/golden/goldens/`（不带平台子目录），CI（Ahem 方块字）
/// 变体关闭。重新生成：
/// `fvm flutter test --update-goldens test/golden/theme_golden_test.dart`。
library;

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/theme/app_tokens.dart';

/// 主题矩阵的一个强调色变体：即 [buildAppTheme] 的 `seedColor` 取值。
class _AccentVariant {
  const _AccentVariant({
    required this.slug,
    required this.seed,
    required this.label,
  });

  /// 文件名与场景名里的小写标识（ASCII）。
  final String slug;

  /// 传给 `buildAppTheme(seedColor:)` 的强调色种子。
  final Color seed;

  /// 场景标签（ASCII）。
  final String label;
}

/// 矩阵的 3 个强调色变体，seed 全部来自 [AppColors]。
const List<_AccentVariant> _accentVariants = <_AccentVariant>[
  _AccentVariant(slug: 'brand', seed: AppColors.brandSeed, label: 'brand seed'),
  _AccentVariant(
    slug: 'success',
    seed: AppColors.successSeed,
    label: 'success seed',
  ),
  _AccentVariant(
    slug: 'warning',
    seed: AppColors.warningSeed,
    label: 'warning seed',
  ),
];

/// 亮度顺序固定为 light → dark，不依赖 `Brightness.values` 的枚举次序。
const List<Brightness> _brightnesses = <Brightness>[
  Brightness.light,
  Brightness.dark,
];

/// golden 落盘路径：`test/golden/goldens/<fileName>.png`，附在测试文件同级目录下。
String _goldenPath(String fileName, String environmentName) =>
    'goldens/$fileName.png';

/// 测试字体族：alchemist 的 `loadFonts()` 把包内 Roboto 注册为 `Roboto` 族。
const String _testFontFamily = 'Roboto';

/// 给主题里**没写 `fontFamily`** 的样式补上测试字体族。
///
/// 主题里的排版绝大多数走 `textTheme`（Material 默认族就是 Roboto，测试环境能命中），
/// 但 `appBarTheme.titleTextStyle` 只写了字号/字重/颜色 —— 族名是 null 时会退回
/// FlutterTest 方块字，AppBar 标题会在 golden 里变成一排黑方块。这里只补族名，
/// 字号 / 字重 / 颜色仍由 `buildAppTheme` 决定，断言的东西不变。
ThemeData _withTestFont(ThemeData theme) {
  final titleStyle = theme.appBarTheme.titleTextStyle;
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: titleStyle?.copyWith(fontFamily: _testFontFamily),
    ),
  );
}

/// 只用设计 token 拼出的代表性表面。
///
/// 必须自带 `material_ui` 的 [MaterialApp]：alchemist 的外壳只提供
/// `package:flutter/material.dart` 的 `MaterialLocalizations`，而 `material_ui`
/// 的 `RawChip` 找的是自己那一份（两者是不同类型），缺了会直接 build 失败。
Widget _themeSurface({required Brightness brightness, required Color seed}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _withTestFont(buildAppTheme(brightness, seedColor: seed)),
    home: Builder(
      builder: (BuildContext context) {
        final semantic = AppSemanticColors.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('MNChat theme matrix')),
          body: Padding(
            padding: AppSpacing.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Card(
                  child: Column(
                    children: <Widget>[
                      const ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text('Alpha'),
                        subtitle: Text('first row'),
                      ),
                      const ListTile(
                        leading: Icon(Icons.group_outlined),
                        title: Text('Beta'),
                        subtitle: Text('second row'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    FilledButton(onPressed: () {}, child: const Text('Send')),
                    const Chip(label: Text('Chip')),
                    Chip(
                      backgroundColor: semantic.successContainer,
                      label: Text(
                        'OK',
                        style: TextStyle(color: semantic.onSuccessContainer),
                      ),
                    ),
                    Chip(
                      backgroundColor: semantic.warningContainer,
                      label: Text(
                        'Warn',
                        style: TextStyle(color: semantic.onWarningContainer),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const TextField(
                  decoration: InputDecoration(hintText: 'Message'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// alchemist 场景标签的外边距。
///
/// `GoldenTestTheme.standard()` 的 padding 是 0，标签文字的第一行上升部会被图片上边缘
/// 切掉；这里只改 padding，颜色与标签字号仍取标准值（alchemist 0.14.1 的 `copyWith`
/// 返回类型写成了 `ThemeExtension<GoldenTestTheme>`，无法直接复用，故重建实例）。
GoldenTestTheme _goldenTestTheme() {
  final standard = GoldenTestTheme.standard();
  return GoldenTestTheme(
    backgroundColor: standard.backgroundColor,
    borderColor: standard.borderColor,
    nameTextStyle: standard.nameTextStyle,
    padding: const EdgeInsets.all(AppSpacing.sm),
  );
}

/// alchemist 配置：可读文本（Roboto）平台变体写进 `goldens/`，CI 方块字变体关闭。
final AlchemistConfig _config = AlchemistConfig(
  platformGoldensConfig: const PlatformGoldensConfig(
    filePathResolver: _goldenPath,
  ),
  ciGoldensConfig: const CiGoldensConfig(enabled: false),
  goldenTestTheme: _goldenTestTheme(),
);

void main() {
  AlchemistConfig.runWithConfig(
    config: _config,
    run: () {
      group('theme matrix golden', () {
        for (final variant in _accentVariants) {
          goldenTest(
            'renders stably with the ${variant.slug} accent',
            fileName: 'theme_${variant.slug}',
            builder: () => GoldenTestGroup(
              columns: _brightnesses.length,
              scenarioConstraints: const BoxConstraints.tightFor(
                width: 360,
                height: 400,
              ),
              children: <Widget>[
                for (final brightness in _brightnesses)
                  GoldenTestScenario(
                    name: '${variant.label} / ${brightness.name}',
                    child: _themeSurface(
                      brightness: brightness,
                      seed: variant.seed,
                    ),
                  ),
              ],
            ),
          );
        }
      });
    },
  );
}
