/// 聊天页多选状态（选中集合 + 进出多选 + 选中消息列表）。
///
/// 从 `_ChatPageState` 抽出的纯状态对象：不碰网络、不弹窗、不读 provider，
/// 只依赖「当前消息列表」与「消息正文」两个回调，因此可以直接单测。
library;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_chat_core/flutter_chat_core.dart' show Message;

class ChatSelectionController extends ChangeNotifier {
  ChatSelectionController({
    required this.messages,
    required this.textOf,
  });

  /// 当前列表里的消息（按渲染顺序）。
  final List<Message> Function() messages;

  /// 一条消息的可复制正文（用于批量复制/导出）。
  final String Function(Message) textOf;

  Set<String>? _ids;

  /// 当前选中 id；null 表示不在多选模式。
  Set<String>? get ids => _ids;

  bool get active => _ids != null;

  int get count => _ids?.length ?? 0;

  bool contains(String id) => _ids?.contains(id) ?? false;

  /// 进入多选并选中一条。
  void begin(String id) {
    _ids = <String>{id};
    notifyListeners();
  }

  /// 切换一条的选中状态；清空后自动退出多选。
  void toggle(String id) {
    final ids = _ids;
    if (ids == null) return;
    if (!ids.remove(id)) ids.add(id);
    if (ids.isEmpty) _ids = null;
    notifyListeners();
  }

  /// 退出多选。
  void exit() {
    if (_ids == null) return;
    _ids = null;
    notifyListeners();
  }

  /// 选中的消息（按列表顺序）；不在多选模式时为空。
  List<Message> get selected {
    final ids = _ids;
    if (ids == null || ids.isEmpty) return const <Message>[];
    return [
      for (final m in messages())
        if (ids.contains(m.id)) m,
    ];
  }

  /// 选中消息的正文（跳过空正文，每行一条）。
  String get selectedText => selected
      .map(textOf)
      .where((t) => t.isNotEmpty)
      .join('\n');
}
