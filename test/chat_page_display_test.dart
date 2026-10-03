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
  Widget harness(ChatService service) {
    final container = ProviderContainer(overrides: [
      chatServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: ChatPage(
            type: ChatSessionType.friend,
            sessionId: 273640665,
            name: '测试好友',
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
