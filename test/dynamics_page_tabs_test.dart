import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/services/chat_service.dart' show ChatService;
import 'package:mnchat/state/providers.dart' show chatServiceProvider;
import 'package:mnchat/ui/dynamics_page.dart' show DynamicsPage;
import 'package:mnchat/ui/theme/app_theme.dart' show buildAppTheme;

/// 动态大厅顶部分类条的窄屏回归。
///
/// 分类数 ≥5（内置的 热门/关注/同城/官方 + 「我的」，服务端还会在「我的」
/// 之前追加自定义标签）。固定等分宽度的 `TabBar` 在手机窄屏 + 系统大字体下
/// 每个标签只剩 ~40dp，标签被压到 `TextOverflow.fade` 淡出 —— 也就是用户报告的
/// 「分类互相挤压把文字给挤没了」。这里在 360dp 宽的手机视口下断言：标签条可
/// 横向滚动，且每个标签都按自身固有宽度完整渲染（没有被挤压）。
void main() {
  Future<void> pumpDynamics(
    WidgetTester tester, {
    required Size logicalSize,
    double textScale = 2.0,
  }) async {
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatServiceProvider.overrideWithValue(ChatService(db: null)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: const DynamicsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 每个分类标签都按固有宽度渲染（被挤压时 `size.width` 会小于固有宽度）。
  void expectLabelsNotSqueezed(WidgetTester tester, double textScale) {
    for (final label in const ['热门', '关注', '同城', '官方', '我的']) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: '缺少分类 $label');
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final intrinsic = paragraph.getMaxIntrinsicWidth(double.infinity);
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(intrinsic - 0.01),
        reason:
            '$label 的文字被挤压：文本区 ${paragraph.size.width}dp < '
            '需要 $intrinsic（textScale $textScale）',
      );
    }
  }

  testWidgets('手机窄屏 + 系统大字体：分类条可横向滚动，标签不被挤没', (tester) async {
    await pumpDynamics(tester, logicalSize: const Size(360, 720));

    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(
      bar.isScrollable,
      isTrue,
      reason: '固定等分宽度会随分类数/字体放大挤压标签',
    );
    expect(bar.tabAlignment, TabAlignment.start, reason: '窄屏标签条应贴左');
    expectLabelsNotSqueezed(tester, 2.0);
  });

  testWidgets('默认字体：分类标签同样完整渲染', (tester) async {
    await pumpDynamics(tester, logicalSize: const Size(360, 720), textScale: 1.0);
    expectLabelsNotSqueezed(tester, 1.0);
  });

  testWidgets('宽屏：分类标签完整渲染', (tester) async {
    await pumpDynamics(
      tester,
      logicalSize: const Size(1024, 768),
      textScale: 1.0,
    );
    expectLabelsNotSqueezed(tester, 1.0);
  });
}
