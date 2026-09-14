import 'package:flutter/material.dart';
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

  testWidgets('有等级+拍档的行显示 Lv 与默契度；非拍档行不显示默契度', (tester) async {
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
    // 只有拍档行有默契度数值 / 徽标。
    expect(find.text('345'), findsOneWidget);
    expect(find.byType(TacitBadge), findsOneWidget);

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
      findsNothing,
    );
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
