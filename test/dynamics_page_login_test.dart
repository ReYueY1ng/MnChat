// 动态页回归：冷启动时页面先于登录构建，登录完成后必须退出「未登录」。
//
// `_authMissing` 是 initState 阶段为了避开 Localizations 断言而落的状态位；
// 登录补跑 `_init` 时如果只设置不清除，页面就会永远停在「未登录」。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/services/auth.dart' show MiniAuth;
import 'package:mnchat/core/services/chat_service.dart' show ChatService;
import 'package:mnchat/core/services/dynamics.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/dynamics_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

/// 手动推进登录态的 AuthNotifier（不碰真实登录 / 网络）。
class _FakeAuthNotifier extends AuthNotifier {
  void emit(AuthState next) => state = next;
}

/// 空动态流，避免测试碰网络。
class _FakeDynamicsClient extends DynamicsClient {
  _FakeDynamicsClient() : super(uin: 1, s2: 's2', s2t: 's2t');

  @override
  Future<FeedResult> pullPostings(
    DynamicsFeedType type, {
    String from = 'null',
    int ct = 0,
    String? tag,
    int? opUin,
  }) async => const FeedResult([], 0);

  @override
  Future<List<DynamicsTag>> fetchPostingTags() async =>
      const <DynamicsTag>[];
}

void main() {
  testWidgets('冷启动未登录 → 登录后动态页退出「未登录」', (tester) async {
    final fakeClient = _FakeDynamicsClient();
    final container = ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(ChatService(db: null)),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        dynamicsClientFactoryProvider.overrideWithValue((_) => fakeClient),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const DynamicsPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('未登录'), findsOneWidget, reason: '未登录时先显示未登录');

    (container.read(authProvider.notifier) as _FakeAuthNotifier).emit(
      const AuthState(
        isLoggedIn: true,
        auth: MiniAuth(
          uin: 1,
          apiId: 1,
          name: '测试',
          s2: 's2',
          s2t: 's2t',
          jwt: 'jwt',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未登录'), findsNothing);
    expect(find.text('暂无动态，下拉刷新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
