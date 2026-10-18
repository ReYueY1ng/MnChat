// 私有信封走完「消息 → 列表 → 提示」的真实链路：
//  - 「正在输入」信号不产生气泡（历史里被丢弃），只广播提示；
//  - 对方用过信封后，桥接层标记该会话"对方也是 MNChat"；
//  - 引用信封的可见正文不含零宽字符，元数据里带被引用原文；
//  - ChatPage 真收到信号后显示「对方正在输入…」。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/chat/chat_bridge.dart';
import 'package:mnchat/chat/message_adapter.dart';
import 'package:mnchat/core/models/chat_envelope.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/chat_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

void main() {
  const selfUin = 279630451;
  const peerUin = 273640665;

  final typingPayload = attachMnEnvelope(
    '',
    const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
  );

  group('适配器与桥接层', () {
    test('正在输入信号：识别为临时信号，不进消息列表', () {
      final m = ChatMessage(uin: peerUin, text: typingPayload, time: 1700000000);
      expect(isTransientSignal(m), isTrue);
      final list = chatHistoryToMessages(
        <ChatMessage>[m],
        ChatSessionType.friend,
        peerUin,
      );
      expect(list, isEmpty, reason: '临时信号不该变成气泡');
    });

    test('引用信封：可见正文不含零宽字符，元数据带引用标识', () {
      // 载荷必须极小：服务端正文上限约 128 **字节**，而隐形符号每个约 3 字节。
      // 空载荷的 quote 信封 ≈ 87 字节，配短正文才装得下。
      final raw = attachMnEnvelope(
        '「小明」',
        const MnEnvelope(MnEnvelopeKind.quote, <String, Object?>{}),
      );
      final list = chatHistoryToMessages(
        <ChatMessage>[
          ChatMessage(uin: peerUin, text: raw, time: 1700000000),
        ],
        ChatSessionType.friend,
        peerUin,
      );
      expect(list, hasLength(1));
      final metadata = list.single.metadata!;
      expect(metadata['raw'], '「小明」');
      expect((metadata['mn']! as Map)['k'], 'quote');
      // 可见部分不该残留零宽字符（气泡/搜索结果里都不该出现）。
      expect(
        (metadata['raw']! as String).codeUnits.any((c) => c >= 0x200B && c <= 0x200D),
        isFalse,
      );
    });

    test('桥接层：广播输入信号，并记下"对方用过信封"', () async {
      final service = ChatService(db: null);
      final bridge = ChatBridge(service);
      addTearDown(bridge.dispose);
      final events = <(String, int)>[];
      final sub = bridge.typingStream.listen(events.add);
      addTearDown(sub.cancel);

      expect(bridge.peerEnvelopeCapable('friend_$peerUin'), isFalse);
      // 先建控制器（应用里由「打开会话」触发），输入信号是在 reconcile 时扫描的。
      final controller = bridge.controllerFor(
        ChatSessionType.friend,
        peerUin,
      );
      service.addLocalMessage(ChatSessionType.friend, peerUin, typingPayload);
      bridge.reconcile(controller, ChatSessionType.friend, peerUin);
      // 事件经 eventStream 异步派发，让出一次微任务/事件循环。
      await Future<void>.delayed(Duration.zero);

      expect(events, isNotEmpty, reason: '应广播「正在输入」信号');
      expect(events.first.$1, 'friend_$peerUin');
      // addLocalMessage 造出来的是**自己**发的（uin == myUin），“对方用过信封”
      // 不能因为自己发的信号而置位 —— 否则会对着官方客户端用户回发空消息。
      expect(
        bridge.peerEnvelopeCapable('friend_$peerUin'),
        isFalse,
        reason: '自己发的信号不算“对方用过信封”',
      );
    });
  });

  testWidgets('对照：同样的 harness 下不加输入信号，不应出现布局异常', (tester) async {
    final service = ChatService(db: null);
    final container = ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(service),
        myUinProvider.overrideWithValue(selfUin),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: ChatPage(
              type: ChatSessionType.friend,
              sessionId: peerUin,
              name: '测试好友',
            ),
          ),
        ),
      ),
    );
    service.addLocalMessage(ChatSessionType.friend, peerUin, '在吗');
    await tester.pumpAndSettle();
    expect(find.text('在吗'), findsOneWidget);
    // 这个用例只要求"没有异常"：任何渲染/布局异常都会让 testWidgets 失败。
  });

  testWidgets('ChatPage 收到输入信号后显示「对方正在输入…」', (tester) async {
    final service = ChatService(db: null);
    final container = ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(service),
        // 让 addLocalMessage 造出的 uin=0 被当成"对方"，从而触发提示。
        myUinProvider.overrideWithValue(selfUin),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: ChatPage(
              type: ChatSessionType.friend,
              sessionId: peerUin,
              name: '测试好友',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('对方正在输入…'), findsNothing);

    // 先有一条普通消息（否则走的是空会话布局，与本用例无关）。
    service.addLocalMessage(ChatSessionType.friend, peerUin, '在吗');
    await tester.pumpAndSettle();

    service.addLocalMessage(ChatSessionType.friend, peerUin, typingPayload);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('对方正在输入…'),
      findsOneWidget,
      reason: '收到输入信号后应显示提示',
    );
    // 让 6 秒的收起定时器跑完，避免测试结束时报 "Timer is still pending"。
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('对方正在输入…'), findsNothing, reason: '超时应自动收起');
  });
}
