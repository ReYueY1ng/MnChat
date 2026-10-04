/// 动态通知页 —— get_channel_msg_list 频道通知列表。
///
/// 频道：评论(post_rep)/点赞(post_prize)/@我(post_at)/粉丝(fans_change)。
/// 每条通知：发起者昵称 + 摘要 + 时间；点击打开对应动态详情（pid）。
/// 进入页面时对当前频道执行已读（read_channel_msg）。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart';
import 'theme/app_tokens.dart';

class DynamicsNoticePage extends ConsumerStatefulWidget {
  const DynamicsNoticePage({super.key});

  @override
  ConsumerState<DynamicsNoticePage> createState() => _DynamicsNoticePageState();
}

class _DynamicsNoticePageState extends ConsumerState<DynamicsNoticePage>
    with SingleTickerProviderStateMixin {
  static const _channels = [
    DynamicsNoticeChannel.rep,
    DynamicsNoticeChannel.prize,
    DynamicsNoticeChannel.at,
    DynamicsNoticeChannel.fans,
  ];

  DynamicsClient? _client;
  late final TabController _tab;

  /// 每个频道的缓存。
  final Map<String, List<DynamicsNotice>> _cache = {};
  final Map<String, String?> _error = {};
  final Map<String, bool> _loading = {};

  @override
  void initState() {
    super.initState();
    final auth = ref.read(chatServiceProvider).auth;
    if (auth != null) {
      _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    }
    _tab = TabController(length: _channels.length, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _load(_channels[_tab.index]);
    });
    _load(_channels.first);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load(String channel) async {
    final client = _client;
    if (client == null) return;
    if (_loading[channel] == true) return;
    setState(() => _loading[channel] = true);
    try {
      final (list, _) = await client.fetchChannelNotice(channel);
      if (!mounted) return;
      setState(() {
        _cache[channel] = list;
        _error[channel] = null;
      });
      // 已读
      if (list.isNotEmpty) {
        final ids = list.map((n) => n.msgId).toList();
        unawaited(client.readChannelNotice(channel, ids));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error[channel] = '$e');
    } finally {
      if (mounted) setState(() => _loading[channel] = false);
    }
  }

  Future<void> _openDetail(DynamicsNotice n) async {
    final client = _client;
    if (client == null || n.pid.isEmpty) return;
    try {
      final post = await client.fetchPost(n.pid);
      if (!mounted || post == null) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DynamicsDetailPage(post: post)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('动态加载失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态通知'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: [
            for (final c in _channels)
              Tab(text: DynamicsNoticeChannel.label(c)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [for (final c in _channels) _buildChannel(c)],
      ),
    );
  }

  Widget _buildChannel(String channel) {
    if (_loading[channel] == true && (_cache[channel]?.isEmpty ?? true)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error[channel] != null && (_cache[channel]?.isEmpty ?? true)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error[channel]!),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: () => _load(channel),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final list = _cache[channel] ?? const <DynamicsNotice>[];
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(channel),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('暂无通知')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(channel),
      child: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final n = list[i];
          final name = n.nickname.isNotEmpty ? n.nickname : '${n.uin}';
          return ListTile(
            leading: AvatarView(name: name, radius: 22),
            title: Text(
              n.content.isNotEmpty ? n.content : _summary(n),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: RichTextView('$name · ${_fmtTime(n.time)}'),
            trailing: n.pid.isNotEmpty
                ? const Icon(Icons.chevron_right, size: 18)
                : null,
            onTap: n.pid.isNotEmpty ? () => _openDetail(n) : null,
          );
        },
      ),
    );
  }

  String _summary(DynamicsNotice n) {
    final type = n.msgType;
    if (type == 'fans_change') return '关注了你';
    if (type == 'post_prize') return '赞了你的动态';
    if (type == 'post_rep') return '评论了你的动态';
    if (type == 'post_at') return '@了你';
    return DynamicsNoticeChannel.label(n.channel);
  }

  static String _fmtTime(int ts) {
    if (ts <= 0) return '';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sub = now - ts;
    if (sub <= 60) return '刚刚';
    if (sub <= 3600) return '${sub ~/ 60}分钟前';
    if (sub <= 86400) return '${sub ~/ 3600}小时前';
    if (sub <= 2592000) return '${sub ~/ 86400}天前';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.month}-${p(d.day)}';
  }
}
