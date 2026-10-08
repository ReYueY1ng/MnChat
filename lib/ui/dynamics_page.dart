import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../core/services/dynamics.dart';
import '../core/services/msg_box.dart' show MsgBoxEntry;
import '../state/providers.dart';
import 'mail_page.dart' show MailPage, MailSelection;
import 'publish_dynamics_page.dart';
import 'widgets/dynamics_card.dart';
import 'theme/app_tokens.dart';

/// 动态页 —— 瀑布流信息流（热门/关注/同城/官方/我的）。
///
/// 每个分类独立缓存：切换分类不清空其它分类已加载内容，
/// 返回时直接显示缓存并后台静默刷新。
class DynamicsPage extends ConsumerStatefulWidget {
  /// 只看某个玩家的动态（他人主页的「TA 的动态」浮层用）；
  /// null = 普通动态页（热门 / 关注 / 官方 / 我的 四个分类）。
  final int? authorUin;

  /// 展示在标题里的昵称（仅 [authorUin] 非空时有意义）。
  final String? authorName;

  const DynamicsPage({super.key, this.authorUin, this.authorName});

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

/// 动态大厅的一个分类标签。
class _HallTab {
  final String label;

  /// 内置分类的数据来源；服务端自定义分类为 null（拉列表时走 `get_posting_by_tag`）。
  final DynamicsFeedType? type;

  /// 服务端分类 id（自定义分类用）。
  final String? tag;

  const _HallTab(this.label, {this.type, this.tag});
}

class _DynamicsPageState extends ConsumerState<DynamicsPage> {
  DynamicsClient? _client;

  /// 当前 tab 下标（默认最左）。
  int _tab = 0;

  /// 请求序号：切 tab 后旧的慢响应不应覆盖新列表。
  int _reqSeq = 0;
  final ScrollController _scroll = ScrollController();

  // 内置分类：同城插在「关注」与「官方」之间，对齐游戏动态大厅的 tab
  // （dynamicsinfocard.lua tab_type：official=4, city=3）；「我的」是客户端自己的
  // 入口（`get_posting_list`）。
  static const List<_HallTab> _baseTabs = [
    _HallTab('热门', type: DynamicsFeedType.hot),
    _HallTab('关注', type: DynamicsFeedType.recommend),
    _HallTab('同城', type: DynamicsFeedType.city),
    _HallTab('官方', type: DynamicsFeedType.official),
  ];
  static const _HallTab _mineTab = _HallTab('我的', type: DynamicsFeedType.mine);

  /// 服务端下发的额外分类（`get_posting_tag_list`）。
  ///
  /// 服务器把 1/2/3/4（推荐/关注/同城/官方，`DynamicHallTabType`）也一起下发，
  /// 这四个已经在内置列表里，只追加其余的（`editable` 的服务端分类）。
  List<DynamicsTag> _extraTags = const [];

  /// 当前分类列表（服务端分类插在「我的」之前）。
  List<_HallTab> get _tabs => [
    ..._baseTabs,
    for (final t in _extraTags)
      _HallTab(t.title.isEmpty ? '分类${t.tagId}' : t.title, tag: '${t.tagId}'),
    _mineTab,
  ];

  /// 各分类的独立缓存（下标与 [_tabs] 对齐，按需增长）。
  final List<_TabCache> _caches = [];

  _TabCache _cacheFor(int i) {
    while (_caches.length <= i) {
      _caches.add(_TabCache());
    }
    return _caches[i];
  }

  void _init() {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) {
      setState(() {
        _cacheFor(0).error = '未登录';
        _cacheFor(0).loading = false;
      });
      return;
    }
    _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    unawaited(_loadTags());
    _load();
  }

  /// 拉服务端分类（`get_posting_tag_list`）。失败/为空则只用内置分类。
  Future<void> _loadTags() async {
    final client = _client;
    if (client == null) return;
    try {
      final tags = await client.fetchPostingTags();
      if (!mounted || tags.isEmpty) return;
      // 1..4 是内置的 推荐/关注/同城/官方，不重复添加。
      final extra = [
        for (final t in tags)
          if (t.tagId < 1 || t.tagId > 4) t,
      ];
      if (extra.isEmpty) return;
      setState(() => _extraTags = extra);
    } catch (_) {
      // 拉不到分类就用内置那几个（不阻断动态流）
    }
  }

  /// 只看某个玩家的动态时：固定用「我的」这个 act（`get_posting_list`），
  /// 只是把 `op_uin` 换成对方 —— 服务端同一个接口既能查自己也能查别人。
  bool get _singleAuthor => widget.authorUin != null;

  /// 当前分类（单作者模式固定用「我的」）。
  _HallTab get _currentTab {
    final tabs = _tabs;
    if (_tab < 0 || _tab >= tabs.length) return _mineTab;
    return _singleAuthor ? _mineTab : tabs[_tab];
  }

  _TabCache get _cache => _cacheFor(_singleAuthor ? 0 : _tab);

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

  /// 加载当前 tab（首次/下拉刷新）。
  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final tab = _currentTab;
    final cache = _cache;
    final seq = ++_reqSeq;
    setState(() {
      cache.loading = true;
      cache.error = null;
    });
    try {
      final result = await client.pullPostings(
        tab.type ?? DynamicsFeedType.mine,
        tag: tab.tag,
        opUin: widget.authorUin,
      );
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
    final tab = _currentTab;
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
      final result = await client.pullPostings(
        tab.type ?? DynamicsFeedType.mine,
        tag: tab.tag,
        ct: cache.nextCt,
        opUin: widget.authorUin,
      );
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
    if (!_cacheFor(i).loadedOnce &&
        _cacheFor(i).error == null &&
        _client != null) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    return DefaultTabController(
      length: tabs.length,
      initialIndex: _tab.clamp(0, tabs.length - 1),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _singleAuthor
                ? '${widget.authorName ?? widget.authorUin} 的动态'
                : '动态',
          ),
          actions: [
            IconButton(
              tooltip: '动态通知',
              icon: const Icon(Icons.notifications_outlined),
              // 动态通知统一进消息中心：顶部"动态互动"入口
              //（post_rep/post_prize/post_at + fans_change 同源）。
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MailPage(
                    focus: MailSelection.entry(MsgBoxEntry.dynamics),
                  ),
                ),
              ),
            ),
            if (!_singleAuthor)
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
                  final i = _tabs.indexWhere(
                    (t) => t.type == DynamicsFeedType.mine,
                  );
                  if (i >= 0) {
                    _cacheFor(i).loadedOnce = false;
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
          bottom: _singleAuthor
              ? null
              : TabBar(
                  onTap: _switchTab,
                  tabs: [for (final t in tabs) Tab(text: t.label)],
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
            const SizedBox(height: AppSpacing.md),
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
                padding: const EdgeInsets.all(AppSpacing.sm),
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
