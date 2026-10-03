import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/profile.dart' show PlayerProfile;
import '../state/providers.dart';
import 'player_home_page.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/rich_text_view.dart';

/// 关注 / 粉丝列表页。
///
/// 数据来自 `/server/friend` 的 `get_user_attention_list`（我关注的人）与
/// `get_user_fans_list`（关注我的人），对齐 playercenterv2focus/fanctrl.lua。
class RelationPage extends ConsumerStatefulWidget {
  const RelationPage({super.key});

  @override
  ConsumerState<RelationPage> createState() => _RelationPageState();
}

class _RelationPageState extends ConsumerState<RelationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  String? _error;
  List<int> _following = const [];
  List<int> _fans = const [];
  Map<int, PlayerProfile> _profiles = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final friend = ref.read(chatServiceProvider).friend;
      if (friend == null) throw StateError('未登录');
      final results = await Future.wait([
        friend.queryAttentionList(),
        friend.queryFansList(),
      ]);
      final following = _parseUins(results[0]['attention_list']);
      final fans = _parseUins(results[1]['fans_list']);
      final profiles = await _loadProfiles({...following, ...fans}.toList());
      if (!mounted) return;
      setState(() {
        _following = following;
        _fans = fans;
        _profiles = profiles;
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

  static int _num(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  /// 从 `attention_list` / `fans_list` 里抽出 uin（列表项可能是 int 或 `{uin:..}`）。
  static List<int> _parseUins(Object? raw) {
    final out = <int>[];
    void add(Object? v) {
      final n = _num(v);
      if (n > 0) out.add(n);
    }

    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          add(e['uin'] ?? e['Uin']);
        } else {
          add(e);
        }
      }
    }
    return out;
  }

  Future<Map<int, PlayerProfile>> _loadProfiles(List<int> uins) async {
    final client = ref.read(profileClientProvider);
    if (client == null || uins.isEmpty) return const {};
    final out = <int, PlayerProfile>{};
    for (var i = 0; i < uins.length; i += 20) {
      final batch = uins.sublist(i, (i + 20).clamp(0, uins.length));
      try {
        for (final p in await client.getProfileBatch3(batch)) {
          out[p.uin] = p;
        }
      } catch (_) {
        // 单批失败不阻断，退化为迷你号
      }
    }
    return out;
  }

  String _name(int uin) {
    final n = _profiles[uin]?.nickname ?? '';
    return n.isEmpty ? '$uin' : n;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关注与粉丝'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '我的关注 ${_following.length}'),
            Tab(text: '我的粉丝 ${_fans.length}'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView()
          : TabBarView(
              controller: _tabs,
              children: [
                _list(_following, '还没有关注任何人'),
                _list(_fans, '还没有粉丝'),
              ],
            ),
    );
  }

  Widget _errorView() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: scheme.outline),
            const SizedBox(height: 12),
            Text('加载失败：$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _list(List<int> uins, String empty) {
    if (uins.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Text(empty, style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: uins.length,
        itemBuilder: (context, i) {
          final uin = uins[i];
          final p = _profiles[uin];
          return ListTile(
            visualDensity: kAvatarListTileDensity,
            minTileHeight: headFrameSlotSize(24),
            leading: AvatarView(
              name: _name(uin),
              avatarUrl: p?.avatarUrl,
              headType: p?.headType,
              headId: p?.headId,
              frameId: p?.headFrameId,
            ),
            title: RichTextView(_name(uin)),
            subtitle: Text('迷你号 $uin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PlayerHomePage(targetUin: uin)),
            ),
          );
        },
      ),
    );
  }
}
