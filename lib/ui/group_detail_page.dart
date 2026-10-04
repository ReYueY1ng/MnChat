import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/nickname.dart' show plainNickname;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/rich_text_view.dart';

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

  /// 本地乐观记录的群置顶状态（服务端无查询接口，仅作按钮文案切换）。
  bool _groupTop = false;

  /// 本地乐观记录的群消息免打扰状态（服务端无查询接口）。
  bool _groupIgnored = false;

  /// 本地乐观记录的成员禁言 / 屏蔽状态（服务端无查询接口）。
  final Set<int> _silenced = {};
  final Set<int> _banned = {};

  @override
  void initState() {
    super.initState();
    // 拉一次群详情（query_group），刷新成员/群主信息
    ref
        .read(chatServiceProvider)
        .refreshGroupInfo(widget.groupId)
        .catchError((_) => <String, Object?>{});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final service = ref.watch(chatServiceProvider);
    final myUin = ref.watch(myUinProvider);
    final info = service.groupInfo(widget.groupId);
    final members = info?.members ?? const <int>[];
    final creatorUin = info?.creatorUin ?? 0;
    final isOwner = creatorUin == myUin;

    return Scaffold(
      appBar: AppBar(
        title: RichTextView(widget.name.isEmpty ? '群详情' : widget.name),
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
            _InfoTile(
              icon: Icons.star,
              label: '群主',
              value: _displayName(creatorUin, service),
            ),

          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text('成员', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (members.isEmpty)
            Padding(
              padding: AppSpacing.listTilePadding,
              child: Text(
                '暂无成员信息（可能未拉取到）',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ...members.map((uin) {
              final profile = service.groupMemberProfile(widget.groupId, uin);
              return _MemberTile(
                uin: uin,
                name: _displayName(uin, service),
                avatarUrl: profile?.avatarUrl,
                headType: profile?.headType,
                headId: profile?.headId,
                headFrameId: profile?.headFrameId,
                isOwner: uin == creatorUin,
                isSelf: uin == myUin,
                onTap: uin == myUin
                    ? null
                    : () => _showMemberActions(uin, isOwner: isOwner),
              );
            }),

          if (_busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildActions(isOwner, myUin, creatorUin, members, service),
        ],
      ),
    );
  }

  Widget _buildActions(
    bool isOwner,
    int myUin,
    int creatorUin,
    List<int> members,
    dynamic service,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _showInviteDialog(service),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('邀请好友入群'),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _toggleGroupTop,
            icon: Icon(_groupTop ? Icons.push_pin : Icons.push_pin_outlined),
            label: Text(_groupTop ? '取消群置顶' : '群置顶'),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _toggleGroupIgnore,
            icon: Icon(
              _groupIgnored
                  ? Icons.notifications_off
                  : Icons.notifications_off_outlined,
            ),
            label: Text(_groupIgnored ? '取消群免打扰' : '群消息免打扰'),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isOwner) ...[
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _editGroupName,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('修改群名'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _rejectAllGroupApplies,
              icon: const Icon(Icons.clear_all),
              label: const Text('一键拒绝入群申请'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _showTransferDialog(members, creatorUin),
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('转让群主'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _confirmDissolve(service),
              icon: const Icon(Icons.delete_forever),
              label: const Text('解散群'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
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

  /// 邀请好友入群：好友选择器（仅双向好友）→ join_group(op_uin)。
  Future<void> _showInviteDialog(dynamic service) async {
    final contacts =
        service.contacts.where((c) => (c.relation & 8) != 0).toList()..sort(
          (a, b) =>
              a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase()),
        );
    if (contacts.isEmpty) {
      _toast('暂无好友可邀请');
      return;
    }
    final selected = <int>{};
    final picked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    '选择要邀请的好友',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (ctx, i) {
                      final c = contacts[i];
                      final plainName = plainNickname(c.nickname);
                      final name = plainName.isEmpty ? '${c.uin}' : plainName;
                      final checked = selected.contains(c.uin);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(name),
                        subtitle: Text('迷你号 ${c.uin}'),
                        // secondary 同样受 ListTile 密度钳制（桌面紧凑密度下 48），
                        // 会把有框槽位（radius * 2 / 0.76 ≈ 52.6）压成非正方形并
                        // 裁掉框外圈；抬高纵向密度解决（见 [kAvatarListTileDensity]）。
                        visualDensity: kAvatarListTileDensity,
                        secondary: AvatarView(
                          name: name,
                          radius: 20,
                          headType: c.headType,
                          headId: c.headId,
                          frameId: c.headFrameId,
                        ),
                        onChanged: (v) {
                          setSheetState(() {
                            if (v == true) {
                              selected.add(c.uin);
                            } else {
                              selected.remove(c.uin);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(child: Text('已选 ${selected.length} 人')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(ctx, true),
                        child: const Text('邀请'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != true || selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final info = ref.read(chatServiceProvider).groupInfo(widget.groupId);
      await ref
          .read(chatServiceProvider)
          .group
          ?.inviteToGroup(
            groupId: widget.groupId,
            uins: selected.toList(),
            groupName: widget.name,
            lord: info?.creatorUin ?? 0,
            isAllowMemberInvite: 0,
          );
      _toast('已发送邀请');
    } catch (e) {
      _toast('邀请失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _displayName(int uin, dynamic service) {
    // 优先群成员资料（getProfileBatch3 已回填昵称）
    final profile = service.groupMemberProfile(widget.groupId, uin);
    if (profile != null && profile.nickname.isNotEmpty) return profile.nickname;
    // 其次好友会话缓存
    final s = service.sessions
        .where((x) => x.type.name == 'friend' && x.id == uin)
        .firstOrNull;
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
            const ListTile(
              title: Text(
                '选择新群主',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
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
    final ok = await _confirm(
      '转让群主',
      '确认将群主转给 ${_displayName(picked, ref.read(chatServiceProvider))}？',
    );
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

  /// 群置顶开关（服务端 act=set_group_top，本地乐观记录文案）。
  Future<void> _toggleGroupTop() async {
    final target = !_groupTop;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).setGroupTop(
            widget.groupId,
            top: target,
          );
      if (mounted) setState(() => _groupTop = target);
      _toast(target ? '已置顶群' : '已取消置顶');
    } catch (e) {
      _toast('置顶失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 一键拒绝全部入群申请（act=reject_group_apply_all，仅群主）。
  Future<void> _rejectAllGroupApplies() async {
    final ok = await _confirm('一键拒绝', '拒绝本群全部待处理的入群申请？');
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).rejectAllGroupApplies(widget.groupId);
      _toast('已全部拒绝');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 群消息免打扰开关（服务端 act=set_slient_group，本地乐观记录文案）。
  Future<void> _toggleGroupIgnore() async {
    final target = !_groupIgnored;
    setState(() => _busy = true);
    try {
      await ref
          .read(chatServiceProvider)
          .setGroupIgnore(widget.groupId, ignore: target);
      if (mounted) setState(() => _groupIgnored = target);
      _toast(target ? '已开启群免打扰' : '已关闭群免打扰');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 修改群名（act=update_group；头像 id/type 原样回传，避免被重置）。
  Future<void> _editGroupName() async {
    final info = ref.read(chatServiceProvider).groupInfo(widget.groupId);
    final ctrl = TextEditingController(text: info?.name ?? widget.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改群名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: '群名称',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(chatServiceProvider).updateGroupInfo(
            widget.groupId,
            name: name,
            iconId: info?.iconId ?? 0,
            iconType: info?.iconType ?? 0,
          );
      _toast('已更新群名');
    } catch (e) {
      _toast('更新失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 成员操作：禁言/解除、屏蔽/解除、移出该群（仅群主）、举报。
  Future<void> _showMemberActions(int uin, {required bool isOwner}) async {
    final name = _displayName(uin, ref.read(chatServiceProvider));
    final silenced = _silenced.contains(uin);
    final banned = _banned.contains(uin);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(plainNickname(name)),
                dense: true,
                enabled: false,
              ),
              const Divider(height: 1),
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.volume_off_outlined),
                  title: Text(silenced ? '解除该成员禁言' : '禁言该成员'),
                  onTap: () => Navigator.pop(ctx, 'silent'),
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(banned ? '解除屏蔽该成员' : '屏蔽该成员消息'),
                onTap: () => Navigator.pop(ctx, 'ban'),
              ),
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text('移出该群'),
                  onTap: () => Navigator.pop(ctx, 'kick'),
                ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('举报该成员'),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;

    final svc = ref.read(chatServiceProvider);

    if (action == 'kick') {
      final info = svc.groupInfo(widget.groupId);
      final ok = await _confirm('移出群成员', '确定将 ${plainNickname(name)} 移出本群？');
      if (!ok || _busy) return;
      setState(() => _busy = true);
      try {
        await svc.kickGroupMembers(
          widget.groupId,
          uins: [uin],
          groupCreator: info?.creatorUin ?? 0,
          groupName: info?.name ?? widget.name,
        );
        _toast('已移出该成员');
      } catch (e) {
        _toast('操作失败: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    setState(() => _busy = true);
    try {
      switch (action) {
        case 'silent':
          final target = !silenced;
          await svc.setGroupMemberSilent(
            widget.groupId,
            opUin: uin,
            silent: target,
          );
          if (mounted) {
            setState(() {
              if (target) {
                _silenced.add(uin);
              } else {
                _silenced.remove(uin);
              }
            });
          }
          _toast(target ? '已禁言' : '已解除禁言');
        case 'ban':
          final target = !banned;
          await svc.setGroupMemberBanned(
            widget.groupId,
            opUin: uin,
            ban: target,
          );
          if (mounted) {
            setState(() {
              if (target) {
                _banned.add(uin);
              } else {
                _banned.remove(uin);
              }
            });
          }
          _toast(target ? '已屏蔽该成员消息' : '已解除屏蔽');
        case 'report':
          await svc.reportGroupMember(widget.groupId, opUin: uin);
          _toast('已提交举报');
      }
    } catch (e) {
      _toast('操作失败: $e');
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
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

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final int uin;
  final String name;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? headFrameId;
  final bool isOwner;
  final bool isSelf;

  /// 点击成员行（自己为 null，不弹操作）。
  final VoidCallback? onTap;

  const _MemberTile({
    required this.uin,
    required this.name,
    this.avatarUrl,
    this.headType,
    this.headId,
    this.headFrameId,
    required this.isOwner,
    required this.isSelf,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      // 单行 ListTile 的 leading 上限与行高都受密度钳制（桌面紧凑密度下仅 48），
      // 装不下框盒（radius * 2 / 0.76 ≈ 63.2）：抬高纵向密度把上限提到 68，
      // 并用 minTileHeight 兜住行高，所有成员行高度一致（见 [kAvatarListTileDensity]）。
      visualDensity: kAvatarListTileDensity,
      minTileHeight: headFrameSlotSize(24),
      leading: AvatarView(
        name: name.isNotEmpty ? name : '$uin',
        avatarUrl: avatarUrl,
        headType: headType,
        headId: headId,
        frameId: headFrameId,
      ),
      title: RichTextView(isSelf ? '$name（我）' : name),
      trailing: isOwner
          ? Chip(
              label: const Text('群主'),
              visualDensity: adaptiveDensity(context),
            )
          : null,
    );
  }
}
