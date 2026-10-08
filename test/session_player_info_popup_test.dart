/// 玩家信息浮窗回归：
/// 1) 「更多」入口必须打开**新版**会话浮动菜单（`session_menu.dart`），而不是
///    已废弃的底部弹窗版本（判据：新版有「标签」项）；
/// 2) 底部按钮按入口来源变化，对齐游戏
///    `PlayerInfoCardMgr:ShowByParamFguiObj(funcBtns: ...)`：动态来源 =
///    个人中心 / 加好友 / 赠送 / 关注（`dynamicsinfocard.lua:2087-2105`），
///    好友来源保留会话类的 置顶 / 更多。
///
/// 注：卡片里的 `PlayerInfoStats` 会去拉等级/主页，测试里用定次 pump 而不是
/// `pumpAndSettle`（后者会等一个永远不结束的网络请求）。
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/messages.dart' show Contact;
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/widgets/session_player_info_popup.dart';

/// 打开浮窗的宿主（真实调用点都在页面里，这里用一个按钮代劳）。
class _Host extends ConsumerWidget {
  const _Host({this.origin = PlayerCardOrigin.friends});

  final PlayerCardOrigin origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () => showSessionPlayerInfoPopup(
        context,
        ref,
        uin: 123,
        name: '好人',
        origin: origin,
      ),
      child: const Text('open'),
    );
  }
}

/// pump 宿主并打开浮窗（定次 pump，避免等 `PlayerInfoStats` 的网络请求）。
Future<void> _openCard(
  WidgetTester tester, {
  PlayerCardOrigin origin = PlayerCardOrigin.friends,
  List<Contact> contacts = const <Contact>[],
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        myUinProvider.overrideWithValue(999),
        contactsProvider.overrideWith((_) => Stream.value(contacts)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(body: _Host(origin: origin)),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('信息卡「更多」打开新版会话菜单（含「标签」项）', (tester) async {
    await _openCard(tester);
    expect(find.text('更多'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('标签'), findsOneWidget, reason: '应由新版会话菜单提供「标签」');
    expect(find.text('备注'), findsOneWidget);
    expect(find.text('删除好友'), findsOneWidget);
  });

  testWidgets('动态来源：按钮为 个人中心 / 加好友 / 赠送 / 关注', (tester) async {
    await _openCard(tester, origin: PlayerCardOrigin.dynamics);
    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('加好友'), findsOneWidget);
    expect(find.text('赠送'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
    // 会话类按钮不该出现在动态来源的卡上。
    expect(find.text('置顶'), findsNothing);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('好友来源：保留 个人中心 / 置顶 / 赠送 / 更多', (tester) async {
    await _openCard(tester);
    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('赠送'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    // 动态来源特有的按钮不该出现。
    expect(find.text('加好友'), findsNothing);
    expect(find.text('关注'), findsNothing);
  });
}
