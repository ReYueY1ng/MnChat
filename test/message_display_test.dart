// 消息显示链路回归测试：
// 1) ActiveSession 必须实现 ==/hashCode（messageHistoryProvider 的 family key），
//    否则每次 build 新建对象 → provider 反复重建 → 事件订阅丢失 → 消息不上屏。
// 2) messageHistoryProvider 必须随 eventStream 事件更新（addLocalMessage/推送触发）。
// 3) ChatService._replaceHistory 现在会发事件（chat_query 拉回历史能刷新窗口）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat_service.dart';
import 'package:mnchat/state/providers.dart';

/// 非 const 构造 ActiveSession —— 模拟 ChatPage.build 里每次新建对象。
ActiveSession makeActive(ChatSessionType type, int id) => ActiveSession(type, id);

void main() {
  group('ActiveSession family key 稳定性', () {
    test('非 const 相同 type+id 对象相等且 hashCode 相同', () {
      final a = makeActive(ChatSessionType.friend, 273640665);
      final b = makeActive(ChatSessionType.friend, 273640665);
      final c = makeActive(ChatSessionType.friend, 999);
      final d = makeActive(ChatSessionType.group, 273640665);

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == d, isFalse);
    });
  });

  group('消息事件驱动 provider 更新', () {
    test('addLocalMessage → eventStream → messageHistoryProvider 重新 yield', () async {
      final service = ChatService(db: null);
      final container = ProviderContainer(overrides: [
        chatServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);

      // 每次 watch 都用新建的 ActiveSession（模拟 build 重建）
      final active = makeActive(ChatSessionType.friend, 273640665);
      final listenable = container.listen(
        messageHistoryProvider(active),
        (_, _) {},
      );
      addTearDown(listenable.close);

      // 初始为空
      expect(listenable.read().value ?? const [], isEmpty);

      // 本地发送一条消息（等价于 UI 发送成功后回显）
      service.addLocalMessage(ChatSessionType.friend, 273640665, 'hello');
      await Future<void>.delayed(Duration.zero);

      final msgs = listenable.read().value ?? const <ChatMessage>[];
      expect(msgs, hasLength(1));
      expect(msgs.first.text, 'hello');
      expect(msgs.first.uin, service.myUin);
    });

    test('只有匹配会话的事件才触发该会话 provider 更新', () async {
      final service = ChatService(db: null);
      final container = ProviderContainer(overrides: [
        chatServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);

      final other = makeActive(ChatSessionType.friend, 999);
      final listenable = container.listen(
        messageHistoryProvider(other),
        (_, _) {},
      );
      addTearDown(listenable.close);

      // 往别的会话发消息，不应影响本会话
      service.addLocalMessage(ChatSessionType.friend, 273640665, 'to-other');
      await Future<void>.delayed(Duration.zero);
      expect(listenable.read().value ?? const [], isEmpty);

      // 本会话事件应触发
      service.addLocalMessage(ChatSessionType.friend, 999, 'to-me');
      await Future<void>.delayed(Duration.zero);
      expect(listenable.read().value ?? const [], hasLength(1));
    });
  });
}
