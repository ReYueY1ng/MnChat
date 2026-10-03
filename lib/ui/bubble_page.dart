import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// 聊天气泡页（`/miniw/business?act=bubble_get_data`）。
///
/// 气泡名称 / 图标来自游戏**内置**配置（`ns_business_config.bubble_cfg`），
/// 不是服务端下发，外部客户端拿不到 —— 因此这里只列已拥有的气泡编号 + 有效期，
/// 支持佩戴 / 取消佩戴（act=bubble_use_record）。对齐 chatbubbleservice.lua。
class BubblePage extends ConsumerStatefulWidget {
  const BubblePage({super.key});

  @override
  ConsumerState<BubblePage> createState() => _BubblePageState();
}

/// 一个已拥有的气泡。
class _OwnedBubble {
  final int id;
  final int timeout;
  const _OwnedBubble(this.id, this.timeout);

  bool get permanent => timeout < 0;
}

class _BubblePageState extends ConsumerState<BubblePage> {
  bool _loading = true;
  String? _error;
  int _using = 0;
  List<_OwnedBubble> _bubbles = const [];

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
      final client = ref.read(chatServiceProvider).bubble;
      if (client == null) throw StateError('未登录');
      final resp = await client.getData();
      final data = resp['data'];
      final m = data is Map ? data.cast<String, Object?>() : resp;
      final using = _num(m['using_bubble']);
      final list = m['bubble_list'];
      final out = <_OwnedBubble>[];
      if (list is Map) {
        for (final e in list.entries) {
          final id = _num(e.key);
          final v = e.value;
          final timeout = v is Map
              ? _num(v['timeout'] ?? v['expire_time'])
              : -1;
          if (id > 0) out.add(_OwnedBubble(id, timeout == 0 ? -1 : timeout));
        }
      }
      out.sort((a, b) => a.id.compareTo(b.id));
      if (!mounted) return;
      setState(() {
        _using = using;
        _bubbles = out;
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

  Future<void> _use(int id) async {
    final client = ref.read(chatServiceProvider).bubble;
    if (client == null) return;
    try {
      await client.useRecord(id);
      if (!mounted) return;
      setState(() => _using = id);
      _toast(id == 0 ? '已取消佩戴气泡' : '已佩戴气泡 #$id');
    } catch (e) {
      _toast('操作失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _expiryText(_OwnedBubble b) {
    if (b.permanent) return '永久';
    final d = DateTime.fromMillisecondsSinceEpoch(b.timeout * 1000);
    final now = DateTime.now();
    if (d.isBefore(now)) return '已过期';
    final mo = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '有效期至 $mo-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天气泡'),
        actions: [
          if (_using != 0)
            TextButton(
              onPressed: () => _use(0),
              child: const Text('取消佩戴'),
            ),
        ],
      ),
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
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '气泡名称/样式由游戏内置配置决定，外部客户端无法显示，'
                      '仅能切换佩戴。',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_bubbles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          '还没有可用气泡',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    ..._bubbles.map(
                      (b) => ListTile(
                        onTap: () => _use(b.id),
                        leading: Icon(
                          Icons.chat_bubble_outline,
                          color: _using == b.id
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        title: Text('气泡 #${b.id}'),
                        subtitle: Text(_expiryText(b)),
                        trailing: _using == b.id
                            ? Icon(Icons.check_circle, color: scheme.primary)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
