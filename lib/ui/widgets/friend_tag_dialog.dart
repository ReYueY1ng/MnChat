/// 给好友打标签 / 管理标签池。
///
/// 对齐反编译 `main_newfriendsmgrctrl.lua:941-1291` 的标签面板：
/// - 列出标签池，已有该标签的好友显示「已打」；
/// - 点一个标签 = 给选中的好友打/去标签（`batch_set_friend_label`，opType 1/2）；
/// - 「清除标签」= `batch_clear_friend_labels`；
/// - 长按 / 删除按钮 = 从标签池删掉（`set_friend_label_pool` opType 0）；
/// - 「+ 新建标签」= `set_friend_label_pool` opType 1（文案 base64）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/friend_tag.dart';
import '../../core/services/request_errors.dart' show responseOk;
import '../../state/providers.dart';
import '../theme/app_tokens.dart';
import 'friend_filter_dialog.dart' show showCreateFriendTagDialog;

/// 打开「标签」面板：[uins] 为要操作的好友（单个 = 从会话菜单进来）。
Future<void> showFriendTagDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<int> uins,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FriendTagDialog(ref: ref, uins: uins),
  );
}

class _FriendTagDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final List<int> uins;

  const _FriendTagDialog({required this.ref, required this.uins});

  @override
  ConsumerState<_FriendTagDialog> createState() => _FriendTagDialogState();
}

class _FriendTagDialogState extends ConsumerState<_FriendTagDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = ref.watch(friendTagPoolProvider).asData?.value;
    return AlertDialog(
      title: Text(widget.uins.length > 1
          ? '给 ${widget.uins.length} 位好友打标签'
          : '标签'),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      content: SizedBox(
        width: 360,
        child: tags == null
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        '你还未创建标签',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final t in tags) _tagRow(theme, t),
                          ],
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _busy ? null : _createTag,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建标签'),
                  ),
                  if (widget.uins.length > 1)
                    TextButton.icon(
                      onPressed: _busy ? null : _clearAll,
                      icon: const Icon(Icons.label_off_outlined, size: 16),
                      label: const Text('清除这些好友的标签'),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _tagRow(ThemeData theme, FriendTag t) {
    // 选中的好友是否都已打上这个标签（决定点它是"打"还是"去"）。
    final all =
        widget.uins.isNotEmpty && widget.uins.every((u) => t.uins.contains(u));
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        all ? Icons.label : Icons.label_outline,
        color: all ? theme.colorScheme.primary : null,
      ),
      title: Text(t.label),
      subtitle: t.uins.isEmpty ? null : Text('${t.uins.length} 位好友'),
      onTap: _busy
          ? null
          : () => _toggleTag(t, add: !all),
      trailing: IconButton(
        tooltip: '删除标签',
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: _busy ? null : () => _deleteTag(t),
      ),
    );
  }

  Future<void> _toggleTag(FriendTag t, {required bool add}) async {
    await _run(
      () => ref
          .read(chatServiceProvider)
          .setFriendLabels(
            widget.uins,
            opType: add ? 1 : 2,
            tagId: t.tagId,
          ),
      add ? '已打标签' : '已取消标签',
    );
  }

  Future<void> _clearAll() async {
    await _run(
      () => ref.read(chatServiceProvider).clearFriendLabels(widget.uins),
      '已清除标签',
    );
  }

  Future<void> _createTag() async {
    final label = await showCreateFriendTagDialog(context);
    if (label == null || !mounted) return;
    await _run(
      () => ref
          .read(chatServiceProvider)
          .setFriendLabelPool(opType: 1, label: label),
      '已创建「$label」',
    );
  }

  Future<void> _deleteTag(FriendTag t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除标签「${t.label}」'),
        content: const Text('删除后该标签会从所有好友身上移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref
          .read(chatServiceProvider)
          .setFriendLabelPool(opType: 0, tagId: t.tagId),
      '已删除标签',
    );
  }

  /// 执行一次标签写入；[okText] 只在**服务端确实受理**时才提示。
  ///
  /// 原先只 catch 异常就报成功 —— 而 `{"result":N}` 里的业务失败不会抛，
  /// 所以删/建失败也照样显示「已创建」。现在用 [responseOk] 看业务码，
  /// 失败时把码原样显示出来。
  Future<void> _run(
    Future<Map<String, Object?>> Function() action,
    String okText,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resp = await action();
      if (!responseOk(resp)) {
        final code = resp['result'] ?? resp['code'] ?? resp['ret'];
        messenger.showSnackBar(
          SnackBar(content: Text('服务端未受理（result=$code）')),
        );
        return;
      }
      ref.invalidate(friendTagPoolProvider);
      messenger.showSnackBar(SnackBar(content: Text(okText)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('操作失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
