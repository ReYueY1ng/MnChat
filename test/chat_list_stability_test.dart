// 回归：聊天消息列表的稳定性。
//
// 背景：flutter_chat_ui 2.12 的 ChatAnimatedList，若控制器 `setMessages` 的
// diff 里出现「同 id、内容不同」的 change 更新（`_onChanged` = removeItem 后同
// 位置 insertItem），会触发 SliverAnimatedList 索引断言 / 「GlobalKey 重复出现
// 在树上」，整段消息列表渲染失败（用户侧表现为「进入会话后消息全不见」）。
//
// 两道防线：
//  1. ChatBridge.stabilizeSameIds —— 同 id 一律沿用既有实例，diff 只剩
//     insert/remove/move，永不产生 change（单测见 chat_bridge_test.dart）；
//  2. 空态走 flutter_chat_ui 的 emptyChatListBuilder，不整体替换 ChatAnimatedList
//     （避免其 GlobalKey 反复挂载/卸载）。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mnchat/chat/chat_bridge.dart' show stabilizeSameIds;

Widget buildChat(ChatController controller) {
  return MaterialApp(
    home: Scaffold(
      body: Chat(
        chatController: controller,
        currentUserId: '1',
        resolveUser: (id) async => null,
        onMessageSend: (_) async {},
        builders: Builders(
          chatAnimatedListBuilder: (context, itemBuilder) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.2),
            ),
            child: ChatAnimatedList(itemBuilder: itemBuilder),
          ),
          emptyChatListBuilder: (context) => const Center(child: Text('空')),
          chatMessageBuilder:
              (context, message, index, animation, child, {
              isRemoved,
              required isSentByMe,
              groupStatus,
            }) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (index % 3 == 0)
                  const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text('时间条'),
                  ),
                child,
              ],
            ),
        ),
      ),
    ),
  );
}

Message _msg(String id, {String text = 'x'}) => Message.text(
  id: id,
  authorId: '1',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
  text: text,
);

/// 模拟 ChatBridge：目标列表里同 id 的条目沿用 current 的既有实例。
Future<void> applyLikeBridge(
  InMemoryChatController c,
  List<Message> target,
) async {
  await c.setMessages(stabilizeSameIds(c.messages, target));
}

void main() {
  testWidgets('空↔非空切换不崩（不整表替换 ChatAnimatedList）', (tester) async {
    final c = InMemoryChatController(messages: [_msg('a'), _msg('b')]);
    await tester.pumpWidget(buildChat(c));
    await tester.pump();

    await c.setMessages(const []);
    await tester.pump();
    await tester.pump();

    await applyLikeBridge(c, [_msg('a'), _msg('b'), _msg('c')]);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('同 id 内容变化：stabilize 后不产生 change，不崩', (tester) async {
    final c = InMemoryChatController(
      messages: [_msg('a', text: 'v0'), _msg('b')],
    );
    await tester.pumpWidget(buildChat(c));
    await tester.pump();

    for (var i = 1; i <= 5; i++) {
      // 目标里 'a' 内容不同，但 stabilize 会换成 current 里的实例
      await applyLikeBridge(c, [_msg('a', text: 'v$i'), _msg('b')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('超过上限的裁剪（删头插尾）不崩', (tester) async {
    final c = InMemoryChatController();
    await tester.pumpWidget(buildChat(c));
    await tester.pump();

    for (var i = 0; i < 60; i++) {
      final next = [for (var j = 0; j <= i; j++) _msg('m$j')];
      final capped = next.length > 50 ? next.sublist(next.length - 50) : next;
      await applyLikeBridge(c, capped);
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });
}
