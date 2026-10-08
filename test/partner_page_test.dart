/// 最佳拍档页：按槽位上限展示列表，空位渲染为「最佳拍档剩余空位 x N」。
///
/// 对齐游戏 `BestPartnerDataMgr:GetTypeRenderCfg()[0]`——`lab == 0` 的条目用
/// `noRelationLoader = icon_add_upload` + `noText = GetS(9312030)`
/// （「最佳拍档剩余空位 x %s」）渲染（`bestpartnerdatamgr.lua:1207-1221`）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/services/partner.dart';
import 'package:mnchat/core/services/profile.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/partner_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

const _one = PartnerInfo(bestUin: 1001, lab: 1, tacitnum: 120);

Future<void> _pump(
  WidgetTester tester, {
  required List<PartnerInfo> partners,
  required int total,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myPartnerListProvider.overrideWith((ref) async => partners),
        partnerSlotProvider.overrideWith(
          (ref) async => PartnerSlotInfo(unlockNormal: total, unlockSpecial: 0),
        ),
        partnerLevelsProvider.overrideWith((ref) async => const <int, int>{}),
        partnerProfilesProvider.overrideWith(
          (ref) async => const <int, PlayerProfile>{},
        ),
        partnerLevelConfigProvider.overrideWith(
          (ref) async => const <(int, int)>[],
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const PartnerPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('有空位时显示「最佳拍档剩余空位 x N」', (tester) async {
    await _pump(tester, partners: const [_one], total: 3);
    expect(tester.takeException(), isNull);
    expect(find.text('最佳拍档剩余空位 x 2'), findsOneWidget);
    // 实拍档卡片仍在。
    expect(find.text('1001'), findsOneWidget);
  });

  testWidgets('槽位占满时不渲染空位卡', (tester) async {
    await _pump(tester, partners: const [_one], total: 1);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('剩余空位'), findsNothing);
  });
}
