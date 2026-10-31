// 家族页回归：未登录 / 已登录都不能永久转圈。
//
// 旧实现把 `l10nOf(context)` 放在 initState 的同步调用链上（`_load()` 第一个
// `await` 之前）—— `Localizations.of` 会注册 InheritedWidget 依赖，框架在
// initState 未完成时直接抛断言，异常让 `_load()` 提前结束而 `_loading` 仍是
// true，页面就一直转圈。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/services/chat_service.dart' show ChatService;
import 'package:mnchat/core/services/family.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/family_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

/// 不进网络的家族客户端：一个家族、没有成员（不触发头像批量请求）。
class _FakeFamilyClient extends FamilyClient {
  _FakeFamilyClient() : super(uin: 1, s2: 's2', s2t: 's2t');

  @override
  Future<List<Object>> queryUserFamilyIds({int? target}) async =>
      <Object>[1];

  @override
  Future<FamilyDetail> getFamilyDetail(Object familyId) async =>
      const FamilyDetail(
        info: FamilyInfo(familyId: 1, name: '测试家族', leaderUin: 1),
      );
}

void main() {
  Future<void> pumpFamily(WidgetTester tester, {FamilyClient? client}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatServiceProvider.overrideWithValue(ChatService(db: null)),
          if (client != null) familyClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const FamilyPage(),
        ),
      ),
    );
  }

  testWidgets('未登录：显示未登录，不转圈也不抛异常', (tester) async {
    await pumpFamily(tester);
    await tester.pump();

    expect(find.text('未登录'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已登录：加载完成显示家族，不卡在转圈', (tester) async {
    await pumpFamily(tester, client: _FakeFamilyClient());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('测试家族'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
