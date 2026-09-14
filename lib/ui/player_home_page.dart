/// 玩家主页 —— get_user_homepage 数据展示。
///
/// 展示目标玩家的：资料卡（头像/昵称/迷你号）、交友标签（social_sign）、
/// 家族、以及核心操作：关注/取关（attention_friend）、拉黑（handle_black）、
/// 访问（add_visit_record）。进入页面自动记一次访问。
///
/// 数据来源（对齐 playerCenterV2HomePageService）：
/// get_user_homepage(uin, target, module_list) → data{role_info{data{profile}},
/// social_sign, family, ...}。
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/player_home.dart';
import '../state/providers.dart';
import 'widgets/avatar_view.dart';
import 'theme/app_tokens.dart';
import 'widgets/rich_text_view.dart';

class PlayerHomePage extends ConsumerStatefulWidget {
  final int targetUin;

  const PlayerHomePage({super.key, required this.targetUin});

  @override
  ConsumerState<PlayerHomePage> createState() => _PlayerHomePageState();
}

class _PlayerHomePageState extends ConsumerState<PlayerHomePage> {
  PlayerHomeClient? _client;
  Map<String, Object?> _data = {};
  bool _loading = true;
  String? _error;

  // 关系状态（本地维护：关注/取关/拉黑）
  bool _following = false;
  bool _blacklisted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) return;
    _client = PlayerHomeClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
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
      final data = await client.getUserHomepage(widget.targetUin);
      // 关系状态：从 role_info.data.profile.relation 读取
      _syncRelation(data);
      // 记一次访问（受"留下踪迹"开关与 24h 去重约束，失败忽略）
      unawaited(_recordVisitIfNeeded(client));
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 必要时上报一次访问记录：受"留下踪迹"开关与 24h 去重约束，
  /// 失败静默忽略，绝不向 [_load] 抛异常。
  Future<void> _recordVisitIfNeeded(PlayerHomeClient client) async {
    try {
      final leaveTrace = ref.read(leaveVisitTraceProvider);
      if (!leaveTrace) return;
      final store = ref.read(settingsProvider);
      final targetUin = widget.targetUin;
      final lastSentAt = await store.visitSentAt(targetUin);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (!PlayerHomeClient.shouldRecordVisit(
        leaveTrace: leaveTrace,
        lastSentAt: lastSentAt,
        now: now,
      )) {
        return;
      }
      final ok = await client.addVisitRecord(targetUin);
      if (ok) await store.setVisitSentAt(targetUin, now);
    } catch (_) {
      // 失败忽略
    }
  }

  /// 解析关注/拉黑关系。对齐 profile.relation.friend_attention /
  /// friend_black 位掩码。
  void _syncRelation(Map<String, Object?> data) {
    final roleInfo = data['role_info'];
    if (roleInfo is! Map) return;
    final rd = roleInfo['data'];
    if (rd is! Map) return;
    final profile = rd['profile'];
    if (profile is! Map) return;
    final p = profile.cast<String, Object?>();
    final rel = p['relation'];
    if (rel is! Map) return;
    final r = rel.cast<String, Object?>();
    int bit(String k) {
      final v = r[k];
      if (v is num) return v.toInt();
      final n = int.tryParse('$v');
      return n ?? 0;
    }

    setState(() {
      _following = bit('friend_attention') == 1;
      _blacklisted = bit('friend_black') == 1;
    });
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(chatServiceProvider);
      await service.followPlayer(widget.targetUin, follow: !_following);
      if (!mounted) return;
      setState(() => _following = !_following);
      _toast(_following ? '已关注' : '已取消关注');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBlacklist() async {
    if (_busy) return;
    final ok = await _confirm(
      _blacklisted ? '移出黑名单' : '加入黑名单',
      _blacklisted ? '确定将 TA 移出黑名单吗？' : '拉黑后将无法看到 TA 的动态与消息，确定？',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(chatServiceProvider);
      if (_blacklisted) {
        await service.removeBlacklist(widget.targetUin);
      } else {
        await service.addBlacklist(widget.targetUin);
      }
      if (!mounted) return;
      setState(() => _blacklisted = !_blacklisted);
      _toast(_blacklisted ? '已加入黑名单' : '已移出黑名单');
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(String title, String message) => showDialog<bool>(
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 展示辅助 ─────────────────────────────────────────────────────────

  String get _nickname {
    final roleInfo = _data['role_info'];
    if (roleInfo is Map) {
      final rd = roleInfo['data'];
      if (rd is Map) {
        final profile = rd['profile'];
        if (profile is Map) {
          final p = profile.cast<String, Object?>();
          final ri = p['RoleInfo'];
          if (ri is Map) {
            final name = (ri.cast<String, Object?>())['NickName']?.toString();
            if (name != null && name.isNotEmpty) return name;
          }
        }
      }
    }
    return '${widget.targetUin}';
  }

  int? get _headFrameId {
    final roleInfo = _data['role_info'];
    if (roleInfo is Map) {
      final rd = roleInfo['data'];
      if (rd is Map) {
        final profile = rd['profile'];
        if (profile is Map) {
          final ri = (profile.cast<String, Object?>())['RoleInfo'];
          if (ri is Map) {
            final v = (ri.cast<String, Object?>())['head_frame_id'];
            if (v is num && v.toInt() > 0) return v.toInt();
            final n = int.tryParse('$v');
            if (n != null && n > 0) return n;
          }
        }
      }
    }
    return null;
  }

  String? get _avatarUrl {
    final roleInfo = _data['role_info'];
    if (roleInfo is Map) {
      final rd = roleInfo['data'];
      if (rd is Map) {
        final profile = rd['profile'];
        if (profile is Map) {
          final p = profile.cast<String, Object?>();
          for (final key in ['header3', 'header2', 'header']) {
            final h = p[key];
            if (h is Map) {
              final u = (h.cast<String, Object?>())['url']?.toString();
              if (u != null && u.isNotEmpty) return u;
            }
          }
        }
      }
    }
    return null;
  }

  String get _signature {
    final ss = _data['social_sign'];
    if (ss is Map) {
      final s = ss.cast<String, Object?>();
      int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      final social = i(s['social_lab'] ?? s['socialLab']);
      final game = i(s['game_lab'] ?? s['gameLab']);
      if (social != 0 || game != 0) {
        return formatDeclarationLocal(social, game);
      }
    }
    return '';
  }

  String get _familyName {
    final fam = _data['family'];
    if (fam is Map) {
      final f = fam['data'];
      if (f is Map) {
        final fm = f.cast<String, Object?>();
        final name = fm['family_name']?.toString() ?? fm['name']?.toString();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _nickname;
    return Scaffold(
      appBar: AppBar(
        title: RichTextView(name),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.narrowContent,
                ),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 资料卡
                    Row(
                      children: [
                        AvatarView(
                          name: name,
                          avatarUrl: _avatarUrl,
                          radius: 36,
                          frameId: _headFrameId,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '迷你号 ${widget.targetUin}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              if (_signature.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _signature,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                              if (_familyName.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.home,
                                      size: 14,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '家族: $_familyName',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 操作区
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _busy ? null : _toggleFollow,
                            icon: Icon(_following ? Icons.check : Icons.add),
                            label: Text(_following ? '已关注' : '关注'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _toggleBlacklist,
                            icon: Icon(
                              _blacklisted
                                  ? Icons.person_add_disabled
                                  : Icons.block,
                            ),
                            label: Text(_blacklisted ? '已拉黑' : '拉黑'),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    // 动态入口提示
                    ListTile(
                      leading: const Icon(Icons.public),
                      title: const Text('TA 的动态'),
                      subtitle: const Text('查看发布的动态内容'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('动态列表请在「动态 → 我的」中查看')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// 本地声明文案（与 social_sign.dart 对齐；避免引入额外依赖）。
String formatDeclarationLocal(int socialLab, int gameLab) {
  final parts = <String>[];
  if (socialLab != 0) parts.add('想要标签#$socialLab');
  if (gameLab != 0) parts.add('喜欢标签#$gameLab');
  return parts.join('，');
}
