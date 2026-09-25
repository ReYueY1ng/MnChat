import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/auth.dart' show MiniAuth;
import 'package:mnchat/core/services/chat_service.dart'
    show ChatService, SessionSnapshot;
import 'package:mnchat/core/services/family.dart'
    show FamilyInfo, FamilyShowInfo;
import 'package:mnchat/core/services/player_home.dart' show SetTopFlagResult;
import 'package:mnchat/core/services/profile.dart' show DiyHeadInfo, PortraitItem;
import 'package:mnchat/core/services/title_config.dart'
    show
        OwnedTitle,
        TitleCatalog,
        TitleConfigEntry,
        TitleShowData,
        TitleType;
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

/// 称号配置目录（名称 + 分类，分类顺序对齐远程 `title_typeList`）。
///
/// 过滤语义：`title.sort == title_typeList[].id`（`commontitleconfig.lua:70-83`
/// 的 `v.sort == type`，`type` 即 `playercenterv2headeditorctrl.lua:1755`
/// 的 `value.id`），故各条目 `sort` 取所属分类的 `id`。
const _catalog = TitleCatalog(
  entries: {
    101: TitleConfigEntry(id: 101, name: '星尘守护者', sort: 2),
    102: TitleConfigEntry(id: 102, name: '迷你季限定', sort: 4),
    103: TitleConfigEntry(id: 103, name: '自定义称号', sort: 5),
  },
  types: [
    TitleType(id: 2, name: '开发者', sort: 2),
    TitleType(id: 4, name: '迷你季', sort: 3),
    TitleType(id: 3, name: '其他', sort: 4),
    TitleType(id: 5, name: '自定义', sort: 5),
  ],
);

/// 已拥有称号（`get_title_showdata`）。
const _titles = TitleShowData(
  owned: [
    OwnedTitle(id: 101, startTime: 1753977600, expireTime: -1),
    OwnedTitle(id: 102, startTime: 1753977600, expireTime: 1790000000),
  ],
  expired: [
    OwnedTitle(id: 103, startTime: 0, expireTime: 1700000000, expired: true),
  ],
  useTitleId: 101,
);

/// 头像编辑弹窗回归测试。
///
/// 覆盖：外壳（标题 / 左 nav / 关闭）、头像页签（来源分类、`自定义` 真实上传
/// 入口、DIY 审核态、4 列网格、右栏提示）、头像框页签（`置顶` 降级提示）、
/// 昵称页签（校验驱动 `确认修改` 可用态 + 未连接返回码文案）、称号页签
/// （分类 + 真实称号 + 有效期 + 佩戴）、家族页签（懒加载列表 + 展示家族切换）。
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
    showFamilyId: 1,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    AvatarEditInitialData data = initial,
    FamilyListLoader? familyLoader,
    FamilyShowLoader? showFamilyLoader,
    FamilySwitcher? familySwitcher,
    DiyHeadLoader? diyLoader,
    DiyAvatarUploader? diyUploader,
    TitleLoader? titleLoader,
    TitleCatalogLoader? titleCatalogLoader,
    TitleWearer? titleWearer,
    FrameTopLoader? frameTopLoader,
    FrameTopToggler? frameTopToggler,
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
            body: AvatarEditDialog(
              initial: data,
              familyLoader: familyLoader,
              showFamilyLoader: showFamilyLoader,
              familySwitcher: familySwitcher,
              diyLoader: diyLoader ?? () async => null,
              diyUploader: diyUploader,
              titleLoader: titleLoader,
              titleCatalogLoader: titleCatalogLoader,
              titleWearer: titleWearer,
              frameTopLoader: frameTopLoader,
              frameTopToggler: frameTopToggler,
            ),
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
    expect(find.byKey(avatarEditDiyUploadKey), findsOneWidget);
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
  });

  testWidgets('头像页签：DIY 审核态（审核中 / 审核失败）与上传入口', (tester) async {
    await pumpDialog(
      tester,
      diyLoader: () async => const DiyHeadInfo(
        preUrl: 'https://example.com/pre.png',
        useDiy: false,
        type: 1,
        id: 1,
      ),
    );
    expect(tester.takeException(), isNull);
    // 审核中：DIY 格子 + `审核中` 角标。
    expect(find.byKey(avatarEditDiyCellKey), findsOneWidget);
    expect(find.text('审核中'), findsOneWidget);

    // 上传入口：注入上传器成功 → 成功提示。
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
            body: AvatarEditDialog(
              initial: initial,
              diyLoader: () async => null,
              diyUploader: () async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(avatarEditDiyUploadKey));
    await tester.pumpAndSettle();
    expect(find.text('上传成功，等待审核'), findsOneWidget);
  });

  testWidgets('头像页签：DIY 审核失败不可选（提示违规）', (tester) async {
    await pumpDialog(
      tester,
      diyLoader: () async => const DiyHeadInfo(
        preUrl: 'https://example.com/pre.png',
        auditFail: true,
        useDiy: false,
        type: 1,
        id: 1,
      ),
    );
    expect(find.text('审核失败'), findsOneWidget);
    await tester.tap(find.byKey(avatarEditDiyCellKey));
    await tester.pumpAndSettle();
    expect(find.text('当前图片违规无法使用'), findsOneWidget);
  });

  testWidgets('头像框页签：4 列帧网格 + 默认框官方文案', (tester) async {
    await pumpDialog(tester, frameTopLoader: () async => const <int>{});
    await tapNav(tester, '头像框');
    expect(tester.takeException(), isNull);

    expect(find.byKey(avatarEditFrameCellKey(1)), findsOneWidget);
    expect(find.byKey(avatarEditFrameCellKey(20201)), findsOneWidget);
    // 默认框（id=1）展示 GetS(5300) 官方文案。
    expect(find.text('默认头像框'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
  });

  testWidgets('头像框页签：<框名>: <获取途径> + 置顶真实切换', (tester) async {
    final toggled = <int, bool>{};
    await pumpDialog(
      tester,
      data: const AvatarEditInitialData(
        uin: 10001,
        name: 'MoonReloaded',
        headType: 1,
        headId: 1,
        frameId: 20201,
        ownedFrames: {1, 20201},
      ),
      // 20201 已置顶 → 按钮应为「取消置顶」。
      frameTopLoader: () async => const {20201},
      frameTopToggler: (id, pin) async {
        toggled[id] = pin;
        return const SetTopFlagResult(ok: true);
      },
    );
    await tapNav(tester, '头像框');
    expect(tester.takeException(), isNull);

    // 说明文案取自 itemdef.csv（Name: GetWay）。
    expect(find.text('单身汪: 双十一活动获取'), findsOneWidget);
    expect(find.text('取消置顶'), findsOneWidget);

    // 取消置顶 → op_type=0。
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();
    expect(toggled[20201], isFalse);
    expect(find.text('已取消置顶'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);

    // 让上一个 SnackBar 消失，避免新提示排队不可见。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 再次置顶 → op_type=1。
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(toggled[20201], isTrue);
    expect(find.text('已置顶'), findsOneWidget);
    expect(find.text('取消置顶'), findsOneWidget);
  });

  testWidgets('头像框页签：置顶被服务端拒绝时原样展示其 msg', (tester) async {
    await pumpDialog(
      tester,
      data: const AvatarEditInitialData(
        uin: 10001,
        name: 'MoonReloaded',
        headType: 1,
        headId: 1,
        frameId: 20201,
        ownedFrames: {1, 20201},
      ),
      frameTopLoader: () async => const <int>{},
      frameTopToggler: (id, pin) async =>
          const SetTopFlagResult(ok: false, message: '置顶数量已达上限'),
    );
    await tapNav(tester, '头像框');
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    // 不硬编码上限数字：透传服务端文案。
    expect(find.text('置顶数量已达上限'), findsOneWidget);
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

  testWidgets('称号页签：真实称号 + 有效期 + 分类筛选 + 佩戴', (tester) async {
    var worn = 0;
    await pumpDialog(
      tester,
      titleCatalogLoader: () async => _catalog,
      titleLoader: () async => _titles,
      titleWearer: (id) async {
        worn = id;
        return true;
      },
    );
    await tapNav(tester, '称号');
    expect(tester.takeException(), isNull);

    // 分类行逐字对齐参考图（来自远程配置顺序）。
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
    // 全部：三个称号都展示，且各带 `有效期`。
    expect(find.text('星尘守护者'), findsOneWidget);
    expect(find.text('迷你季限定'), findsOneWidget);
    expect(find.text('自定义称号'), findsOneWidget);
    expect(find.text('有效期'), findsNWidgets(3));
    // 永久称号的有效期区间以 `--永久` 结尾。
    expect(find.textContaining('--永久'), findsOneWidget);

    // 分类筛选：`开发者` 只保留 sort==2 的称号。
    await tester.tap(
      find.descendant(
        of: find.byKey(avatarEditTitleTabsKey),
        matching: find.text('开发者'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('星尘守护者'), findsOneWidget);
    expect(find.text('迷你季限定'), findsNothing);
    expect(find.text('自定义称号'), findsNothing);

    // 佩戴：当前佩戴者（101）不重复提交，选另一个。
    await tester.tap(
      find.descendant(
        of: find.byKey(avatarEditTitleTabsKey),
        matching: find.text('迷你季'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(avatarEditTitleCellKey(102)));
    await tester.pumpAndSettle();
    expect(worn, 102);
    expect(find.text('称号已佩戴'), findsOneWidget);
  });

  testWidgets('称号页签：无分类配置时仅全部可用，其余分类诚实空态', (tester) async {
    await pumpDialog(
      tester,
      // 名称可用但分类缺失：非「全部」无法筛选。
      titleCatalogLoader: () async => TitleCatalog(entries: _catalog.entries),
      titleLoader: () async => _titles,
    );
    await tapNav(tester, '称号');
    expect(find.text('星尘守护者'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(avatarEditTitleTabsKey),
        matching: find.text('开发者'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('称号分类配置未获取'), findsOneWidget);
  });

  testWidgets('家族页签：懒加载列表 + 展示家族切换', (tester) async {
    var loadCount = 0;
    var switched = 0;
    await pumpDialog(
      tester,
      familyLoader: () async {
        loadCount++;
        return const [
          FamilyInfo(familyId: 1, name: 'MoonX'),
          FamilyInfo(familyId: 2, name: '繁花拥雪'),
        ];
      },
      showFamilyLoader: () async =>
          const FamilyShowInfo(familyId: 1, name: 'MoonX'),
      familySwitcher: (id) async {
        switched = id;
        return true;
      },
    );
    expect(loadCount, 0, reason: '未切到家族页签时不应请求');

    await tapNav(tester, '家族');
    expect(loadCount, 1);
    expect(find.text('MoonX'), findsOneWidget);
    expect(find.text('繁花拥雪'), findsOneWidget);

    final first = find.byKey(avatarEditFamilyCellKey(1));
    expect(
      find.descendant(of: first, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(avatarEditFamilyCellKey(2)),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNothing,
    );

    // 点选第二个家族 → 调用 set_show_family 并切换选中态。
    await tester.tap(find.text('繁花拥雪'));
    await tester.pumpAndSettle();
    expect(switched, 2);
    expect(find.text('展示家族已更新'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(avatarEditFamilyCellKey(2)),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.byIcon(Icons.check_circle)),
      findsNothing,
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
                    diyLoader: () async => null,
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
