import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../core/models/messages.dart';
import '../state/providers.dart';
import 'widgets/avatar_view.dart';

/// 好友申请列表页 —— 展示待处理申请，提供通过/拒绝。
class FriendRequestPage extends ConsumerWidget {
  const FriendRequestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(friendRequestStreamProvider).asData?.value ?? const <FriendRequest>[];
    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: requests.isEmpty
          ? const Center(child: Text('暂无待处理的好友申请'))
          : ListView.separated(
              itemCount: requests.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = requests[i];
                return _RequestTile(request: r);
              },
            ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  final FriendRequest request;

  const _RequestTile({required this.request});

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).acceptFriendRequest(widget.request.uin);
      _toast('已添加好友');
    } catch (e) {
      _toast('通过失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).rejectFriendRequest(widget.request.uin);
      _toast('已拒绝');
    } catch (e) {
      _toast('拒绝失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;
    return ListTile(
      leading: AvatarView(name: r.name.isNotEmpty ? r.name : '${r.uin}'),
      title: Text(r.name.isNotEmpty ? r.name : '${r.uin}'),
      subtitle: Text('Uin: ${r.uin} · ${_fmtTime(r.time)}'),
      trailing: _busy
          ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '通过',
                  icon: Icon(Icons.check, color: Colors.green.shade600),
                  onPressed: _accept,
                ),
                IconButton(
                  tooltip: '拒绝',
                  icon: Icon(Icons.close, color: theme.colorScheme.error),
                  onPressed: _reject,
                ),
              ],
            ),
    );
  }
}

String _fmtTime(int ts) {
  if (ts <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final now = DateTime.now();
  final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  if (sameDay) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// 弹出"按迷你号添加好友"对话框。返回是否发起了申请。
Future<bool> showAddFriendDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('添加好友'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '迷你号 (Uin)',
          hintText: '输入对方的迷你号',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('发送申请'),
        ),
      ],
    ),
  );
  if (result != true) return false;
  final text = controller.text.trim();
  final uin = int.tryParse(text);
  if (uin == null || uin <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效的迷你号')));
    }
    return false;
  }
  if (!context.mounted) return false;
  await _doApply(context, uin, ref);
  return true;
}

Future<void> _doApply(BuildContext context, int uin, WidgetRef ref) async {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(chatServiceProvider).applyFriend(uin);
    messenger.showSnackBar(SnackBar(content: Text('已向 $uin 发送好友申请')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('发送申请失败: $e'),
      backgroundColor: Colors.red.shade400,
    ));
  }
}