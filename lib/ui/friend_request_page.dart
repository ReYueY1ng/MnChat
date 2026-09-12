import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../core/models/messages.dart';
import '../state/providers.dart';
import 'widgets/avatar_view.dart';

/// 好友/群申请列表页 —— 两个 tab：好友申请 + 群邀请。
///
/// 好友申请来自推送扫描（relation==2），群邀请来自
/// query_user_groups_apply_list（同意/拒绝，对齐 newfriendservice.lua）。
class FriendRequestPage extends ConsumerStatefulWidget {
  const FriendRequestPage({super.key});

  @override
  ConsumerState<FriendRequestPage> createState() => _FriendRequestPageState();
}

class _FriendRequestPageState extends ConsumerState<FriendRequestPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('申请列表'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '好友申请'),
              Tab(text: '群邀请'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _FriendApplyTab(),
            _GroupApplyTab(onChanged: () {}),
          ],
        ),
      ),
    );
  }
}

/// 好友申请 tab。
class _FriendApplyTab extends ConsumerWidget {
  const _FriendApplyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests =
        ref.watch(friendRequestStreamProvider).asData?.value ??
            const <FriendRequest>[];
    if (requests.isEmpty) {
      return const Center(child: Text('暂无待处理的好友申请'));
    }
    return ListView.separated(
      itemCount: requests.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _RequestTile(request: requests[i]),
    );
  }
}

/// 群邀请 tab。
class _GroupApplyTab extends ConsumerStatefulWidget {
  final VoidCallback onChanged;

  const _GroupApplyTab({required this.onChanged});

  @override
  ConsumerState<_GroupApplyTab> createState() => _GroupApplyTabState();
}

class _GroupApplyTabState extends ConsumerState<_GroupApplyTab> {
  List<GroupApplyItem>? _items;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(chatServiceProvider);
    final group = service.group;
    if (group == null) {
      setState(() => _error = '未登录');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await group.queryGroupApplyList();
      final data = resp['data'];
      final items = <GroupApplyItem>[];
      if (data is List) {
        for (final e in data) {
          if (e is! Map) continue;
          items.add(GroupApplyItem.fromMap(e.cast<String, Object?>()));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  Future<void> _decide(GroupApplyItem item, bool agree) async {
    final group = ref.read(chatServiceProvider).group;
    if (group == null) return;
    setState(() => _loading = true);
    try {
      final resp = agree
          ? await group.agreeGroupApply(item.groupId)
          : await group.rejectGroupApply(item.groupId);
      final ret = resp['ret'];
      final ok = ret is num && (ret == 0 || ret == 4);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _items?.removeWhere((e) => e.groupId == item.groupId);
          _loading = false;
        });
        widget.onChanged();
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: ret=$ret')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final items = _items ?? const <GroupApplyItem>[];
    if (items.isEmpty) {
      return const Center(child: Text('暂无群邀请'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final item = items[i];
          return ListTile(
            leading: Icon(
              Icons.group_add_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(item.groupName.isNotEmpty ? item.groupName : '群 ${item.groupId}'),
            subtitle: Text(
              '邀请人 ${item.invitor} · 成员 ${item.memberNum}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '同意',
                  icon: Icon(Icons.check, color: Colors.green.shade600),
                  onPressed: _loading ? null : () => _decide(item, true),
                ),
                IconButton(
                  tooltip: '拒绝',
                  icon: Icon(Icons.close, color: theme.colorScheme.error),
                  onPressed: _loading ? null : () => _decide(item, false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 群邀请条目（对齐 CreateGroupChatServersMsg(4, data)，type="Invite"）。
class GroupApplyItem {
  final String groupId;
  final String groupName;
  final int creator;
  final int invitor;
  final int memberNum;

  const GroupApplyItem({
    required this.groupId,
    required this.groupName,
    required this.creator,
    required this.invitor,
    required this.memberNum,
  });

  static GroupApplyItem fromMap(Map<String, Object?> m) {
    final rawId = m['group_id'] ?? m['GroupID'];
    final rawCreator = m['creator'] ?? m['GroupCreator'] ?? 0;
    final rawInvitor = m['invitor'] ?? m['Inviter'] ?? 0;
    final rawMember = m['MemberNum'] ?? m['member_num'] ?? 1;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return GroupApplyItem(
      groupId: '$rawId',
      groupName: m['group_name']?.toString() ?? m['GroupName']?.toString() ?? '',
      creator: i(rawCreator),
      invitor: i(rawInvitor),
      memberNum: i(rawMember),
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
          ? const SizedBox(
              width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2))
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
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  if (sameDay) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的迷你号')),
      );
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
