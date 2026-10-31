// 历史条与聊天页接线：加载更早的入口必须可见、可点、能到达 service。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/chat_page.dart';

import 'support/harness.dart';

/// 只负责历史分页的假服务：不碰数据库/网络，记录翻页调用。
class _PagedChatService extends ChatService {
  _PagedChatService() : super(db: null);

  int loadCalls = 0;
  bool older = true;

  final List<ChatMessage> _history = [
    ChatMessage(uin: 2, text: 'old', time: 1, isSuccess: true),
    ChatMessage(uin: 1, text: 'new', time: 2, isSuccess: true),
  ];

  @override
  List<ChatMessage> historyOf(ChatSessionType type, int id) =>
      List.unmodifiable(_history);

  @override
  Future<void> prepareHistory(
    ChatSessionType type,
    int id, {
    int limit = 200,
  }) async {}

  @override
  bool hasOlderHistory(ChatSessionType type, int id) => older;

  @override
  Future<int> loadOlderHistory(
    ChatSessionType type,
    int id, {
    int limit = ChatService.kHistoryPageSize,
  }) async {
    loadCalls++;
    return 0;
  }
}

void main() {
  Future<TestHarness> pumpBar(
    WidgetTester tester, {
    bool hasOlder = true,
    bool loading = false,
    DateTime? day,
    VoidCallback? onLoadOlder,
    VoidCallback? onJumpDate,
    VoidCallback? onLatest,
  }) async {
    final harness = TestHarness.empty();
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            ChatHistoryBar(
              hasOlder: hasOlder,
              loading: loading,
              day: day,
              onLoadOlder: onLoadOlder ?? () {},
              onJumpDate: onJumpDate ?? () {},
              onLatest: onLatest ?? () {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
    return harness;
  }

  group('ChatHistoryBar', () {
    testWidgets('没有任何可翻内容时不占空间', (tester) async {
      await pumpBar(tester, hasOlder: false);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byKey(chatHistoryLoadOlderKey), findsNothing);
    });

    testWidgets('有更早历史：显示加载与跳日期，点击回调', (tester) async {
      var loads = 0;
      var jumps = 0;
      await pumpBar(
        tester,
        onLoadOlder: () => loads++,
        onJumpDate: () => jumps++,
      );
      expect(find.text('加载更早'), findsOneWidget);
      expect(find.byKey(chatHistoryJumpDateKey), findsOneWidget);
      await tester.tap(find.byKey(chatHistoryLoadOlderKey));
      await tester.tap(find.byKey(chatHistoryJumpDateKey));
      expect(loads, 1);
      expect(jumps, 1);
    });

    testWidgets('加载中：按钮禁用并显示文案', (tester) async {
      await pumpBar(tester, loading: true);
      expect(find.text('加载中…'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(chatHistoryLoadOlderKey),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('历史窗口：只显示日期与回到最新', (tester) async {
      var latest = 0;
      await pumpBar(
        tester,
        day: DateTime(2026, 10, 1),
        onLatest: () => latest++,
      );
      expect(find.textContaining('2026-10-01'), findsOneWidget);
      expect(find.byKey(chatHistoryLoadOlderKey), findsNothing);
      await tester.tap(find.byKey(chatHistoryLatestKey));
      expect(latest, 1);
    });
  });

  group('自动加载更早的方向', () {
    // ChatAnimatedList 默认非反向：最新在底部（extentAfter == 0），
    // 更早在顶部（extentBefore == 0）。按 extentAfter 判断会在打开会话时
    // 立即拉「更早」并弹「没有更早的聊天记录」。
    FixedScrollMetrics metrics({
      required double pixels,
      double max = 1000,
      double viewport = 600,
      AxisDirection dir = AxisDirection.down,
    }) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: max,
      pixels: pixels,
      viewportDimension: viewport,
      axisDirection: dir,
      devicePixelRatio: 1.0,
    );

    test('停在最新一页（底部）不补更早', () {
      expect(shouldAutoLoadOlderHistory(metrics(pixels: 400)), isFalse);
    });

    test('滑到顶部（更早一端）才补一页', () {
      expect(shouldAutoLoadOlderHistory(metrics(pixels: 0)), isTrue);
    });

    test('内容不足一屏或横向滚动不触发', () {
      expect(shouldAutoLoadOlderHistory(metrics(pixels: 0, max: 0)), isFalse);
      expect(
        shouldAutoLoadOlderHistory(
          metrics(pixels: 0, dir: AxisDirection.right),
        ),
        isFalse,
      );
    });
  });

  group('ChatPage 接线', () {
    testWidgets('进入会话后历史条可见，点加载更早会调用服务', (tester) async {
      final service = _PagedChatService();
      final container = ProviderContainer(
        overrides: [chatServiceProvider.overrideWithValue(service)],
      );
      final harness = TestHarness(container);
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        Scaffold(
          body: ChatPage(
            type: ChatSessionType.friend,
            sessionId: 1001,
            name: '测试好友',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(chatHistoryLoadOlderKey), findsOneWidget);
      await tester.tap(find.byKey(chatHistoryLoadOlderKey));
      await tester.pumpAndSettle();
      expect(service.loadCalls, 1);
      expect(find.text('old'), findsOneWidget);
      expect(find.text('new'), findsOneWidget);
    });
  });
}
