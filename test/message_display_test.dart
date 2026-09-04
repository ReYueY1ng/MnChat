// ActiveSession 值语义回归测试。
//
// 迁移说明：flutter_chat_ui 迁移后，消息显示链路已由
// `ChatBridge`（eventStream → ChatController 增量 reconcile）接管，
// 原 messageHistoryProvider 的"事件驱动 provider 重新 yield"用例随之删除，
// 其覆盖由 test/chat_bridge_test.dart（链路层）与
// test/chat_page_display_test.dart（widget 层）等价接管。
//
// 本文件保留 ActiveSession 相等性回归：它是 activeSessionProvider 的
// 状态类型，被 MainShell/会话列表依赖，值语义破坏会导致 UI 无法识别
// "当前打开的会话"。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/state/providers.dart';

/// 非 const 构造 ActiveSession —— 模拟各处每次新建对象。
ActiveSession makeActive(ChatSessionType type, int id) => ActiveSession(type, id);

void main() {
  group('ActiveSession 值语义', () {
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
}
