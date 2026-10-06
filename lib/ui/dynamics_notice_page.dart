/// 动态通知页 —— `get_channel_msg_list` 六个频道通知列表。
///
/// 频道顺序与 id 对齐反编译 `miniui/module/dynamics/dynamicsdatamanager.lua`
/// 的 `DynamicsChannelType`，通知的取用 / 合并逻辑见同文件 2571-2668
/// `NewGetRedPointNoticeByChannel` 与 `MergeInteractiveFunc`：
///   评论(post_rep) → 点赞(post_prize) → @我(post_at) → 粉丝(fans_change)
///   → 系统(post_sys) → 地图互动(map_interact)
/// 标签统一取 [DynamicsNoticeChannel.labels]。
///
/// 每个频道：
/// - 分页拉取 `fetchChannelNotice(channel, offset: ...)`，`next_offset` 作为
///   「加载更多」游标（0 表示没有更多）；
/// - 进入频道时对当前页执行已读 `readChannelNotice(channel, msgIds)`；
/// - 空态 / 失败可重试，绝不静默空白；
/// - 条目 `pid` 非空才可点开动态详情（粉丝 / 系统等通知没有 pid）。
///
/// 频道按需懒加载：首屏只请求默认频道，切 tab 时才请求对应频道，
/// 不会一次打出六个请求。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/nickname.dart' show plainNickname;
import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'widgets/avatar_view.dart';
import 'theme/app_tokens.dart';

class DynamicsNoticePage extends ConsumerStatefulWidget {
  const DynamicsNoticePage({super.key, this.client});

  /// 注入的动态客户端；为 null 时按当前登录态自建（供测试替换网络）。
  final DynamicsClient? client;

  @override
  ConsumerState<DynamicsNoticePage> createState() => _DynamicsNoticePageState();
}

/// 单个频道的分页状态。
class _ChannelState {
  final List<DynamicsNotice> items = [];
  bool loading = false;
  bool loadingMore = false;
  bool loadedOnce = false;

  /// 「加载更多」游标；0 = 没有更多。
  int nextOffset = 0;

  /// 首屏失败文案；不清空已加载数据。
  String? error;

  /// 「加载更多」失败文案。
  String? moreError;

  bool get hasMore => nextOffset != 0;
}

class _DynamicsNoticePageState extends ConsumerState<DynamicsNoticePage>
    with SingleTickerProviderStateMixin {
  /// 六个频道，顺序对齐游戏 `DynamicsChannelType`（见库注释）。
  static const List<String> _channels = [
    DynamicsNoticeChannel.rep,
    DynamicsNoticeChannel.prize,
    DynamicsNoticeChannel.at,
    DynamicsNoticeChannel.fans,
    DynamicsNoticeChannel.sys,
    DynamicsNoticeChannel.mapInteract,
  ];

  /// 滚动到距底部该距离内自动触发「加载更多」。
  static const double _loadMoreExtent = 400;

  DynamicsClient? _client;
  late final TabController _tab;
  final Map<String, _ChannelState> _states = {};
  bool _openingDetail = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? _resolveClient();
    _tab = TabController(length: _channels.length, vsync: this);
    _tab.addListener(_onTabChanged);
    _load(_channels.first);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// 按登录态自建客户端；未登录或依赖未就绪 → null（页面降级为占位态）。
  DynamicsClient? _resolveClient() {
    try {
      final auth = ref.read(chatServiceProvider).auth;
      if (auth == null) return null;
      return DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    } catch (_) {
      // Provider 依赖未初始化（如未 override databaseProvider 的 widget 测试）：
      // 降级为「未登录」占位，而不是让整页抛异常。
      return null;
    }
  }

  _ChannelState _stateOf(String channel) =>
      _states.putIfAbsent(channel, _ChannelState.new);

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    final channel = _channels[_tab.index];
    final st = _stateOf(channel);
    if (!st.loadedOnce && !st.loading) _load(channel);
  }

  /// 拉取频道通知。[more] 为 true 时按 [nextOffset] 追加下一页。
  Future<void> _load(String channel, {bool more = false}) async {
    final client = _client;
    final st = _stateOf(channel);
    if (client == null) return;
    if (more) {
      if (!st.loadedOnce || st.loading || st.loadingMore || !st.hasMore) return;
      st.loadingMore = true;
      st.moreError = null;
    } else {
      if (st.loading) return;
      st.loading = true;
      st.error = null;
    }
    setState(() {});

    try {
      final (list, nextOffset) = await client.fetchChannelNotice(
        channel,
        offset: more ? st.nextOffset : 0,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          st.items.addAll(list);
        } else {
          st.items
            ..clear()
            ..addAll(list);
          st.loadedOnce = true;
        }
        st.nextOffset = nextOffset;
      });
      // 进入频道即已读：上报当前页的 msg_id。
      if (!more && list.isNotEmpty) {
        unawaited(
          client.readChannelNotice(channel, [for (final n in list) n.msgId]),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (more) {
          st.moreError = '加载更多失败';
        } else {
          st.error = '加载失败：$e';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (more) {
            st.loadingMore = false;
          } else {
            st.loading = false;
          }
        });
      }
    }
  }

  /// 打开条目对应的动态详情：先拉取动态，失败（已删除/不可见）则提示。
  Future<void> _openDetail(DynamicsNotice n) async {
    final client = _client;
    if (client == null || n.pid.isEmpty || _openingDetail) return;
    _openingDetail = true;
    try {
      final post = await client.fetchPost(n.pid);
      if (!mounted) return;
      if (post == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('动态已删除或不可见')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DynamicsDetailPage(post: post)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('动态加载失败：$e')),
      );
    } finally {
      _openingDetail = false;
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
    if (_client == null) {
      return const _NoticePlaceholder(
        icon: Icons.lock_outline,
        text: '未登录，无法加载动态通知',
      );
    }
    final st = _stateOf(channel);
    if (st.loading && st.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (st.error != null && st.items.isEmpty) {
      return _NoticePlaceholder(
        icon: Icons.error_outline,
        text: st.error!,
        onRetry: () => _load(channel),
      );
    }
    if (st.items.isEmpty) {
      return _NoticePlaceholder(
        icon: Icons.notifications_none,
        text: '暂无通知',
        onRefresh: () => _load(channel),
      );
    }
    final showMore = st.hasMore || st.loadingMore || st.moreError != null;
    return RefreshIndicator(
      onRefresh: () => _load(channel),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (st.hasMore && n.metrics.extentAfter < _loadMoreExtent) {
            _load(channel, more: true);
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: st.items.length + (showMore ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i >= st.items.length) return _moreTile(channel, st);
            return _noticeTile(st.items[i]);
          },
        ),
      ),
    );
  }

  Widget _noticeTile(DynamicsNotice n) {
    final name = plainNickname(n.nickname);
    final display = name.isNotEmpty ? name : '${n.uin}';
    final title = n.content.isNotEmpty ? n.content : _summary(n);
    final tappable = n.pid.isNotEmpty;
    return ListTile(
      leading: AvatarView(name: display, radius: 22),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$display · ${_fmtTime(n.time)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: tappable ? const Icon(Icons.chevron_right) : null,
      onTap: tappable ? () => _openDetail(n) : null,
    );
  }

  /// 「加载更多」页脚：加载中转圈，否则可点（失败后提示重试）。
  Widget _moreTile(String channel, _ChannelState st) {
    if (st.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final failed = st.moreError != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: TextButton(
          onPressed: () => _load(channel, more: true),
          child: Text(failed ? '加载更多失败，点击重试' : '加载更多'),
        ),
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

/// 空态 / 未登录 / 失败重试的占位视图。
///
/// [onRefresh] 非空时套一层 [RefreshIndicator]（下拉重试）；[onRetry] 非空时
/// 显示「重试」按钮。两者至少一个可用，避免出现无法恢复的空白页。
class _NoticePlaceholder extends StatelessWidget {
  const _NoticePlaceholder({
    required this.icon,
    required this.text,
    this.onRetry,
    this.onRefresh,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(text, textAlign: TextAlign.center),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ],
    );
    final refresh = onRefresh;
    if (refresh == null) return Center(child: body);
    return RefreshIndicator(
      onRefresh: refresh,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: constraints.maxHeight, child: Center(child: body)),
          ],
        ),
      ),
    );
  }
}
