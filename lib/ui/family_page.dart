import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/family.dart';
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart';

/// 家族页 —— 我的家族信息 + 成员列表 + 家族消息。
class FamilyPage extends ConsumerStatefulWidget {
  const FamilyPage({super.key});

  @override
  ConsumerState<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends ConsumerState<FamilyPage> {
  FamilyClient? _client;
  FamilyInfo? _family;
  final List<String> _messages = [];
  final TextEditingController _msgController = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  void _init() {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) {
      setState(() {
        _loading = false;
        _error = '未登录';
      });
      return;
    }
    _client = FamilyClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // get_family_list → 找我的家族 id → get_family_detail
      final listResp = await client.getFamilyList();
      final family = _findMyFamily(listResp);
      if (family != null) {
        final detail = await client.getFamilyDetail(family.familyId);
        _family = FamilyInfo.fromJson(detail) ?? family;
      } else {
        _family = null;
      }
    } catch (e) {
      _error = '加载失败: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 从 get_family_list 响应里取出我所在的家族（兼容 {family:..} / {families:[..]} / 顶层）。
  FamilyInfo? _findMyFamily(Map<String, Object?> resp) {
    if (FamilyInfo.fromJson(resp) case final f?) return f;
    final family = resp['family'];
    if (family is Map)
      return FamilyInfo.fromJson(family.cast<String, Object?>());
    final list = resp['families'] ?? resp['data'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) {
          final f = FamilyInfo.fromJson(e.cast<String, Object?>());
          if (f != null) return f;
        }
      }
    }
    return null;
  }

  Future<void> _sendMsg(String text) async {
    final t = text.trim();
    final family = _family;
    final client = _client;
    if (t.isEmpty || family == null || client == null) return;
    setState(() => _messages.add(t));
    _msgController.clear();
    try {
      await client.sendFamilyMsg(family.familyId, t);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
    }
  }

  Future<void> _quitFamily() async {
    final family = _family;
    final client = _client;
    if (family == null || client == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出家族'),
        content: Text('确定退出「${family.name}」吗？'),
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
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await client.quit(family.familyId);
      if (mounted) _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('退出失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家族'),
        actions: [
          IconButton(
            tooltip: '入族申请',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: _loading ? null : _showApplyList,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _body(),
    );
  }

  /// 入族申请列表（仅族长可见审批按钮）。
  Future<void> _showApplyList() async {
    final client = _client;
    final family = _family;
    if (client == null || family == null) return;
    final detail = await client.getFamilyDetail(family.familyId);
    if (!mounted) return;
    final data = detail['data'] ?? detail;
    final applies = <Map<String, Object?>>[];
    if (data is Map) {
      final al = data['apply_list'];
      if (al is List) {
        for (final e in al) {
          if (e is Map) applies.add(e.cast<String, Object?>());
        }
      }
    }
    if (applies.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无入族申请')));
      return;
    }
    final myUin = ref.read(myUinProvider);
    final isLeader = family.leaderUin == myUin;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                '入族申请',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ...applies.map((a) {
              final uin = (a['uin'] ?? a['Uin'] ?? 0) is num
                  ? ((a['uin'] ?? a['Uin']) as num).toInt()
                  : int.tryParse('${a['uin'] ?? a['Uin'] ?? 0}') ?? 0;
              final name = a['NickName']?.toString() ?? '$uin';
              return ListTile(
                leading: AvatarView(name: name),
                title: Text(name),
                subtitle: Text('迷你号 $uin'),
                trailing: isLeader
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '通过',
                            icon: Icon(
                              Icons.check,
                              color: AppSemanticColors.of(ctx).success,
                            ),
                            onPressed: () async {
                              await client.acceptJoin(
                                target: uin,
                                familyId: family.familyId,
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _toast('已通过');
                            },
                          ),
                          IconButton(
                            tooltip: '拒绝',
                            icon: Icon(
                              Icons.close,
                              color: Theme.of(ctx).colorScheme.error,
                            ),
                            onPressed: () async {
                              await client.acceptJoin(
                                target: uin,
                                familyId: family.familyId,
                                reject: true,
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _toast('已拒绝');
                            },
                          ),
                        ],
                      )
                    : null,
              );
            }),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text('$_error\n\n点击右上角刷新', textAlign: TextAlign.center),
      );
    }
    final family = _family;
    if (family == null) return const Center(child: Text('你尚未加入任何家族'));
    final myUin = ref.watch(myUinProvider);
    final isLeader = family.leaderUin == myUin;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              _InfoTile(icon: Icons.home, label: '家族', value: family.name),
              _InfoTile(
                icon: Icons.star,
                label: '族长',
                value: '${family.leaderUin}',
              ),
              _InfoTile(
                icon: Icons.groups,
                label: '成员数',
                value: '${family.memberCount}',
              ),
              if (family.notice != null && family.notice!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.campaign),
                  title: const Text('公告'),
                  subtitle: Text(family.notice!),
                ),
              const Divider(),
              if (family.members.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '成员',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ...family.members.map(
                  (m) => ListTile(
                    leading: AvatarView(
                      name: m.nickname.isNotEmpty ? m.nickname : '${m.uin}',
                    ),
                    title: RichTextView(
                      m.nickname.isNotEmpty ? m.nickname : '${m.uin}',
                    ),
                    trailing: m.isLeader
                        ? const Chip(
                            label: Text('族长'),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  ),
                ),
              ],
              const Divider(),
              // 家族消息
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  '家族消息',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    '暂无家族消息',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                ..._messages.map(
                  (m) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.chat_bubble_outline, size: 18),
                    title: Text(m),
                  ),
                ),
            ],
          ),
        ),
        // 消息输入 + 操作
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        decoration: const InputDecoration(
                          hintText: '发家族消息…',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: _sendMsg,
                      ),
                    ),
                    IconButton(
                      color: Theme.of(context).colorScheme.primary,
                      icon: const Icon(Icons.send),
                      onPressed: () => _sendMsg(_msgController.text),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _quitFamily,
                    child: const Text('退出家族'),
                  ),
                  if (isLeader) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _busy ? null : () {},
                      child: const Text('转让族长'),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
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
