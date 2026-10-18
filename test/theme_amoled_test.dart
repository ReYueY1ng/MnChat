// 主题收尾三件套的行为断言：
// - AMOLED 纯黑（深色专属，且 surfaceTint 必须透明，否则 M3 高程染色会把黑染成灰）
// - M3 高对比度：contrastLevel 1.0 必须与默认 0.0 产出不同配色
// - 跟随系统取色：平台不支持时退化为 null，且默认关闭时不触碰平台通道
// 另附 AppSemanticColors.of 的裸 MaterialApp 回退守卫（历史上在这里崩过 widget 测试）。
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/theme/app_tokens.dart';
import 'package:mnchat/ui/theme_settings_page.dart';

void main() {
  group('AMOLED 纯黑模式', () {
    test('深色 + amoled：surface 与 surfaceContainer* 均为纯黑，surfaceTint 透明', () {
      final scheme = buildAppTheme(
        Brightness.dark,
        amoled: true,
      ).colorScheme;

      expect(scheme.surface, const Color(0xFF000000));
      expect(scheme.surfaceTint, Colors.transparent);
      expect(scheme.surfaceContainerLowest, const Color(0xFF000000));
      expect(scheme.surfaceContainerLow, const Color(0xFF000000));
      expect(scheme.surfaceContainer, const Color(0xFF000000));
      expect(scheme.surfaceContainerHigh, const Color(0xFF000000));
      expect(scheme.surfaceContainerHighest, const Color(0xFF000000));
      // 脚手架底色取自 surface，必须跟着变黑。
      expect(
        buildAppTheme(Brightness.dark, amoled: true).scaffoldBackgroundColor,
        const Color(0xFF000000),
      );
    });

    test('默认深色主题不是纯黑（证明开关真的在切）', () {
      final scheme = buildAppTheme(Brightness.dark).colorScheme;
      expect(scheme.surface, isNot(const Color(0xFF000000)));
      expect(scheme.surfaceContainerLow, isNot(const Color(0xFF000000)));
      expect(scheme.surfaceTint, isNot(Colors.transparent));
    });

    test('amoled 在浅色模式下不生效（深色专属）', () {
      final plain = buildAppTheme(Brightness.light).colorScheme;
      final amoled = buildAppTheme(Brightness.light, amoled: true).colorScheme;
      expect(amoled.surface, plain.surface);
      expect(amoled.surfaceContainerLow, plain.surfaceContainerLow);
    });

    test('amoled 保留 tonalSpot 与 outlineVariant 的既有行为', () {
      final scheme = buildAppTheme(Brightness.dark, amoled: true).colorScheme;
      expect(scheme.outlineVariant, const Color(0x1FFFFFFF));
      // 其余角色仍由 fromSeed 派生（不是手挑的原始色）。
      expect(
        scheme.primary,
        buildAppTheme(Brightness.dark).colorScheme.primary,
      );
    });
  });

  group('M3 高对比度', () {
    test('contrastLevel 1.0 与默认 0.0 产出不同配色', () {
      final standard = buildAppTheme(Brightness.light).colorScheme;
      final high = buildAppTheme(
        Brightness.light,
        contrastLevel: AppContrast.high,
      ).colorScheme;
      expect(high, isNot(equals(standard)));
      expect(high.primary, isNot(standard.primary));
      expect(high.onSurface, isNot(standard.onSurface));
      expect(high.outline, isNot(standard.outline));
      // 浅色下的 surface（tone 98）在高对比档下不变，改由 foreground / container 体现对比。
      expect(high.surfaceContainerHigh, isNot(standard.surfaceContainerHigh));
    });

    test('默认 contrastLevel 就是旧输出（0.0）', () {
      expect(
        buildAppTheme(Brightness.dark).colorScheme,
        equals(buildAppTheme(Brightness.dark, contrastLevel: 0.0).colorScheme),
      );
    });

    test('高对比度与 AMOLED 可叠加', () {
      final scheme = buildAppTheme(
        Brightness.dark,
        amoled: true,
        contrastLevel: AppContrast.high,
      ).colorScheme;
      expect(scheme.surface, const Color(0xFF000000));
      expect(scheme.surfaceTint, Colors.transparent);
    });
  });

  group('跟随系统取色 / 设置持久化', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('三个开关默认关闭，且默认不读平台动态色', () async {
      expect(container.read(appAmoledProvider), isFalse);
      expect(container.read(appHighContrastProvider), isFalse);
      expect(container.read(dynamicColorEnabledProvider), isFalse);
      // 关闭时不触碰平台通道：直接返回 null（用户手选强调色继续生效）。
      expect(await container.read(dynamicColorSeedProvider.future), isNull);
    });

    test('开关写入后落库并立即生效', () async {
      final amoled = container.read(appAmoledProvider.notifier);
      final contrast = container.read(appHighContrastProvider.notifier);
      final dynamicColor = container.read(dynamicColorEnabledProvider.notifier);

      // set() 是乐观更新：写入前状态已生效（不等异步落库完成）。
      final writes = Future.wait([
        amoled.set(true),
        contrast.set(true),
        dynamicColor.set(true),
      ]);
      expect(container.read(appAmoledProvider), isTrue);
      expect(container.read(appHighContrastProvider), isTrue);
      expect(container.read(dynamicColorEnabledProvider), isTrue);
      await writes;

      expect(await db.getSetting(ThemeSettingsKeys.amoled), '1');
      expect(await db.getSetting(ThemeSettingsKeys.highContrast), '1');
      expect(await db.getSetting(ThemeSettingsKeys.dynamicColor), '1');
    });

    test('已落库的开关在全新容器里能读回', () async {
      await container.read(appAmoledProvider.notifier).set(true);

      final fresh = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(fresh.dispose);
      // build() 先给默认值，异步读取完后才更新成落库值。
      expect(fresh.read(appAmoledProvider), isFalse);
      await pumpEventQueue();
      expect(fresh.read(appAmoledProvider), isTrue);
      expect(fresh.read(appHighContrastProvider), isFalse);
    });

    test('开启取色但平台不支持时退化为 null（不抛异常）', () async {
      await container.read(dynamicColorEnabledProvider.notifier).set(true);
      // 测试环境没有注册 dynamic_color 插件，OptionalMethodChannel 返回 null。
      expect(await container.read(dynamicColorSeedProvider.future), isNull);
    });
  });

  group('AppSemanticColors 回退', () {    testWidgets('裸 MaterialApp（未挂 extension）下 of() 仍返回语义色', (tester) async {
      late AppSemanticColors colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.brandSeed),
          ),
          home: Builder(
            builder: (context) {
              colors = AppSemanticColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final expected = AppSemanticColors.fromBrightness(Brightness.light);
      expect(colors.success, expected.success);
      expect(colors.warning, expected.warning);
      expect(colors.onSuccessContainer, expected.onSuccessContainer);
    });
  });

  group('主题设置页外观开关', () {
    testWidgets('三行开关渲染出来，且写回设置', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: const ThemeSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('纯黑模式（AMOLED）'), findsOneWidget);
      expect(find.text('高对比度'), findsOneWidget);
      expect(find.text('跟随系统取色'), findsOneWidget);

      Switch switchIn(String title) => tester.widget<Switch>(
        find.descendant(
          of: find.ancestor(
            of: find.text(title),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(Switch),
        ),
      );

      // 浅色模式下 AMOLED 行不可交互（深色专属）。
      expect(switchIn('纯黑模式（AMOLED）').onChanged, isNull);
      expect(switchIn('高对比度').onChanged, isNotNull);

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('高对比度'),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(await db.getSetting(ThemeSettingsKeys.highContrast), '1');

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('跟随系统取色'),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(await db.getSetting(ThemeSettingsKeys.dynamicColor), '1');
    });
  });
}
