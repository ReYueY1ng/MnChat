import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// 退群 / 被移出记录（`act=query_user_groups_quit_list`，对齐 friendservice.lua）。
///
/// 每条记录对应游戏里「你已退出 / 被移出 / 群已解散」的红点提醒，可单条清除
/// （`act=del_group_quit_list`）。
class QuitGroupPage extends ConsumerStatefulWidget {
  const QuitGroupPage({super.key});

  @override
  ConsumerState<QuitGroupPage> createState() => _QuitGroupPageState();
}

class _QuitRecord {
  final int groupId;
  final String name;
  final int type;
  const _QuitRecord(this.groupId, this.name, this.type);

  /// 记录类型文案（type 2=解散 / 3=被移出，其余按退出处理）。
  String get label => switch (type) {
        2 => '群已解散',
        3 => '你被移出该群',
        _ => '你已退出该群',
      };
}

class _QuitGroupPageState extends ConsumerState<QuitGroupPage> {
  bool _loading = true;
  String? _error;
  List<_QuitRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static int _num(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final group = ref.read(chatServiceProvider).group;
      if (group == null) throw StateError('未登录');
      final resp = await group.queryUserGroupsQuitList();
      final raw = resp['data'] ?? resp['quit_list'] ?? resp['list'];
      final out = <_QuitRecord>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final m = e.cast<String, Object?>();
          final gid = _num(m['group_id'] ?? m['groupId']);
          out.add(
            _QuitRecord(
              gid,
              (m['group_name'] ?? m['GroupName'] ?? (gid > 0 ? '群 $gid' : ''))
                  .toString(),
              _num(m['type']),
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _records = out;
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

  Future<void> _delete(_QuitRecord r) async {
    try {
      await ref.read(chatServiceProvider).delQuitGroupRecord(r.groupId);
      if (!mounted) return;
      setState(() => _records = [..._records]..remove(r));
      _toast('已清除记录');
    } catch (e) {
      _toast('清除失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('退群记录')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 40,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text('加载失败：$_error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _records.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            '没有退群记录',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _records.length,
                      itemBuilder: (context, i) {
                        final r = _records[i];
                        return ListTile(
                          leading: const Icon(Icons.group_off_outlined),
                          title: Text(r.name.isEmpty ? '群 ${r.groupId}' : r.name),
                          subtitle: Text(r.label),
                          trailing: IconButton(
                            tooltip: '清除',
                            icon: const Icon(Icons.close),
                            onPressed: () => _delete(r),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
