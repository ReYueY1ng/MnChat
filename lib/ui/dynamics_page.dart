import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'widgets/dynamics_card.dart';

/// 动态页 —— 双列瀑布流信息流（好友/热门/官方）。
class DynamicsPage extends ConsumerStatefulWidget {
  const DynamicsPage({super.key});

  @override
  ConsumerState<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends ConsumerState<DynamicsPage> {
  DynamicsClient? _client;
  List<DynamicsPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _tab = 0;
  int _nextCt = 0;
  final ScrollController _scroll = ScrollController();

  static const _feedTypes = [DynamicsFeedType.recommend, DynamicsFeedType.hot, DynamicsFeedType.official, DynamicsFeedType.mine];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
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
        _loading = false;
        _error = '未登录';
      });
      return;
    }
    _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
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
      final result = await client.pullPostings(_feedTypes[_tab]);
      if (mounted) {
        setState(() {
          _posts = result.posts;
          _nextCt = result.nextCt;
        });
      }
    } catch (e) {
      _error = '加载失败: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final client = _client;
    if (client == null || _loadingMore || _loading || _nextCt == 0) return;
    setState(() => _loadingMore = true);
    try {
      final result = await client.pullPostings(_feedTypes[_tab], ct: _nextCt);
      if (mounted) {
        setState(() {
          _posts = [..._posts, ...result.posts];
          _nextCt = result.nextCt;
        });
      }
    } catch (_) {
      // 忽略加载更多失败
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _switchTab(int i) {
    if (i == _tab) return;
    setState(() {
      _tab = i;
      _nextCt = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _feedTypes.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('动态'),
          bottom: TabBar(
            onTap: _switchTab,
            tabs: const [Tab(text: '推荐'), Tab(text: '热门'), Tab(text: '官方'), Tab(text: '我的')],
          ),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text('$_error\n\n点击右上角刷新', textAlign: TextAlign.center),
      );
    }
    if (_posts.isEmpty) return const Center(child: Text('暂无动态'));
    final myUin = ref.read(myUinProvider);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: MasonryGridView.count(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              padding: const EdgeInsets.all(8),
              itemCount: _posts.length,
              itemBuilder: (context, i) => DynamicsCard(post: _posts[i], isMine: _posts[i].uin == myUin),
            ),
          ),
        ),
        if (_loadingMore) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}
