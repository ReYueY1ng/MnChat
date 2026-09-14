import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/auth.dart' show MiniAuth;
import 'package:mnchat/core/services/chat_service.dart'
    show ChatService, SessionSnapshot;
import 'package:mnchat/core/services/family.dart' show FamilyInfo;
import 'package:mnchat/core/services/profile.dart' show PortraitItem;
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/widgets/avatar_edit_dialog.dart';
import 'package:mnchat/ui/widgets/avatar_view.dart';

/// 测试用登录态（含已拥有皮肤 1，用于渲染「装扮」头像格子）。
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    auth: MiniAuth(
      uin: 10001,
      apiId: 110,
      name: 'MoonReloaded',
      s2: 's2',
      s2t: 's2t',
      jwt: '',
      ownedSkinIds: {1},
    ),
  );
}

/// 头像编辑弹窗回归测试。
///
/// 覆盖：外壳（标题 / 左 nav / 关闭）、头像页签（顶部来源分类、`自定义`、
/// 4 列网格、右栏提示）、头像框页签（`置顶` 降级提示）、昵称页签（校验驱动
/// `确认修改` 可用态 + 未连接返回码文案）、称号页签（分类 + 空态）、
/// 家族页签（懒加载列表 + 选中态 + 切换无协议提示）。
void main() {
  const initial = AvatarEditInitialData(
    uin: 10001,
    name: 'MoonReloaded',
    // 头像本体（type=1 皮肤）：id 为皮肤 ID（1 → 本地图标 31）。
    headType: 1,
    headId: 1,
    frameId: 1,
    ownedFrames: {1, 20201},
    portraits: [PortraitItem(id: 7)],
    titleName: '星尘守护者',
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    AvatarEditInitialData data = initial,
    FamilyListLoader? familyLoader,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatServiceProvider.overrideWithValue(ChatService(db: null)),
          sessionListProvider.overrideWith(
            (_) => Stream.value(const SessionSnapshot([], [])),
          ),
          authProvider.overrideWith(_FakeAuthNotifier.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: AvatarEditDialog(initial: data, familyLoader: familyLoader),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(avatarEditNavKey),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('外壳 + 头像页签：标题 / 左 nav / 来源分类 / 自定义 / 右栏提示', (
    tester,
  ) async {
    await pumpDialog(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('头像编辑'), findsOneWidget);
    for (final label in ['头像', '头像框', '昵称', '称号', '家族']) {
      expect(
        find.descendant(
          of: find.byKey(avatarEditNavKey),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: '缺少左 nav 文案：$label',
      );
    }
    for (final label in ['全部', '装扮', '坐骑', '个性']) {
      expect(
        find.descendant(
          of: find.byKey(avatarEditSourceTabsKey),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: '缺少来源分类：$label',
      );
    }

    // 首格 `自定义` + 皮肤 / 立绘缩略图格子。
    expect(find.text('自定义'), findsOneWidget);
    expect(find.byKey(avatarEditHeadCellKey(4, 7)), findsOneWidget);
    // 当前头像（皮肤 1 → 图标 31）选中 → 绿色勾选角标。
    final selectedCell = find.byKey(avatarEditHeadCellKey(1, 1));
    expect(selectedCell, findsOneWidget);
    expect(
      find.descendant(
        of: selectedCell,
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );

    // 右栏：预览 + 逐字提示 + 会员免费 + 使用中。
    expect(find.byType(AvatarView), findsOneWidget);
    expect(find.text('请勿上传包含恐怖、反动等不良元素的图片哦'), findsOneWidget);
    expect(find.text('会员免费'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);

    // `自定义` 无上传链路：点按只提示。
    await tester.tap(find.text('自定义'));
    await tester.pump();
    expect(find.text('外部客户端暂不支持自定义头像上传'), findsOneWidget);
  });

  testWidgets('头像框页签：4 列帧网格 + 说明 + 置顶降级', (tester) async {
    await pumpDialog(tester);
    await tapNav(tester, '头像框');
    expect(tester.takeException(), isNull);

    expect(find.byKey(avatarEditFrameCellKey(1)), findsOneWidget);
    expect(find.byKey(avatarEditFrameCellKey(20201)), findsOneWidget);
    expect(find.text('头像框 #1'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);

    await tester.tap(find.text('置顶'));
    await tester.pump();
    expect(find.text('外部客户端暂不支持置顶头像框'), findsOneWidget);
  });

  testWidgets('昵称页签：当前昵称 / 输入校验驱动确认按钮 / 未连接返回码', (tester) async {
    await pumpDialog(tester);
    await tapNav(tester, '昵称');
    expect(tester.takeException(), isNull);

    expect(find.text('MoonReloaded'), findsOneWidget);
    expect(find.text('输入修改的名字'), findsOneWidget);
    expect(find.text('消耗'), findsOneWidget);
    expect(find.text('x1'), findsOneWidget);

    FilledButton confirmButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认修改'),
    );
    // 空输入 → 禁用。
    expect(confirmButton().onPressed, isNull);

    // 合法新昵称 → 启用。
    await tester.enterText(find.byKey(avatarEditNicknameFieldKey), '新名字');
    await tester.pump();
    expect(confirmButton().onPressed, isNotNull);

    // 与当前昵称相同 → 禁用。
    await tester.enterText(
      find.byKey(avatarEditNicknameFieldKey),
      'MoonReloaded',
    );
    await tester.pump();
    expect(confirmButton().onPressed, isNull);

    // 提交：测试中 ChatService 未连接 → 业务码 20 文案。
    await tester.enterText(find.byKey(avatarEditNicknameFieldKey), '新名字');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确认修改'));
    await tester.pumpAndSettle();
    expect(find.text('尚未连接服务器，请稍后重试'), findsOneWidget);
  });

  testWidgets('称号页签：分类 + 当前佩戴称号卡片 + 空态说明', (tester) async {
    await pumpDialog(tester);
    await tapNav(tester, '称号');
    expect(tester.takeException(), isNull);

    for (final label in ['全部', '开发者', '迷你季', '其他', '自定义']) {
      expect(
        find.descendant(
          of: find.byKey(avatarEditTitleTabsKey),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: '缺少称号分类：$label',
      );
    }
    expect(find.text('星尘守护者'), findsOneWidget);
    expect(find.text('有效期'), findsOneWidget);
    // 有效期无协议来源 → 「—」占位。
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('完整列表与有效期'), findsOneWidget);
  });

  testWidgets('家族页签：懒加载列表 + 首个选中 + 切换展示无协议', (tester) async {
    var loadCount = 0;
    await pumpDialog(
      tester,
      familyLoader: () async {
        loadCount++;
        return const [
          FamilyInfo(familyId: 1, name: 'MoonX'),
          FamilyInfo(familyId: 2, name: '繁花拥雪'),
        ];
      },
    );
    expect(loadCount, 0, reason: '未切到家族页签时不应请求');

    await tapNav(tester, '家族');
    expect(loadCount, 1);
    expect(find.text('MoonX'), findsOneWidget);
    expect(find.text('繁花拥雪'), findsOneWidget);

    final selected = find.byKey(avatarEditFamilyCellKey(1));
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(avatarEditFamilyCellKey(2)),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNothing,
    );

    await tester.tap(find.text('繁花拥雪'));
    await tester.pump();
    expect(find.text('外部客户端暂不支持设置展示家族'), findsOneWidget);
    // 选中态不变（设置无协议，不做假切换）。
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
  });

  testWidgets('✕ 关闭按钮经 showAvatarEditDialog 回传修改标记', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    bool? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatServiceProvider.overrideWithValue(ChatService(db: null)),
          sessionListProvider.overrideWith(
            (_) => Stream.value(const SessionSnapshot([], [])),
          ),
          authProvider.overrideWith(_FakeAuthNotifier.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showAvatarEditDialog(
                    context,
                    initial: initial,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('头像编辑'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('头像编辑'), findsNothing);
    expect(result, isFalse);
  });
}
