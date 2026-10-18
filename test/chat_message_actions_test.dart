// 消息长按操作的 widget 级验证：
// 长按弹出操作菜单（复制 / 引用 / 转发 / 多选 / 收藏 / 删除仅本机）、
// 点「复制」真的把正文写进系统剪贴板、长按有触觉反馈、多选进入选择模式。
//
// 平台通道用 `TestDefaultBinaryMessenger.setMockMethodCallHandler` 拦截
// `SystemChannels.platform`，因此断言的是一次真实的 platform 调用，而不是
// "调用了某个 Dart 方法"。
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/chat_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

void main() {
  const sessionId = 273640665;
  const body = '冒险开始啦';

  /// 挂载 ChatPage，并返回被拦截到的 platform 通道调用。
  Future<List<MethodCall>> pumpChat(
    WidgetTester tester, {
    String text = body,
  }) async {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final service = ChatService(db: null);
    service.addLocalMessage(ChatSessionType.friend, sessionId, text);
    final container = ProviderContainer(
      overrides: [chatServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // buildAppTheme 会挂上 AppSemanticColors extension（裸 MaterialApp 不够）。
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: ChatPage(
              type: ChatSessionType.friend,
              sessionId: sessionId,
              name: '测试好友',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('长按消息弹出操作菜单，并触发触觉反馈', (tester) async {
    final calls = await pumpChat(tester);
    expect(find.text(body), findsOneWidget);

    await tester.longPress(find.text(body));
    await tester.pumpAndSettle();

    for (final label in ['复制', '引用', '转发', '多选', '收藏', '删除（仅本机）']) {
      expect(find.text(label), findsOneWidget, reason: '菜单应包含「$label」');
    }
    expect(
      calls.any((c) => c.method == 'HapticFeedback.vibrate'),
      isTrue,
      reason: '长按应有触觉反馈（platform 通道调用）',
    );
  });

  testWidgets('点「复制」把消息正文写进剪贴板', (tester) async {
    final calls = await pumpChat(tester);

    await tester.longPress(find.text(body));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    final setData = calls
        .where((c) => c.method == 'Clipboard.setData')
        .toList();
    expect(setData, isNotEmpty, reason: '应调用 Clipboard.setData');
    final args = setData.last.arguments as Map<Object?, Object?>;
    expect(args['text'], body);
  });

  testWidgets('点「多选」进入多选模式：标题显示已选条数、底部出现操作条', (tester) async {
    await pumpChat(tester);

    await tester.longPress(find.text(body));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已选'), findsWidgets);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('转发'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
  });

  testWidgets('多选模式下点消息可取消选中并退出多选', (tester) async {
    await pumpChat(tester);

    await tester.longPress(find.text(body));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选'), findsWidgets);

    // 再点同一条消息 → 取消选中（集合空）→ 退出多选，操作条消失。
    await tester.tap(find.text(body));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收藏'), findsNothing);
  });
}
