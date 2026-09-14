import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart' show SessionSnapshot;
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/friends_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/theme/app_tokens.dart';

/// 好友页真实页面回归测试（pump 真正的 [FriendsPage]，而非复刻私有组件）。
///
/// 覆盖用户反馈的两点：
/// - 工具条透明 → 列表卡片会透出：工具条必须是不透明实心条
///   （ColoredBox 铺 `theme.scaffoldBackgroundColor`）；
/// - 列表无上下留白 → 首/末圆角卡片分别贴住工具栏与窗口边缘：四边都需
///   内缩 [AppSpacing.sm]。
void main() {
  /// 构造 [count] 个好友会话（relation 的 bit3 = 好友，见 _FriendCat.friend）。
  List<ChatSession> friends(int count) => [
    for (var i = 0; i < count; i++)
      ChatSession(
        id: 10000 + i,
        type: ChatSessionType.friend,
        name: '好友$i',
        relation: 8,
      ),
  ];

  /// pump 真实好友页：会话流直接用 [count] 个好友接管，避免依赖
  /// ChatService / 网络。
  Future<void> pumpFriendsPage(WidgetTester tester, {int count = 20}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionListProvider.overrideWith(
            (_) => Stream.value(SessionSnapshot(friends(count), const [])),
          ),
          friendRequestCountProvider.overrideWithValue(0),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const FriendsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('工具条：ColoredBox 铺页面底色（不透明）且位于 Divider 之上', (tester) async {
    await pumpFriendsPage(tester);
    expect(tester.takeException(), isNull);

    final theme = Theme.of(tester.element(find.byType(FriendsPage)));
    // 取工具条 ColoredBox（"在线 N / N" 文本最近的 ColoredBox 祖先）。
    final toolbarFinder = find
        .ancestor(
          of: find.text('在线 0 / 20'),
          matching: find.byType(ColoredBox),
        )
        .first;
    final toolbar = tester.widget<ColoredBox>(toolbarFinder);
    // 颜色 = 页面底色且 alpha=255：实心遮住下方内容、与页面无缝。
    expect(toolbar.color, theme.scaffoldBackgroundColor);
    expect(toolbar.color.a, 1.0);
    // 仍是 Column 中的普通条状：工具条底边紧贴分隔线，不是浮层 / 叠层。
    expect(
      tester.getRect(toolbarFinder).bottom,
      tester.getRect(find.byType(Divider).first).top,
    );
  });

  testWidgets('列表上下留白：首/末卡片与工具栏、窗口边缘各留 AppSpacing.sm', (tester) async {
    await pumpFriendsPage(tester);
    expect(tester.takeException(), isNull);

    // 好友列表 = 含 ListTile 的那个 ListView（排除左侧分类栏的 ListView）。
    final listFinder = find.ancestor(
      of: find.byType(ListTile).first,
      matching: find.byType(ListView),
    );
    final viewport = tester.getRect(listFinder);
    expect(
      tester.getRect(find.byType(ListTile).first).top,
      viewport.top + AppSpacing.sm,
      reason: '首卡片与工具条分隔线之间需留 AppSpacing.sm',
    );
    expect(
      tester.getRect(find.byType(ListTile).first).left,
      viewport.left + AppSpacing.sm,
      reason: '圆角卡片左右仍需内缩 AppSpacing.sm',
    );

    // 内容超出视口才滚得到底部；用真实拖拽滚到底（clamping 物理在末端精确
    // 停住，jumpTo(maxScrollExtent) 可能落在 SliverList 的估算 extent 上）。
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: listFinder, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(ListTile).first, const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(ListTile).last).bottom,
      viewport.bottom - AppSpacing.sm,
      reason: '末卡片与窗口底边之间需留 AppSpacing.sm',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('关系标签：好友+关注(relation 24)显示「好友」而非「关注」', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionListProvider.overrideWith(
            (_) => Stream.value(
              SessionSnapshot(
                const [
                  ChatSession(
                    id: 10001,
                    type: ChatSessionType.friend,
                    name: '双向好友',
                    relation: 24, // 8|16 = 好友 + 我关注
                  ),
                ],
                const [],
              ),
            ),
          ),
          friendRequestCountProvider.overrideWithValue(0),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const FriendsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 关系标签在好友行（ListTile）内；左侧分类栏的「关注」入口不算。
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('好友')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('关注')),
      findsNothing,
    );
  });
}
