// Widget 层验证：ChatPage 在收到消息后真的把气泡渲染上屏。
// 这锁定"消息不显示"的 UI 根因修复 —— ActiveSession ==/hashCode 修复后，
// messageHistoryProvider 能稳定跟随 eventStream，addLocalMessage 必须立即上屏。
import 'package:flutter/material.dart';
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
          body: ChatPage(type: ChatSessionType.friend, sessionId: 273640665),
        ),
      ),
    );
  }

  testWidgets('addLocalMessage 后消息气泡立即上屏', (tester) async {
    final service = ChatService(db: null);
    await tester.pumpWidget(harness(service));
    await tester.pump();

    // 初始为空
    expect(find.text('暂无消息'), findsOneWidget);

    // 模拟发送成功后本地回显（等价 ChatPage._send 里 addLocalMessage）
    service.addLocalMessage(ChatSessionType.friend, 273640665, 'hello world');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 气泡必须渲染，不再显示"暂无消息"
    expect(find.text('暂无消息'), findsNothing);
    expect(find.text('hello world'), findsOneWidget);
  });
}
