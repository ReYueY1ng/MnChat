/// 主页「编辑布局」弹窗 —— 拖拽排序后保存回服务端。
///
/// 协议：`get_homepage_layout` / `change_homepage_layout`
/// （`playercenterv2/playercenterv2homepageservice.lua:26-66`）。
/// 布局条目由服务端以 JSON 串下发（同文件 `:87`），本弹窗**只调整顺序、
/// 不改动任何字段**，保存时原样回传，因此无需（也不应）臆造布局 schema。
library;

import 'package:flutter/material.dart';

import '../../core/models/homepage_modules.dart' show kHomeModuleNames;
import '../theme/app_tokens.dart';

/// 保存回调：返回 `true` 表示服务端接受本次布局。
typedef LayoutSaver =
    Future<bool> Function(List<Map<String, Object?>> layout);

/// 弹出「编辑布局」对话框；保存成功返回 `true`。
Future<bool> showHomeLayoutDialog(
  BuildContext context, {
  required List<Map<String, Object?>> layout,
  required LayoutSaver save,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _HomeLayoutDialog(initial: layout, save: save),
  );
  return ok ?? false;
}

class _HomeLayoutDialog extends StatefulWidget {
  final List<Map<String, Object?>> initial;
  final LayoutSaver save;

  const _HomeLayoutDialog({required this.initial, required this.save});

  @override
  State<_HomeLayoutDialog> createState() => _HomeLayoutDialogState();
}

class _HomeLayoutDialogState extends State<_HomeLayoutDialog> {
  late final List<Map<String, Object?>> _items = List.of(widget.initial);
  bool _busy = false;

  /// 条目标题：模块名（未收录的 id 回退为 `模块 <id>`，不臆造名称）。
  String _label(Map<String, Object?> e) {
    final raw = e['moduleId'];
    final id = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (id == null) return '未知模块';
    return kHomeModuleNames[id] ?? '模块 $id';
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await widget.save(_items);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('编辑布局'),
      contentPadding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, 0),
      content: SizedBox(
        width: 420,
        height: 380,
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          itemCount: _items.length,
          // 用 onReorderItem：该回调已为「移除 oldIndex 项」调整好 newIndex，
          // 不能再手动 `if (newIndex > oldIndex) newIndex -= 1`（会错位）。
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final item = _items.removeAt(oldIndex);
              _items.insert(newIndex, item);
            });
          },
          itemBuilder: (context, i) {
            final e = _items[i];
            final size = e['sizeType'];
            return ListTile(
              key: ValueKey<String>('layout-$i-${e['moduleId']}'),
              dense: true,
              leading: const Icon(Icons.drag_handle),
              title: Text(_label(e)),
              trailing: size == null
                  ? null
                  : Text(
                      '$size',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
