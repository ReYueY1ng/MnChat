import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/theme/app_tokens.dart';
import 'package:mnchat/ui/widgets/avatar_view.dart';
import 'package:mnchat/ui/widgets/head_frame.dart';

/// 会话 / 好友行的「圆角卡片」回归测试。
///
/// 单测无法直接 pump 私有行组件（`_SessionTile` / `_FriendTile`），故复刻其
/// 真实结构：ListTile（shape + tileColor + minTileHeight + kAvatarListTileDensity）
/// + 带头像框的 AvatarView leading，放进有界 ListView。
///
/// 覆盖 analyze / build 抓不到的运行时问题：
/// - ListTile 承载「有框槽位」时一旦布局越界会抛
///   「Leading widget consumes the entire tile width」等断言（见 head_frame.dart 注释）；
/// - shape 必须真正落到渲染层的 Ink 上（圆角 + 与 cardTheme 同源的 1px 描边），
///   而不是只写在 widget 参数里 —— 否则底色 / 选中色仍是直角矩形。
void main() {
  const radius = 24.0;

  group('会话 / 好友行圆角卡片（运行时布局与渲染外形）', () {
    /// ListTile.shape 写的是 [AppRadius.cardR] + cardTheme 同源的描边。
    void expectCardShape(ShapeBorder? shape, ThemeData theme) {
      expect(shape, isA<RoundedRectangleBorder>());
      final rounded = shape! as RoundedRectangleBorder;
      final borderRadius = rounded.borderRadius.resolve(TextDirection.ltr);
      expect(rounded.borderRadius, AppRadius.cardR);
      // 圆角必须等于 token，不能是任意值。
      expect(
        borderRadius.topLeft.x,
        AppRadius.card,
        reason: '圆角应使用 AppRadius.cardR（18），与全局卡片一致',
      );
      // 描边与 cardTheme 完全同源（1px + outlineVariant）。
      const expectedSide = BorderSide(color: Color(0x1F000000));
      final cardShape = theme.cardTheme.shape;
      expect(cardShape, isA<RoundedRectangleBorder>());
      expect(
        (cardShape! as RoundedRectangleBorder).side,
        expectedSide,
        reason: 'cardTheme 描边应保持 outlineVariant / 1px',
      );
      expect(
        rounded.side,
        (cardShape as RoundedRectangleBorder).side,
        reason: '行的描边必须复用 cardTheme 的同一条 BorderSide',
      );
    }

    /// 取出 ListTile 真正绘制底色 / 描边的 Ink 的 ShapeDecoration。
    /// 逐行断言（每行一个 Ink），避免多行时 findsOneWidget 误报。
    ShapeDecoration inkDecoration(WidgetTester tester, {int row = 0}) {
      final inkFinder = find.descendant(
        of: find.byType(ListTile).at(row),
        matching: find.byType(Ink),
      );
      expect(inkFinder, findsOneWidget);
      final decoration = tester.widget<Ink>(inkFinder).decoration;
      expect(decoration, isA<ShapeDecoration>());
      return decoration! as ShapeDecoration;
    }

    /// 复刻行结构。会话行与好友行现在共用 [AppSpacing.listTilePadding]
    /// （此前会话行手写 vertical 4 导致行高偏矮、同样的头像显得偏大）；
    /// selectFirst 模拟当前选中的会话行；[itemCount] 用于撑到列表可滚动。
    Future<void> pumpRows(
      WidgetTester tester, {
      required bool withHeadFrame,
      bool selectFirst = false,
      ValueChanged<int>? onRowTap,
      int itemCount = 2,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: ListView.separated(
                // 四边内缩 AppSpacing.sm：左右避免圆角贴住面板边缘；上下避免
                // 首/末卡片贴住上方工具栏与窗口底边（此前只有横向内缩）。
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                itemCount: itemCount,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final theme = Theme.of(context);
                  final cardShape = theme.cardTheme.shape;
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.cardR,
                      side: cardShape is RoundedRectangleBorder
                          ? cardShape.side
                          : BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    tileColor: theme.colorScheme.surfaceContainerLow,
                    selected: selectFirst && i == 0,
                    selectedTileColor: theme.colorScheme.secondaryContainer,
                    contentPadding: AppSpacing.listTilePadding,
                    visualDensity: kAvatarListTileDensity,
                    minTileHeight: headFrameSlotSize(radius),
                    leading: AvatarView(
                      frameId: withHeadFrame ? 20201 : null,
                      radius: radius,
                      name: 'ab',
                    ),
                    title: const Text('昵称'),
                    subtitle: const Text('副标题'),
                    onTap: onRowTap == null ? null : () => onRowTap(i),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('带框行 + 两行副标题：不抛布局断言，槽位保持正方形', (tester) async {
      await pumpRows(tester, withHeadFrame: true);

      expect(tester.takeException(), isNull);
      const slotSide = radius * 2 / kHeadFrameAvatarInset;
      final avatarSize = tester.getSize(find.byType(AvatarView).first);
      expect(avatarSize.width, closeTo(slotSide, 1e-6));
      expect(avatarSize.height, closeTo(slotSide, 1e-6));
    });

    testWidgets('无框行同样不抛异常，且几何与有框一致', (tester) async {
      await pumpRows(tester, withHeadFrame: false);

      expect(tester.takeException(), isNull);
      const slotSide = radius * 2 / kHeadFrameAvatarInset;
      final avatarSize = tester.getSize(find.byType(AvatarView).first);
      expect(avatarSize.width, closeTo(slotSide, 1e-6));
      expect(avatarSize.height, closeTo(slotSide, 1e-6));
    });

    testWidgets('行高足以容纳头像槽位（会话/好友行几何一致）', (tester) async {
      const slotSide = radius * 2 / kHeadFrameAvatarInset;
      await pumpRows(tester, withHeadFrame: true);

      expect(tester.takeException(), isNull);
      expect(find.byType(ListTile), findsNWidgets(2));
      // 行高必须 ≥ 头像槽位：行越矮，同样的头像越显得偏大
      // （会话行曾用 vertical 4，比好友行矮 8px，观感上头像偏大）。
      expect(
        tester.getSize(find.byType(ListTile).first).height,
        greaterThanOrEqualTo(slotSide),
      );
    });

    testWidgets('渲染外形：圆角 cardR + cardTheme 同源描边 + surfaceContainerLow 底色', (
      tester,
    ) async {
      await pumpRows(tester, withHeadFrame: true);
      expect(tester.takeException(), isNull);

      final theme = Theme.of(
        tester.element(find.byType(ListTile).first),
      );
      // 已渲染的 Ink 拿到的就是圆角外形（不再依赖 widget 参数）。
      final decoration = inkDecoration(tester);
      expectCardShape(decoration.shape, theme);
      // 底色 = 全局卡片色。
      expect(
        decoration.color,
        theme.colorScheme.surfaceContainerLow,
        reason: '行的底色应为 surfaceContainerLow（cardTheme.color）',
      );
    });

    testWidgets('选中行：selectedTileColor 作为同一圆角卡片的底色', (tester) async {
      await pumpRows(tester, withHeadFrame: true, selectFirst: true);
      expect(tester.takeException(), isNull);

      final selected = tester.widget<ListTile>(find.byType(ListTile).first);
      final theme = Theme.of(tester.element(find.byType(ListTile).first));
      expect(selected.selected, isTrue);
      expect(selected.selectedTileColor, theme.colorScheme.secondaryContainer);
      // 选中态不改变外形：仍是 cardR 圆角 + cardTheme 同源描边，
      // selectedTileColor 由 ListTile 内部解析进 Ink 底色（圆角卡片而非满幅矩形）。
      expect(selected.shape, isA<RoundedRectangleBorder>());
      expectCardShape(inkDecoration(tester).shape, theme);
    });

    testWidgets('圆角卡片：左右内缩 + 行间留白均为 AppSpacing.sm，卡片互不接触', (tester) async {
      await pumpRows(tester, withHeadFrame: true);

      final tile0 = tester.getRect(find.byType(ListTile).at(0));
      final tile1 = tester.getRect(find.byType(ListTile).at(1));
      // ListView 左右各内缩 8（= CardThemeData.margin.horizontal）。
      expect(tile0.left, AppSpacing.sm);
      expect(tile0.right, 800 - AppSpacing.sm);
      // 行间留白 8（= CardThemeData.margin.vertical）。
      expect(tile1.top - tile0.bottom, AppSpacing.sm);
      // 圆角本身不会让卡片互相重叠。
      expect(tile1.top, greaterThan(tile0.bottom));
    });

    testWidgets('点击仍可命中整行，不抛异常', (tester) async {
      final taps = <int>[];
      await pumpRows(
        tester,
        withHeadFrame: true,
        onRowTap: taps.add,
      );

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(taps, [0]);
    });

    testWidgets('悬停 / 获取焦点不抛异常（反馈裁进圆角）', (tester) async {
      await pumpRows(tester, withHeadFrame: true);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(ListTile).first));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final selected = tester.widget<ListTile>(find.byType(ListTile).first);
      expect(selected.shape, isA<RoundedRectangleBorder>());
      // ListTile 自带 InkWell，focus 高亮同样走 customBorder 裁剪路径。
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('列表上下留白：首卡片距顶 / 末卡片距底均为 AppSpacing.sm', (tester) async {
      await pumpRows(tester, withHeadFrame: true, itemCount: 20);

      final viewport = tester.getRect(find.byType(ListView));
      // 顶部留白：第一张卡片不贴住上方工具栏 / 分隔线。
      expect(
        tester.getRect(find.byType(ListTile).first).top,
        viewport.top + AppSpacing.sm,
        reason: 'ListView 顶部需内缩 AppSpacing.sm',
      );

      // 内容须超出视口，滚到底部断言底部留白才有意义。
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      // 用真实拖拽滚到底：clamping 物理会在末端精确停住，而 jumpTo(maxScrollExtent)
      // 可能落在 SliverList 的估算 extent 上，没有真正到达底部。
      await tester.drag(find.byType(ListTile).first, const Offset(0, -4000));
      await tester.pumpAndSettle();

      // 底部留白：最后一张卡片不贴住窗口底边。
      expect(
        tester.getRect(find.byType(ListTile).last).bottom,
        viewport.bottom - AppSpacing.sm,
        reason: 'ListView 底部需内缩 AppSpacing.sm',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('好友页工具条：ColoredBox 铺页面底色（不透明）且不抛异常', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  theme = Theme.of(context);
                  // 复刻 friends_page._buildToolbar：Padding / Row 外包一层
                  // ColoredBox(color: theme.scaffoldBackgroundColor)。
                  return Column(
                    children: [
                      ColoredBox(
                        color: theme.scaffoldBackgroundColor,
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Row(children: [Text('在线 0 / 1')]),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                          children: const [ListTile(title: Text('卡片'))],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final toolbarFinder = find
          .ancestor(
            of: find.text('在线 0 / 1'),
            matching: find.byType(ColoredBox),
          )
          .first;
      final toolbar = tester.widget<ColoredBox>(toolbarFinder);
      // 不透明（alpha=255）= 实心遮住下方内容；颜色 = 页面底色保持无缝。
      expect(toolbar.color, theme.scaffoldBackgroundColor);
      expect(toolbar.color.a, 1.0);
      // 仍是 Column 中的普通条状（在 Divider 之上），不是浮层 / 叠层。
      expect(
        tester.getRect(find.text('在线 0 / 1')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(Divider)).top),
      );
    });
  });
}
