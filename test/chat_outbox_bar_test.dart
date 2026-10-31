// 发件箱提示条：「N 条未发送」可见、重试按钮触发回调。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/ui/chat_page.dart';

import 'support/harness.dart';

void main() {
  Future<TestHarness> pumpBar(
    WidgetTester tester, {
    required int count,
    required Future<void> Function() onRetry,
  }) async {
    final harness = TestHarness.empty();
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            ChatOutboxBar(count: count, onRetry: onRetry),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
    return harness;
  }

  testWidgets('显示待发送数量并触发重试', (tester) async {
    var retries = 0;
    await pumpBar(
      tester,
      count: 3,
      onRetry: () async {
        retries++;
      },
    );
    expect(find.byKey(chatOutboxBarKey), findsOneWidget);
    expect(find.text('3 条消息未发送'), findsOneWidget);
    await tester.tap(find.byKey(chatOutboxRetryKey));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('重试按钮在异步执行期间不抛', (tester) async {
    var called = false;
    await pumpBar(
      tester,
      count: 1,
      onRetry: () async {
        called = true;
        await Future<void>.value();
      },
    );
    await tester.tap(find.byKey(chatOutboxRetryKey));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });
}
