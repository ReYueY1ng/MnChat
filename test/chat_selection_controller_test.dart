// 多选状态控制器：进出多选、切换、选中顺序与正文拼接。
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/ui/chat_selection_controller.dart';

void main() {
  final messages = <Message>[
    Message.text(
      id: 'a',
      authorId: '1',
      text: 'first',
      createdAt: DateTime(2026, 10, 1),
    ),
    Message.text(
      id: 'b',
      authorId: '2',
      text: 'second',
      createdAt: DateTime(2026, 10, 1, 0, 1),
    ),
    Message.text(
      id: 'c',
      authorId: '2',
      text: '',
      createdAt: DateTime(2026, 10, 1, 0, 2),
    ),
  ];

  ChatSelectionController controller() => ChatSelectionController(
    messages: () => messages,
    textOf: (m) => m is TextMessage ? m.text : '',
  );

  test('初始不在多选；begin 进入并选中一条', () {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);
    expect(c.active, isFalse);
    c.begin('b');
    expect(c.active, isTrue);
    expect(c.count, 1);
    expect(c.contains('b'), isTrue);
    expect(c.selected.map((m) => m.id).toList(), ['b']);
    expect(notified, 1);
  });

  test('toggle 增删；清空后自动退出多选', () {
    final c = controller()..begin('a');
    c.toggle('b');
    expect(c.ids, {'a', 'b'});
    c.toggle('a');
    expect(c.ids, {'b'});
    c.toggle('b');
    expect(c.active, isFalse);
  });

  test('selected 按列表顺序；selectedText 跳过空正文并换行拼接', () {
    final c = controller()
      ..begin('c')
      ..toggle('a');
    expect(c.selected.map((m) => m.id).toList(), ['a', 'c']);
    expect(c.selectedText, 'first');
  });

  test('未进入多选时 toggle/exit 是空操作，selected 为空', () {
    final c = controller();
    c.toggle('a');
    c.exit();
    expect(c.active, isFalse);
    expect(c.selected, isEmpty);
  });
}
