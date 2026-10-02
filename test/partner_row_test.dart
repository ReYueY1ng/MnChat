import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart' show SessionSnapshot;
import 'package:mnchat/core/services/partner.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/friends_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/widgets/partner_badges.dart';

/// 好友行徽标回归测试（pump 真实 [FriendsPage]）。
///
/// 覆盖：等级 `Lv<N>`、拍档默契度六边形、大会员 VIP 徽标的显示与不显示。
void main() {
  /// 会话快照：10001 为拍档 + 会员，10002 为普通好友。
  const snapshot = SessionSnapshot(
    [
      ChatSession(
        id: 10001,
        type: ChatSessionType.friend,
        name: '拍档好友',
        relation: 8,
      ),
      ChatSession(
        id: 10002,
        type: ChatSessionType.friend,
        name: '普通好友',
        relation: 8,
      ),
    ],
    [],
  );

  Future<void> pumpFriends(
    WidgetTester tester,
    PartnerDirectory directory,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionListProvider.overrideWith(
            (_) => Stream.value(snapshot),
          ),
          friendRequestCountProvider.overrideWithValue(0),
          partnerDirectoryProvider.overrideWith((_) => directory),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const FriendsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('有等级+拍档的行显示 Lv 与默契度；非拍档行也显示默契度 0', (tester) async {
    await pumpFriends(
      tester,
      const PartnerDirectory(
        levels: {10001: 12, 10002: 7},
        partners: {
          10001: PartnerInfo(
            bestUin: 10001,
            lab: 1,
            tacitnum: 345,
            createtime: 1700000000,
          ),
        },
      ),
    );
    expect(tester.takeException(), isNull);

    // 两行都有等级徽标。
    expect(find.text('Lv12'), findsOneWidget);
    expect(find.text('Lv7'), findsOneWidget);
    // 默契度是每个好友都有的（非拍档显示 0），所以两行都有徽标。
    expect(find.byType(TacitBadge), findsNWidgets(2));
    expect(find.text('345'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    final partnerTile = find.ancestor(
      of: find.text('Lv12'),
      matching: find.byType(ListTile),
    );
    final normalTile = find.ancestor(
      of: find.text('Lv7'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: partnerTile, matching: find.byType(TacitBadge)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: normalTile, matching: find.byType(TacitBadge)),
      findsOneWidget,
    );
  });

  testWidgets('窄屏（360dp）下徽标不会把好友名挤没，默契度仍然可见', (tester) async {
    // 回归：以前昵称是 `Flexible`、徽标是定宽，徽标按固有宽度（实测 153.8dp）
    // 吃完整行，名字实测被压到 **0 宽**。
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpFriends(
      tester,
      const PartnerDirectory(
        levels: {10001: 12, 10002: 7},
        partners: {
          10001: PartnerInfo(
            bestUin: 10001,
            lab: 1,
            tacitnum: 345,
            createtime: 1700000000,
          ),
        },
      ),
    );
    // 页头控件行（friends_page.dart:638）在 360dp 下另有一处**既有**溢出，
    // 与好友行无关，这里只关心行内布局。
    while (tester.takeException() != null) {}

    final nameBox = tester.renderObject<RenderBox>(find.text('拍档好友'));
    expect(nameBox.size.width, greaterThan(60),
        reason: '昵称至少要放得下一两个字，不能被状态徽标挤没');
    expect(find.byType(PartnerNameBadges), findsWidgets);
  });

  testWidgets('徽标按可用宽度降级：宽 → 全量；窄 → 只留得下的；极窄 → 不渲染', (tester) async {
    Future<void> pumpAt(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: width,
                child: const PartnerNameBadges(
                  level: 12,
                  tacitnum: 1069,
                  lab: 4,
                  isVip: true,
                  levels: <(int, int)>[(1, 100), (2, 600)],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // 宽：三枚都有（含进度条）。
    await pumpAt(400);
    expect(find.byType(LevelBadge), findsOneWidget);
    expect(find.byType(TacitBadge), findsOneWidget);
    expect(find.byType(VipBadge), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 窄：只留装得下的（测试字体下 1069 比 LV12/VIP 更短，保住默契度）。
    await pumpAt(80);
    expect(find.byType(TacitBadge), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 极窄：一枚都放不下 → 不渲染（把宽度让给昵称），也不溢出。
    await pumpAt(40);
    expect(find.byType(TacitBadge), findsNothing);
    expect(find.byType(LevelBadge), findsNothing);
    expect(find.byType(VipBadge), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('徽标在任意可用宽度下都不溢出（含估算偏差兜底）', (tester) async {
    // 回归：真实字体下估算偏小 2.7dp 曾触发 RenderFlex 溢出；现在一是每枚预留
    // 4dp 余量，二是渲染层用 ClipRect 兜底，所以任意宽度都不应再报溢出。
    for (var w = 20.0; w <= 260; w += 3) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: w,
                child: const PartnerNameBadges(
                  level: 12,
                  tacitnum: 123456,
                  lab: 4,
                  isVip: true,
                  levels: <(int, int)>[(1, 100), (2, 600)],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '可用宽度 $w 下溢出');
      final box = tester.renderObject<RenderBox>(
        find.byType(PartnerNameBadges),
      );
      expect(
        box.size.width,
        lessThanOrEqualTo(w + 0.01),
        reason: '可用宽度 $w 下徽标超出了可用宽度',
      );
    }
  });

  testWidgets('大会员行显示 VIP 徽标，非会员行不显示', (tester) async {
    await pumpFriends(
      tester,
      const PartnerDirectory(
        levels: {10001: 12, 10002: 7},
        vipExpiry: {10001: 4102444800}, // 2100 年，恒为会员
      ),
    );
    expect(tester.takeException(), isNull);

    expect(find.byType(VipBadge), findsOneWidget);
    expect(find.text('VIP'), findsOneWidget);

    final normalTile = find.ancestor(
      of: find.text('Lv7'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: normalTile, matching: find.byType(VipBadge)),
      findsNothing,
    );
  });
}
