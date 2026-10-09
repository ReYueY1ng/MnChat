/// 话题页 —— 热门 / 全部话题列表，以及单个话题下的动态流。
///
/// 对齐反编译：
///   - 话题列表 `dynamics_frame_topic` + `dynamicsdatamanager.lua:3750` PullTopicList
///     （`get_topic_list` / `get_official_topic_list` / `get_follow_topic_list`）；
///   - 热门话题 `dynamicsdatamanager.lua:4781` ReqGetHotTopic（`get_hot_topic2`）；
///   - 话题动态流 `dynamicsdatamanager.lua:2129` GetPostingByTag（`get_posting_by_tag`，
///     `tag` 即话题 id）。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/dynamics_card.dart';

/// 话题页。[topicId] 为空 → 话题列表页；非空 → 该话题下的动态流。
class DynamicsTopicPage extends ConsumerStatefulWidget {
  /// 话题 id（`null` = 列表模式）。真实形态是字符串，如 `o:21` / `u:<uin>:<ct>`。
  final String? topicId;

  /// 话题标题（动态流标题栏展示）。
  final String? topicTitle;

  const DynamicsTopicPage({super.key, this.topicId, this.topicTitle});

  @override
  ConsumerState<DynamicsTopicPage> createState() => _DynamicsTopicPageState();
}

class _DynamicsTopicPageState extends ConsumerState<DynamicsTopicPage> {
  DynamicsClient? _client;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(chatServiceProvider).auth;
    if (auth != null) {
      _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    }
  }

  bool get _isFeed => widget.topicId != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFeed
            ? '#${widget.topicTitle ?? widget.topicId}'
            : '话题'),
      ),
      body: _client == null
          ? const Center(child: Text('未登录'))
          : (_isFeed
              ? _TopicFeed(client: _client!, topicId: widget.topicId!)
              : _TopicList(client: _client!)),
    );
  }
}

/// 话题列表：热门 / 全部 两个分栏。
class _TopicList extends StatefulWidget {
  final DynamicsClient client;

  const _TopicList({required this.client});

  @override
  State<_TopicList> createState() => _TopicListState();
}

class _TopicListState extends State<_TopicList> {
  List<DynamicsTopic> _official = const [];
  List<DynamicsTopic> _all = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 官方话题 + 全部话题：实测两者都是 `data: [...]` 的普通话题数组。
      // （get_hot_topic2 返回的是「话题→其动态」的分组结构，不是话题列表，
      // 故这里不用它做列表源。）
      final official = await widget.client.fetchOfficialTopicList();
      final all = await widget.client.fetchTopicList();
      if (!mounted) return;
      setState(() {
        _official = official;
        _all = all;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(DynamicsTopic t) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DynamicsTopicPage(
          topicId: t.topicId,
          topicTitle: t.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
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
    final items = <DynamicsTopic>[..._official, ..._all];
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            Center(child: Text('暂无话题，下拉刷新')),
          ],
        ),
      );
    }
    // 去重（官方与全部可能重叠），保持官方在前。
    final seen = <String>{};
    final merged = <_TopicEntry>[];
    for (final t in _official) {
      if (seen.add(t.topicId)) merged.add(_TopicEntry(t, official: true));
    }
    for (final t in _all) {
      if (seen.add(t.topicId)) merged.add(_TopicEntry(t, official: false));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: merged.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final e = merged[i];
          return ListTile(
            leading: Icon(e.official ? Icons.verified_outlined : Icons.tag),
            title: Text('#${e.topic.title}'),
            subtitle: Text('话题 ${e.topic.topicId}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(e.topic),
          );
        },
      ),
    );
  }
}

/// 列表条目（标记是否官方话题）。
class _TopicEntry {
  final DynamicsTopic topic;
  final bool official;

  const _TopicEntry(this.topic, {required this.official});
}

/// 单个话题下的动态流（`get_posting_by_tag`）。
class _TopicFeed extends ConsumerStatefulWidget {
  final DynamicsClient client;
  final String topicId;

  const _TopicFeed({required this.client, required this.topicId});

  @override
  ConsumerState<_TopicFeed> createState() => _TopicFeedState();
}

class _TopicFeedState extends ConsumerState<_TopicFeed> {
  final List<DynamicsPost> _posts = [];
  final ScrollController _scroll = ScrollController();
  int _nextCt = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // tag 非空时 pullPostings 走 `get_posting_by_tag`，type 不参与请求。
      final r = await widget.client.pullPostings(
        DynamicsFeedType.hot,
        tag: widget.topicId,
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(r.posts);
        _nextCt = r.nextCt;
      });
      unawaited(_enrichAvatars());
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 补作者头像展示（角色头像本体 / 头像框）：与动态大厅同一条规则
  /// （见 [enrichPostAvatars]）—— 话题流里的卡片同样要显示角色头像。
  Future<void> _enrichAvatars() async {
    final next = await enrichPostAvatars(ref, _posts);
    if (!mounted || identical(next, _posts)) return;
    setState(() {
      _posts
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _nextCt == 0) return;
    setState(() => _loadingMore = true);
    try {
      final r = await widget.client.pullPostings(
        DynamicsFeedType.hot,
        tag: widget.topicId,
        ct: _nextCt,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(r.posts);
        _nextCt = r.nextCt;
      });
      unawaited(_enrichAvatars());
    } catch (_) {
      // 加载更多失败：保留已加载内容。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
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
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            Center(child: Text('该话题暂无动态，下拉刷新')),
          ],
        ),
      );
    }
    final myUin = ref.read(myUinProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
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
            itemCount: _posts.length,
            itemBuilder: (context, i) => DynamicsCard(
              post: _posts[i],
              isMine: _posts[i].uin == myUin,
            ),
          ),
        );
      },
    );
  }
}
