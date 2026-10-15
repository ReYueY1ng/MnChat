// Widget 层验证：ChatPage 使用 flutter_chat_ui Chat 组件后，
// addLocalMessage 的消息通过桥接层自动上屏。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/chat_page.dart';

void main() {
  Widget harness(
    ChatService service, {
    bool wide = false,
    double textScale = 1.0,
  }) {
    final container = ProviderContainer(overrides: [
      chatServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: ChatPage(
                type: ChatSessionType.friend,
                sessionId: 273640665,
                name: '测试好友',
                wide: wide,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('ChatPage 渲染 Chat 组件', (tester) async {
    final service = ChatService(db: null);
    await tester.pumpWidget(harness(service));
    await tester.pump();

    // Chat 组件必须在树中
    expect(find.byType(Chat), findsOneWidget);

    // 排空 ChatAnimatedList 初始滚动遗留的 250ms timer，避免 "Timer still pending"
    await tester.pumpAndSettle();
  });

  testWidgets('空会话显示中文空态，收到消息后消失', (tester) async {
    final service = ChatService(db: null);
    await tester.pumpWidget(harness(service));
    await tester.pump();

    // 空态经 flutter_chat_ui 的 emptyChatListBuilder 渲染
    expect(find.text('打个招呼'), findsOneWidget);

    service.addLocalMessage(ChatSessionType.friend, 273640665, '第一条');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('打个招呼'), findsNothing);
    expect(find.text('第一条'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('返回箭头只认主壳告知的双栏标志，不再看窗口宽度', (tester) async {
    // 旧写法是 `MediaQuery.size.width >= 700`：横屏手机（窗口 800、内容区约 720
    // < 双栏断点 760）走单栏、聊天顶掉会话列表，却没有返回按钮。现在只看主壳
    // 传过来的 `wide`。
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 窗口很宽但主壳判定为单栏 → 必须有返回按钮。
    await tester.pumpWidget(harness(ChatService(db: null)));
    await tester.pump();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.pumpAndSettle();

    // 双栏（会话列表就在旁边）→ 不需要返回按钮。
    await tester.pumpWidget(harness(ChatService(db: null), wide: true));
    await tester.pump();
    expect(find.byTooltip('返回'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('快捷短语行高随系统字号缩放（否则大字号下短语被裁）', (tester) async {
    await tester.pumpWidget(harness(ChatService(db: null), textScale: 2.0));
    await tester.pump();

    // 短语行的盒子 = `Text('嗨~')` 最近的 SizedBox 祖先。
    final row = tester.getSize(
      find
          .ancestor(of: find.text('嗨~'), matching: find.byType(SizedBox))
          .first,
    );
    expect(
      row.height,
      greaterThan(36),
      reason: '行高必须随 textScaler 放大（2.0x 下应为 72，写死 36 会裁字）',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('聊天区跟随系统无障碍字号（不被应用内倍率整体覆盖）', (tester) async {
    // 旧写法 `copyWith(textScaler: TextScaler.linear(chatFontScale))` 把系统字号
    // 丢掉：应用内倍率默认 1.0，系统 2.0 也完全不生效。
    await tester.pumpWidget(harness(ChatService(db: null)));
    await tester.pump();
    final normal = tester.getSize(find.text('打个招呼')).height;
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(ChatService(db: null), textScale: 2.0));
    await tester.pump();
    final doubled = tester.getSize(find.text('打个招呼')).height;
    expect(
      doubled,
      greaterThan(normal * 1.5),
      reason: '系统字号 2x 必须体现在聊天区文字上',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('addLocalMessage 后消息通过桥接层上屏', (tester) async {
    final service = ChatService(db: null);
    await tester.pumpWidget(harness(service));
    await tester.pump();

    // 模拟发送成功后本地回显（等价 ChatPage._send 里 addLocalMessage）
    service.addLocalMessage(ChatSessionType.friend, 273640665, 'hello world');
    // 桥接层是异步的（eventStream microtask），需要多次 pump
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 消息必须渲染
    expect(find.text('hello world'), findsOneWidget);

    // 排空滚动 timer，避免 "Timer still pending"
    await tester.pumpAndSettle();
  });
}
