import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'widgets/avatar_view.dart';

/// 群详情页 —— 成员列表 + 群主/管理操作（退出/解散/转让）。
class GroupDetailPage extends ConsumerStatefulWidget {
  final int groupId;
  final String name;

  const GroupDetailPage({super.key, required this.groupId, required this.name});

  @override
  ConsumerState<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends ConsumerState<GroupDetailPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 拉一次群详情（query_group），刷新成员/群主信息
    ref.read(chatServiceProvider).refreshGroupInfo(widget.groupId).catchError((_) => <String, Object?>{});
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(chatServiceProvider);
    final myUin = ref.watch(myUinProvider);
    final info = service.groupInfo(widget.groupId);
    final members = info?.members ?? const <int>[];
    final creatorUin = info?.creatorUin ?? 0;
    final isOwner = creatorUin == myUin;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name.isEmpty ? '群详情' : widget.name),
      ),
      body: ListView(
        children: [
          _InfoTile(icon: Icons.group, label: '群号', value: '${widget.groupId}'),
          _InfoTile(
            icon: Icons.person,
            label: '成员数',
            value: members.isEmpty ? '—' : '${members.length}',
          ),
          if (creatorUin != 0)
            _InfoTile(icon: Icons.star, label: '群主', value: _displayName(creatorUin, service)),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('成员', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('暂无成员信息（可能未拉取到）', style: TextStyle(color: Colors.grey)),
            )
          else
            ...members.map((uin) {
              final profile = service.groupMemberProfile(widget.groupId, uin);
              return _MemberTile(
                uin: uin,
                name: _displayName(uin, service),
                avatarUrl: profile?.avatarUrl,
                isOwner: uin == creatorUin,
                isSelf: uin == myUin,
              );
            }),

          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildActions(isOwner, myUin, creatorUin, members, service),
        ],
      ),
    );
  }

  Widget _buildActions(bool isOwner, int myUin, int creatorUin, List<int> members, dynamic service) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (isOwner) ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _showTransferDialog(members, creatorUin),
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('转让群主'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _confirmDissolve(service),
              icon: const Icon(Icons.delete_forever),
              label: const Text('解散群'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            ),
          ] else
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _confirmQuit(service),
              icon: const Icon(Icons.exit_to_app),
              label: const Text('退出群'),
            ),
        ],
      ),
    );
  }

  String _displayName(int uin, dynamic service) {
    // 优先群成员资料（getProfileBatch3 已回填昵称）
    final profile = service.groupMemberProfile(widget.groupId, uin);
    if (profile != null && profile.nickname.isNotEmpty) return profile.nickname;
    // 其次好友会话缓存
    final s = service.sessions.where((x) => x.type.name == 'friend' && x.id == uin).firstOrNull;
    if (s != null && s.name.isNotEmpty) return s.name;
    return '$uin';
  }

  Future<void> _confirmQuit(dynamic service) async {
    final ok = await _confirm('退出群', '确定退出该群吗？');
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      await service.quitGroup(widget.groupId);
      if (mounted) {
        Navigator.of(context).pop();
        _toast('已退出群');
      }
    } catch (e) {
      _toast('退出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDissolve(dynamic service) async {
    final ok = await _confirm('解散群', '解散后群内数据将不可恢复，确定解散？');
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      await service.dissolveGroup(widget.groupId);
      if (mounted) {
        Navigator.of(context).pop();
        _toast('群已解散');
      }
    } catch (e) {
      _toast('解散失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showTransferDialog(List<int> members, int creatorUin) async {
    final targets = members.where((u) => u != creatorUin).toList();
    if (targets.isEmpty) {
      _toast('没有可转让的成员');
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择新群主', style: TextStyle(fontWeight: FontWeight.w600))),
            ...targets.map(
              (uin) => ListTile(
                leading: const Icon(Icons.person),
                title: Text(_displayName(uin, ref.read(chatServiceProvider))),
                onTap: () => Navigator.pop(ctx, uin),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || _busy) return;
    final ok = await _confirm('转让群主', '确认将群主转给 ${_displayName(picked, ref.read(chatServiceProvider))}？');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).transferGroup(widget.groupId, picked);
      _toast('已转让');
    } catch (e) {
      _toast('转让失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return r ?? false;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final int uin;
  final String name;
  final String? avatarUrl;
  final bool isOwner;
  final bool isSelf;

  const _MemberTile({
    required this.uin,
    required this.name,
    this.avatarUrl,
    required this.isOwner,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AvatarView(name: name.isNotEmpty ? name : '$uin', avatarUrl: avatarUrl),
      title: Text(isSelf ? '$name（我）' : name),
      trailing: isOwner
          ? const Chip(label: Text('群主'), visualDensity: VisualDensity.compact)
          : null,
    );
  }
}
