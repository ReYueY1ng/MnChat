// Ctrl+K 快速切换：过滤、回车/点击打开会话。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart' show SessionSnapshot;
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/widgets/session_quick_switcher.dart';

import 'support/harness.dart';

void main() {
  const sessions = <ChatSession>[
    ChatSession(id: 1001, type: ChatSessionType.friend, name: '阿里'),
    ChatSession(id: 2002, type: ChatSessionType.group, name: '冒险小队'),
    ChatSession(id: 3003, type: ChatSessionType.friend, name: '小北'),
  ];

  Future<ProviderContainer> pumpAndOpen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        sessionListProvider.overrideWith(
          (ref) => Stream.value(const SessionSnapshot(sessions, [])),
        ),
      ],
    );
    final harness = TestHarness(container);
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSessionQuickSwitcher(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('列出全部会话；输入过滤；点击打开并关闭弹层', (tester) async {
    final container = await pumpAndOpen(tester);
    expect(find.byKey(sessionQuickSwitcherKey), findsOneWidget);
    expect(find.text('阿里'), findsOneWidget);
    expect(find.text('冒险小队'), findsOneWidget);

    await tester.enterText(
      find.byKey(sessionQuickSwitcherFieldKey),
      '冒险',
    );
    await tester.pumpAndSettle();
    expect(find.text('冒险小队'), findsOneWidget);
    expect(find.text('阿里'), findsNothing);

    await tester.tap(find.text('冒险小队'));
    await tester.pumpAndSettle();
    expect(find.byKey(sessionQuickSwitcherKey), findsNothing);
    expect(container.read(activeSessionProvider)?.id, 2002);
    expect(container.read(activeSessionProvider)?.type, ChatSessionType.group);
  });

  testWidgets('迷你号也能匹配；无结果显示空态', (tester) async {
    await pumpAndOpen(tester);
    await tester.enterText(
      find.byKey(sessionQuickSwitcherFieldKey),
      '3003',
    );
    await tester.pumpAndSettle();
    expect(find.text('小北'), findsOneWidget);
    expect(find.text('阿里'), findsNothing);

    await tester.enterText(
      find.byKey(sessionQuickSwitcherFieldKey),
      '不存在的人',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的会话'), findsOneWidget);
  });

  testWidgets('回车打开第一条匹配', (tester) async {
    final container = await pumpAndOpen(tester);
    await tester.enterText(
      find.byKey(sessionQuickSwitcherFieldKey),
      '阿里',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(container.read(activeSessionProvider)?.id, 1001);
  });
}
