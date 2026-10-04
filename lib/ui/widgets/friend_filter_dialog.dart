/// 好友筛选对话框 —— 对齐反编译 `NewFriendsMgrFilterFrame`
/// （`newfriendsmgrfilterframectrl.lua:25-160`）：
///
/// ```text
/// 通用
///  ☐ 在线好友   ☐ 最佳拍档   ☐ 上线通知   ☐ 邀请一起玩的好友
/// 标签
///  （标签列表；一个标签都没有时显示「你还未创建标签」）
///                     [重置] [筛选]
/// ```
///
/// 语义：通用条件之间是 **AND**（`main_newfriendsmgrmodel.lua:117-143`），
/// 标签也是 AND（同一好友要同时命中选中的所有标签）。
library;

import 'package:material_ui/material_ui.dart';

import '../../core/models/friend_tag.dart';
import '../theme/app_tokens.dart';

/// 通用筛选条件（id 对齐游戏 `def_commonFilterType`：1/2/3/4）。
enum FriendFilterCommon {
  online('在线好友'),
  partner('最佳拍档'),
  onlineNotify('上线通知'),
  invitedMe('邀请一起玩的好友');

  const FriendFilterCommon(this.label);
  final String label;
}

/// 一次筛选的选中状态。
class FriendFilterState {
  final Set<FriendFilterCommon> common;
  final Set<int> tagIds;

  const FriendFilterState({
    this.common = const <FriendFilterCommon>{},
    this.tagIds = const <int>{},
  });

  bool get isEmpty => common.isEmpty && tagIds.isEmpty;

  FriendFilterState copyWith({
    Set<FriendFilterCommon>? common,
    Set<int>? tagIds,
  }) => FriendFilterState(
    common: common ?? this.common,
    tagIds: tagIds ?? this.tagIds,
  );
}

/// 打开筛选对话框；返回 null = 取消（不改变当前筛选）。
Future<FriendFilterState?> showFriendFilterDialog(
  BuildContext context, {
  required FriendFilterState current,
  required List<FriendTag> tags,
  VoidCallback? onCreateTag,
}) {
  return showDialog<FriendFilterState>(
    context: context,
    builder: (ctx) =>
        _FriendFilterDialog(current: current, tags: tags, onCreateTag: onCreateTag),
  );
}

class _FriendFilterDialog extends StatefulWidget {
  final FriendFilterState current;
  final List<FriendTag> tags;
  final VoidCallback? onCreateTag;

  const _FriendFilterDialog({
    required this.current,
    required this.tags,
    this.onCreateTag,
  });

  @override
  State<_FriendFilterDialog> createState() => _FriendFilterDialogState();
}

class _FriendFilterDialogState extends State<_FriendFilterDialog> {
  late Set<FriendFilterCommon> _common = {...widget.current.common};
  late Set<int> _tags = {...widget.current.tagIds};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('筛选'),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('通用', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final c in FriendFilterCommon.values)
                    FilterChip(
                      label: Text(c.label),
                      selected: _common.contains(c),
                      onSelected: (v) => setState(() {
                        v ? _common.add(c) : _common.remove(c);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('标签', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              if (widget.tags.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '你还未创建标签',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final t in widget.tags)
                      FilterChip(
                        label: Text(t.label),
                        selected: _tags.contains(t.tagId),
                        onSelected: (v) => setState(() {
                          v ? _tags.add(t.tagId) : _tags.remove(t.tagId);
                        }),
                      ),
                  ],
                ),
              if (widget.onCreateTag != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onCreateTag,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建标签'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _common = <FriendFilterCommon>{};
            _tags = <int>{};
          }),
          child: const Text('重置'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            FriendFilterState(common: _common, tagIds: _tags),
          ),
          child: const Text('筛选'),
        ),
      ],
    );
  }
}

/// 新建标签对话框（上限 [kFriendTagMaxLength] 个字）。
Future<String?> showCreateFriendTagDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建标签'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: kFriendTagMaxLength,
        decoration: const InputDecoration(hintText: '标签名（最多 5 个字）'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            Navigator.of(ctx).pop(v.isEmpty ? null : v);
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
}
