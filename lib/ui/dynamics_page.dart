import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'dynamics_notice_page.dart';
import 'publish_dynamics_page.dart';
import 'widgets/dynamics_card.dart';

/// 动态页 —— 瀑布流信息流（热门/关注/官方/我的）。
///
/// 每个分类独立缓存：切换分类不清空其它分类已加载内容，
/// 返回时直接显示缓存并后台静默刷新。
class DynamicsPage extends ConsumerStatefulWidget {
  const DynamicsPage({super.key});

  @override
  ConsumerState<DynamicsPage> createState() => _DynamicsPageState();
}

/// 单个分类的数据缓存。
class _TabCache {
  List<DynamicsPost> posts = [];
  int nextCt = 0;
  String? error;
  bool loading = false;
  bool loadedOnce = false;
  bool loadingMore = false;
}

class _DynamicsPageState extends ConsumerState<DynamicsPage> {
  DynamicsClient? _client;

  /// 当前 tab：0 热门 / 1 关注 / 2 官方 / 3 我的。默认热门（最左）。
  int _tab = 0;
  final List<_TabCache> _caches =
      List.generate(_feedTypes.length, (_) => _TabCache());

  /// 请求序号：切 tab 后旧的慢响应不应覆盖新列表。
  int _reqSeq = 0;
  final ScrollController _scroll = ScrollController();

  static const _feedTypes = [DynamicsFeedType.hot, DynamicsFeedType.recommend, DynamicsFeedType.official, DynamicsFeedType.mine];
  static const _feedLabels = ['热门', '关注', '官方', '我的'];

  _TabCache get _cache => _caches[_tab];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 主壳（IndexedStack）会在后台自动登录完成前就构建本页：
    // 启动时 auth 可能为 null（显示"未登录"），必须监听登录态，
    // 一旦登录成功立即初始化并拉取，否则永远停在"未登录"。
    // 注意：initState 中必须用 listenManual（ref.listen 仅限 build）。
    ref.listenManual<AuthState>(authProvider, (prev, next) {
      if (next.isLoggedIn && _client == null && mounted) _init();
    });
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _init() {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) {
      setState(() {
        _cache.error = '未登录';
        _cache.loading = false;
      });
      return;
    }
    _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    _load();
  }

  /// 加载当前 tab（首次/下拉刷新）。
  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final cache = _cache;
    final seq = ++_reqSeq;
    setState(() {
      cache.loading = true;
      cache.error = null;
    });
    try {
      final result = await client.pullPostings(_feedTypes[_tab]);
      if (!mounted || seq != _reqSeq) return; // 已切 tab，丢弃旧响应
      setState(() {
        cache.posts = result.posts;
        cache.nextCt = result.nextCt;
        cache.loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || seq != _reqSeq) return;
      setState(() => cache.error = '加载失败: $e');
    } finally {
      if (mounted && seq == _reqSeq) {
        setState(() => cache.loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    final client = _client;
    final cache = _cache;
    if (client == null ||
        cache.loadingMore ||
        cache.loading ||
        cache.nextCt == 0 ||
        !cache.loadedOnce) {
      return;
    }
    final seq = _reqSeq;
    setState(() => cache.loadingMore = true);
    try {
      final result =
          await client.pullPostings(_feedTypes[_tab], ct: cache.nextCt);
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        cache.posts = [...cache.posts, ...result.posts];
        cache.nextCt = result.nextCt;
      });
    } catch (_) {
      // 忽略加载更多失败
    } finally {
      if (mounted && seq == _reqSeq) {
        setState(() => cache.loadingMore = false);
      }
    }
  }

  void _switchTab(int i) {
    if (i == _tab) return;
    setState(() {
      _tab = i;
      _scroll.jumpTo(0); // 回顶部（各分类独立列表）
    });
    // 保留其它分类内容：仅当此分类从没加载过时才拉取
    if (!_caches[i].loadedOnce && _caches[i].error == null && _client != null) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _feedTypes.length,
      initialIndex: 0, // 默认"热门"（最左）
      child: Scaffold(
        appBar: AppBar(
          title: const Text('动态'),
          actions: [
            IconButton(
              tooltip: '动态通知',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DynamicsNoticePage()),
              ),
            ),
            IconButton(
              tooltip: '发布动态',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const PublishDynamicsPage(),
                  ),
                );
                // 发布成功 → 刷新"我的"分类缓存
                if (ok == true && mounted) {
                  final i = _feedLabels.indexOf('我的');
                  if (i >= 0) {
                    _caches[i].loadedOnce = false;
                    _switchTab(i);
                  }
                }
              },
            ),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _init,
            ),
          ],
          bottom: TabBar(
            onTap: _switchTab,
            tabs: [for (final l in _feedLabels) Tab(text: l)],
          ),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    final cache = _cache;
    // 首次加载（该 tab 还没有内容）→ 显示转圈
    if (!cache.loadedOnce && cache.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cache.error != null && cache.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${cache.error}', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    // 有缓存但正在后台刷新（下拉之外的静默刷新）→ 顶部细条
    if (cache.posts.isEmpty && !cache.loading) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            Center(child: Text('暂无动态，下拉刷新')),
          ],
        ),
      );
    }
    final myUin = ref.read(myUinProvider);
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            // 竖屏/窄 → 单列；横屏/宽 → 双列瀑布流
            final wide = constraints.maxWidth >= 700;
            return RefreshIndicator(
              onRefresh: _load,
              child: MasonryGridView.count(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                crossAxisCount: wide ? 2 : 1,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                padding: const EdgeInsets.all(8),
                itemCount: cache.posts.length,
                itemBuilder: (context, i) => DynamicsCard(
                  post: cache.posts[i],
                  isMine: cache.posts[i].uin == myUin,
                ),
              ),
            );
          }),
        ),
        if (cache.loading && cache.loadedOnce)
          const LinearProgressIndicator(minHeight: 2),
        if (cache.loadingMore) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}
