import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/family.dart';
import '../core/services/profile.dart' show PlayerProfile, ProfileClient;
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

  /// 已加入的全部家族（游戏里一个账号可以加入多个；`query_user_family_id_list`）。
  List<FamilyInfo> _families = const [];

  /// 当前展示的是第几个家族（切换用）。
  int _selected = 0;

  FamilyInfo? _family;

  /// 成员 / 申请者的头像（DIY 自定义头像 / 角色头像本体）。
  ///
  /// 家族接口只给 `uin`+昵称，不给头像；这类列表以前一律显示首字，现在按
  /// 「DIY 头像 → 角色头像本体 → 首字」补齐（同好友列表）。
  Map<int, PlayerProfile> _avatars = const {};
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
      // 多家族：先拿已加入的家族 id 列表（`get_family_list` 只回一条），
      // 再逐个查详情；拿不到 id 列表时回退到旧的单条接口。
      List<Object> ids = const [];
      try {
        ids = await client.queryUserFamilyIds();
      } catch (_) {
        // 忽略：回退到 get_family_list
      }
      final infos = <FamilyInfo>[];
      if (ids.isNotEmpty) {
        for (final id in ids) {
          try {
            final detail = await client.getFamilyDetail(id);
            final info = detail.info;
            if (info != null) infos.add(info);
          } catch (_) {
            // 单个家族详情失败不影响其它家族
          }
        }
      }
      if (infos.isEmpty) {
        infos.addAll(await client.getFamilyList());
      }
      if (!mounted) return;
      setState(() {
        _families = infos;
        if (_selected >= infos.length) _selected = 0;
        _family = infos.isEmpty ? null : infos[_selected];
      });
      // 家族成员头像（拿不到就保持首字占位，不阻断加载）。
      await _loadAvatars(infos.expand((f) => f.members.map((m) => m.uin)));
    } catch (e) {
      _error = '加载失败: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 批量补头像（家族成员 / 入族申请者）。失败保持首字。
  Future<void> _loadAvatars(Iterable<int> uins) async {
    final list = uins.where((u) => u > 0).toSet().toList();
    if (list.isEmpty) return;
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) return;
    try {
      final map = await ProfileClient(
        uin: auth.uin,
        s2: auth.s2,
        s2t: auth.s2t,
      ).fetchAvatarProfiles(list);
      if (!mounted || map.isEmpty) return;
      setState(() => _avatars = {..._avatars, ...map});
    } catch (_) {
      // 拉不到头像就继续用首字占位
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('退出失败: $e')));
      }
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
    final applies = detail.applies;
    if (applies.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无入族申请')));
      return;
    }
    await _loadAvatars(applies.map((a) => a.uin));
    if (!mounted) return;
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
              final uin = a.uin;
              // 昵称已在 FamilyApply.fromJson 里洗过富文本标记。
              final name = a.nickname;
              return ListTile(
                leading: AvatarView(
                  name: name,
                  avatarUrl: _avatars[uin]?.avatarUrl,
                  headType: _avatars[uin]?.headType,
                  headId: _avatars[uin]?.headId,
                  frameId: _avatars[uin]?.headFrameId,
                ),
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
              // 加入多个家族时给出切换（游戏允许一个账号加入多个家族）。
              if (_families.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    '已加入 ${_families.length} 个家族',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (var i = 0; i < _families.length; i++)
                        ChoiceChip(
                          label: Text(_families[i].name),
                          selected: i == _selected,
                          onSelected: (_) => setState(() {
                            _selected = i;
                            _family = _families[i];
                          }),
                        ),
                    ],
                  ),
                ),
                const Divider(),
              ],
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
                  padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
                  child: Text(
                    '成员',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ...family.members.map(
                  (m) => ListTile(
                    leading: AvatarView(
                      name: m.nickname.isNotEmpty ? m.nickname : '${m.uin}',
                      avatarUrl: _avatars[m.uin]?.avatarUrl,
                      headType: _avatars[m.uin]?.headType,
                      headId: _avatars[m.uin]?.headId,
                      frameId: _avatars[m.uin]?.headFrameId,
                    ),
                    title: RichTextView(
                      m.nickname.isNotEmpty ? m.nickname : '${m.uin}',
                    ),
                    trailing: m.isLeader
                        ? Chip(
                            label: const Text('族长'),
                            visualDensity: adaptiveDensity(context),
                          )
                        : null,
                  ),
                ),
              ],
              const Divider(),
              // 家族消息
              const Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
                child: Text(
                  '家族消息',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_messages.isEmpty)
                Padding(
                  padding: AppSpacing.listTilePadding,
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
                    const SizedBox(width: AppSpacing.sm),
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
