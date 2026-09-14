import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/chat_service.dart'
    show ChatService, SessionSnapshot;
import 'package:mnchat/core/services/partner.dart' show PartnerInfo;
import 'package:mnchat/core/services/profile.dart' show PlayerProfile;
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/profile_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/widgets/avatar_edit_dialog.dart' show avatarEditNavKey;
import 'package:mnchat/ui/widgets/avatar_view.dart';
import 'package:mnchat/ui/widgets/partner_badges.dart';

/// 个人主页回归测试。
///
/// 1) 未登录态 pump 真实 [ProfilePage]：验证参考图要求的版块顺序与文案都在，
///    且无协议数据的版块降级为「—」占位（不臆造数值）；
/// 2) [HomePartnerTile]：验证「最佳拍档」条目的头像与等级 / 默契度 / VIP 徽标。
void main() {
  /// 以「未登录」态 pump 个人主页：此时不会发起任何网络请求。
  ///
  /// 视口调高，保证整页（ListView 懒构建）的版块全部参与断言。
  Future<void> pumpProfilePage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatServiceProvider.overrideWithValue(ChatService(db: null)),
          sessionListProvider.overrideWith(
            (_) => Stream.value(const SessionSnapshot([], [])),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('个人主页按参考图顺序渲染各版块与文案', (tester) async {
    await pumpProfilePage(tester);
    expect(tester.takeException(), isNull);

    // 顶栏：标题 / 资料 / 入口按钮 / 四项统计
    for (final label in <String>[
      '个人主页',
      '最近访客',
      '编辑布局',
      '修改昵称',
      '家园',
      '关注',
      '粉丝',
      '人气值',
      '信用分',
    ]) {
      expect(find.text(label), findsWidgets, reason: '缺少文案：$label');
    }
    expect(find.textContaining('迷你号'), findsWidgets);

    // 版块顺序（参考图自上而下）
    for (final label in <String>[
      '个性装扮',
      '头像框',
      '魅力值',
      '称号',
      '发布作品',
      '动态',
      '最佳拍档',
      '追光计划',
      '我的收藏夹',
      '勋章',
      '迷你印迹',
      '交友宣言',
    ]) {
      expect(find.text(label), findsWidgets, reason: '缺少版块：$label');
    }

    // 无协议版块只出现「—」占位，不展示臆造数值。
    expect(find.text(kHomeUnknownValue), findsWidgets);
    expect(find.textContaining('IP属地'), findsOneWidget);
    // 无拍档数据时降级为文案，而不是空卡片。
    expect(find.text('暂无最佳拍档'), findsOneWidget);
  });

  testWidgets('最佳拍档条目渲染头像 + 昵称 + 等级 / 默契度 / VIP 徽标', (tester) async {
    const partner = PartnerInfo(
      bestUin: 10001,
      lab: 1,
      tacitnum: 345,
      createtime: 1700000000,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(
            body: HomePartnerTile(
              partner: partner,
              profile: PlayerProfile(uin: 10001, nickname: '拍档好友'),
              level: 12,
              isVip: true,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    expect(find.text('拍档好友'), findsOneWidget);
    expect(find.byType(AvatarView), findsOneWidget);
    expect(find.text('Lv12'), findsOneWidget);
    expect(find.text('345'), findsOneWidget);
    expect(find.byType(TacitBadge), findsOneWidget);
    expect(find.byType(VipBadge), findsOneWidget);
  });

  testWidgets('无资料时最佳拍档条目退回迷你号且不显示徽标', (tester) async {
    const partner = PartnerInfo(bestUin: 10002);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(body: HomePartnerTile(partner: partner)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    expect(find.text('10002'), findsOneWidget);
    expect(find.byType(LevelBadge), findsNothing);
    expect(find.byType(TacitBadge), findsNothing);
    expect(find.byType(VipBadge), findsNothing);
  });

  testWidgets('个人主页两处入口均可打开头像编辑弹窗并关闭', (tester) async {
    await pumpProfilePage(tester);
    // 顶栏按钮 + 头像点按共两处入口（Tooltip 同名）。
    expect(find.byTooltip('头像编辑'), findsNWidgets(2));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.badge_outlined));
    await tester.pumpAndSettle();
    expect(find.text('头像编辑'), findsOneWidget);
    for (final label in ['头像', '头像框', '昵称', '称号', '家族']) {
      expect(
        find.descendant(
          of: find.byKey(avatarEditNavKey),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: '缺少弹窗页签：$label',
      );
    }

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('头像编辑'), findsNothing);
  });
}
