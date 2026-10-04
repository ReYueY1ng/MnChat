// 设置页两层结构：顶层只有 5 个分组入口，点进去才是具体设置。
//
// 用真实内存 Drift 库承载 SettingsStore，让各 provider 正常读到默认值；
// 只点「通用与外观」这一支 —— 它的子页全部走本地设置，不触网。
// （通知子页会读服务端开关、隐私子页会拉 closeapply_flag，放进来会真的发请求。）
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/settings_page.dart';
import 'package:mnchat/ui/theme/app_tokens.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    // 默认测试视口只有 800×600，设置页顶层的「关于」分组在折线以下、根本不会被
    // ListView 构建出来，断言会假失败。把视口拉高到整页可见。
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.brandSeed,
            ),
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('顶层只有 5 个分组入口，功能入口不再挂在设置页上', (tester) async {
    await pumpSettings(tester);

    for (final title in const [
      '账号与安全',
      '通用与外观',
      '消息与通知',
      '隐私与数据',
      '关于 MnChat',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少分组入口：$title');
    }

    // 这些原来是设置页顶层的条目，现在要么进了子页，要么搬去了宿主页面。
    for (final moved in const [
      '个人资料',
      '交友标签',
      '关注与粉丝',
      '附近的人',
      '聊天气泡',
      '退群记录',
      '聊天记录',
      '快捷短语',
      '应用锁',
    ]) {
      expect(find.text(moved), findsNothing, reason: '$moved 不该还在设置页顶层');
    }
  });

  testWidgets('点「通用与外观」进入子页', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('通用与外观'));
    await tester.pumpAndSettle();

    // 子页标题（AppBar）与子页内容都在
    expect(find.text('通用与外观'), findsOneWidget);
    expect(find.text('主题显示设置'), findsOneWidget);
    expect(find.text('聊天气泡'), findsOneWidget);
    expect(find.text('会话排序'), findsOneWidget);
    expect(find.text('头像框动画'), findsOneWidget);
  });
}
