part of 'mail_page.dart';

class _MailPageState extends ConsumerState<MailPage> {
  late MailSelection _selected;

  /// msgcenter 频道消息（channel → items）。
  final Map<int, List<MsgItem>> _items = {};
  final Map<int, bool> _loading = {};
  final Map<int, String?> _errors = {};

  /// msg_box 频道消息（channel 名 → items）。
  final Map<String, List<MsgBoxMessage>> _boxItems = {};
  final Map<String, bool> _boxLoading = {};
  final Map<String, String?> _boxErrors = {};
  final Map<String, int> _boxUnread = {};
  final Map<int, ChannelSummary> _summaries = {};
  final Map<int, PlayerProfile> _profiles = {};

  /// 作品互动卡片的作品名：owid → 名称（`/miniw/map` `get_map_list_info`）。
  final Map<String, String> _mapNames = {};

  bool _started = false;

  /// 互动入口的类型筛选（右栏「全部 ▾」）；切换入口 / 分类时重置为「全部」。
  String _typeFilter = '全部';

  /// 已在本页关注过的粉丝 uin（按钮置为「已关注」）。
  final Set<int> _followed = <int>{};

  @override
  void initState() {
    super.initState();
    _selected =
        widget.focus ?? const MailSelection.entry(MsgBoxEntry.dynamics);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _ensureLoaded(_selected);
    unawaited(_loadSummaries());
    unawaited(_loadLeftSummaries());
  }

  // ── 客户端 ────────────────────────────────────────────────────────────

  MessageCenterClient? get _center => ref.read(messageCenterClientProvider);
  MsgBoxClient? get _box => ref.read(msgBoxClientProvider);
  MapInfoClient? get _mapInfoClient => ref.read(mapInfoClientProvider);
  DynamicsClient? get _dynamics => ref.read(dynamicsClientProvider);
  ProfileClient? get _profileClient => ref.read(profileClientProvider);

  // ── 加载 ──────────────────────────────────────────────────────────────

  void _ensureLoaded(MailSelection sel) {
    final ch = sel.channel;
    if (ch != null) {
      if (ch == MsgChannel.activityAssistant) {
        unawaited(_loadBoxChannel(MsgBoxChannel.sys));
      } else if (_items[ch] == null) {
        unawaited(_loadChannel(ch));
      }
      return;
    }
    unawaited(_loadEntry(sel.entry!));
  }

  Future<void> _loadEntry(MsgBoxEntry entry) =>
      Future.wait([for (final c in entry.channels) _loadBoxChannel(c)]);

  /// 拉取 msgcenter 频道：消息流（新增 id）+ 详情。
  Future<void> _loadChannel(int channel) async {
    if (_loading[channel] == true) return;
    final client = _center;
    if (client == null) {
      if (mounted) setState(() => _errors[channel] = '未登录');
      return;
    }
    setState(() {
      _loading[channel] = true;
      _errors[channel] = null;
    });
    try {
      final (flow, _) = await client.fetchMsgFlow(channel);
      final list = <MsgItem>[];
      if (flow.isNotEmpty) {
        final details = await client.fetchMsgByIDs(
          channel,
          flow.map((e) => e.id).toList(),
        );
        for (final e in flow) {
          final d = details[e.id];
          if (d != null) list.add(d);
        }
      }
      if (!mounted) return;
      // 新→旧展示（flowlist 顺序不保证；左列摘要/详情栏都取最新在前）。
      list.sort((a, b) => b.createTime.compareTo(a.createTime));
      setState(() => _items[channel] = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors[channel] = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading[channel] = false);
    }
  }

  /// 拉取 msg_box 频道通知列表。
  Future<void> _loadBoxChannel(String channel) async {
    if (_boxLoading[channel] == true) return;
    final client = _box;
    if (client == null) {
      if (mounted) setState(() => _boxErrors[channel] = '未登录');
      return;
    }
    setState(() {
      _boxLoading[channel] = true;
      _boxErrors[channel] = null;
    });
    try {
      final page = await client.getChannelMsgList(channel);
      if (!mounted) return;
      setState(() => _boxItems[channel] = page.items);
      unawaited(_enrichProfiles(page.items.map((m) => m.uin)));
      if (channel == MsgBoxChannel.mapInteract) {
        unawaited(_enrichMapNames(page.items));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _boxErrors[channel] = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _boxLoading[channel] = false);
    }
  }

  /// 左列摘要：各 msgcenter 频道首屏（含最新一条，用于行内时间/正文）
  /// + 动态助手（msg_box post_sys）。
  Future<void> _loadLeftSummaries() async {
    for (final ch in MsgChannel.mailChannels) {
      unawaited(_loadChannel(ch));
    }
    unawaited(_loadBoxChannel(MsgBoxChannel.sys));
  }

  /// 频道计数（fetch_channels_info）+ 互动入口红点（get_channel_msg_list_x）。
  Future<void> _loadSummaries() async {
    final center = _center;
    if (center != null) {
      try {
        final map = await center.fetchChannelsInfo(MsgChannel.mailChannels);
        if (mounted && map.isNotEmpty) {
          setState(() => _summaries
            ..clear()
            ..addAll(map));
        }
      } catch (_) {
        // 计数失败：未读角标退回已加载列表统计
      }
    }
    final box = _box;
    if (box != null) {
      final channels = <String>{
        for (final e in MsgBoxEntry.values) ...e.channels,
        MsgBoxChannel.sys,
      }.toList();
      try {
        final map = await box.getChannelMsgListX(channels);
        if (mounted && map.isNotEmpty) {
          setState(() => _boxUnread
            ..clear()
            ..addAll(map));
        }
      } catch (_) {
        // 红点失败：角标退回已加载列表统计
      }
    }
  }

  /// 互动通知头像补全（角色头 / 头像框本地资源）。
  Future<void> _enrichProfiles(Iterable<int> uins) async {
    final client = _profileClient;
    if (client == null) return;
    final pending = <int>{
      for (final u in uins)
        if (u > 0 && !_profiles.containsKey(u)) u,
    };
    if (pending.isEmpty) return;
    try {
      final list = await client.getProfileBatch3(pending.toList());
      if (!mounted || list.isEmpty) return;
      setState(() {
        for (final p in list) {
          _profiles[p.uin] = p;
        }
      });
    } catch (_) {
      // 资料拉取失败：头像退回迷你号 + 首字占位
    }
  }

  /// 作品互动卡片的作品名补全（`data.map_id` → `/miniw/map` 查名）。
  /// 失败/查不到就不显示作品名（卡片只留行动作），不阻断列表。
  Future<void> _enrichMapNames(List<MsgBoxMessage> items) async {
    final client = _mapInfoClient;
    if (client == null) return;
    final pending = <String>{
      for (final m in items)
        if (m.msgType.startsWith('map_'))
          if ('${m.data['map_id'] ?? ''}'.isNotEmpty)
            if (!_mapNames.containsKey('${m.data['map_id']}'))
              '${m.data['map_id']}',
    };
    if (pending.isEmpty) return;
    try {
      final names = await client.fetchMapNames(pending.toList());
      if (!mounted || names.isEmpty) return;
      setState(() => _mapNames.addAll(names));
    } catch (_) {
      // 查名失败：卡片不影响列表展示
    }
  }

  Future<void> _refreshSelection() async {    final ch = _selected.channel;
    if (ch != null && ch != MsgChannel.activityAssistant) {
      await _loadChannel(ch);
    } else if (ch == MsgChannel.activityAssistant) {
      await _loadBoxChannel(MsgBoxChannel.sys);
    } else {
      for (final c in _selected.entry!.channels) {
        await _loadBoxChannel(c);
      }
    }
    await _loadSummaries();
  }

  // ── 已读 / 删除 ───────────────────────────────────────────────────────
  //
  // 降级说明：官方 `SetChannelMsgAllRead` / `GetChannelAllReadIds` 基于本地
  // 缓存的全量 id 列表；本客户端只持有已加载的首屏条目，因此
  // `一键已读` / `删除已读` 只作用于**当前已加载**的未读 / 已读条目
  //（服务端仍按所传 id 精确处理，不会误伤）。

  /// 一键已读：msgcenter 频道 → read_message；msg_box → read_channel_msg。
  Future<void> _readAll() async {
    final ch = _selected.channel;
    if (ch != null && ch != MsgChannel.activityAssistant) {
      final list = _items[ch] ?? const <MsgItem>[];
      final unread = [for (final e in list) if (e.unread) e.id];
      if (unread.isEmpty) return;
      final client = _center;
      if (client == null) return;
      final ok = await client.readMessages(ch, unread);
      if (!mounted) return;
      if (ok) {
        setState(() => _items[ch] = [
              for (final e in list) e.copyWith(readState: 1),
            ]);
      } else {
        _toast('标记已读失败');
      }
      return;
    }
    final channels = ch == MsgChannel.activityAssistant
        ? const [MsgBoxChannel.sys]
        : _selected.entry!.channels;
    await _readBoxChannels(channels);
  }

  Future<void> _readBoxChannels(List<String> channels) async {
    final client = _box;
    if (client == null) return;
    var failed = false;
    for (final c in channels) {
      final list = _boxItems[c] ?? const <MsgBoxMessage>[];
      final unread = [for (final m in list) if (m.unread) m.msgId];
      if (unread.isEmpty) continue;
      final ok = await client.readChannelMsg(c, unread);
      if (!ok) {
        failed = true;
        continue;
      }
      if (!mounted) return;
      setState(() => _boxItems[c] = [
            for (final m in list) m.copyWith(status: 1),
          ]);
    }
    if (failed) _toast('标记已读失败');
  }

  /// 删除已读：msgcenter 频道 → delete_message；msg_box → del_channel_msg。
  Future<void> _deleteRead() async {
    final ch = _selected.channel;
    if (ch != null && ch != MsgChannel.activityAssistant) {
      final list = _items[ch] ?? const <MsgItem>[];
      final read = [for (final e in list) if (!e.unread) e.id];
      if (read.isEmpty) return;
      final client = _center;
      if (client == null) return;
      final ok = await client.deleteMessages(ch, read);
      if (!mounted) return;
      if (ok) {
        setState(() => _items[ch] = [
              for (final e in list)
                if (e.unread) e,
            ]);
      } else {
        _toast('删除失败');
      }
      return;
    }
    final channels = ch == MsgChannel.activityAssistant
        ? const [MsgBoxChannel.sys]
        : _selected.entry!.channels;
    await _deleteBoxRead(channels);
  }

  Future<void> _deleteBoxRead(List<String> channels) async {
    final client = _box;
    if (client == null) return;
    var failed = false;
    for (final c in channels) {
      final list = _boxItems[c] ?? const <MsgBoxMessage>[];
      final read = [for (final m in list) if (!m.unread) m.msgId];
      if (read.isEmpty) continue;
      final ok = await client.delChannelMsg(c, read);
      if (!ok) {
        failed = true;
        continue;
      }
      if (!mounted) return;
      setState(() => _boxItems[c] = [
            for (final m in list)
              if (m.unread) m,
          ]);
    }
    if (failed) _toast('删除失败');
  }

  Future<void> _takeAttachment(int channel, MsgItem item) async {
    final client = _center;
    if (client == null) return;
    final ok = await client.takeAttachments(channel, [item.id]);
    if (!mounted) return;
    if (ok.contains(item.id)) {
      final list = _items[channel];
      if (list == null) return;
      final i = list.indexWhere((e) => e.id == item.id);
      if (i < 0) return;
      setState(() => _items[channel] = [
            ...list.sublist(0, i),
            list[i].copyWith(attachmentTaken: true),
            ...list.sublist(i + 1),
          ]);
    }
  }

  Future<void> _deleteItem(int channel, MsgItem item) async {
    final client = _center;
    if (client == null) return;
    final ok = await client.deleteMessages(channel, [item.id]);
    if (!mounted) return;
    if (ok) {
      setState(() => _items[channel]?.removeWhere((e) => e.id == item.id));
    } else {
      _toast('删除失败');
    }
  }

  // ── 跳转 ──────────────────────────────────────────────────────────────

  Future<void> _openMailDetail(int channel, MsgItem item) async {
    if (item.unread) {
      final client = _center;
      if (client != null) {
        final ok = await client.readMessages(channel, [item.id]);
        if (!mounted) return;
        if (ok) {
          final list = _items[channel];
          if (list != null) {
            final i = list.indexWhere((e) => e.id == item.id);
            if (i >= 0) {
              setState(() => _items[channel] = [
                    ...list.sublist(0, i),
                    list[i].copyWith(readState: 1),
                    ...list.sublist(i + 1),
                  ]);
            }
          }
        }
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MailDetailPage(
          item: item,
          onTake: item.attach.isNotEmpty
              ? () => _takeAttachment(channel, item)
              : null,
          onDelete: () => _deleteItem(channel, item),
        ),
      ),
    );
  }

  Future<void> _openDynamics(String pid) async {
    final client = _dynamics;
    if (client == null || pid.isEmpty) return;
    try {
      final post = await client.fetchPost(pid);
      if (!mounted) return;
      if (post == null) {
        _toast('动态不存在或已删除');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DynamicsDetailPage(post: post),
        ),
      );
    } catch (e) {
      _toast('动态加载失败: $e');
    }
  }

  /// 关注粉丝（`attention_friend`）；成功后按钮置为「已关注」。
  Future<void> _follow(int uin) async {
    try {
      await ref.read(chatServiceProvider).followPlayer(uin, follow: true);
    } catch (_) {
      _toast('关注失败');
      return;
    }
    if (!mounted) return;
    setState(() => _followed.add(uin));
    _toast('已关注');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _select(MailSelection sel) {
    setState(() {
      _selected = sel;
      // 类型筛选属于入口维度：切走一律回到「全部」。
      _typeFilter = '全部';
    });
    _ensureLoaded(sel);
  }

  void _pushDetail(MailSelection sel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MailPage(focus: sel)),
    );
  }

  // ── 数据视图 ──────────────────────────────────────────────────────────

  List<MsgBoxMessage> _entryItems(MsgBoxEntry entry) {
    final all = <MsgBoxMessage>[];
    for (final c in entry.channels) {
      all.addAll(_boxItems[c] ?? const <MsgBoxMessage>[]);
    }
    all.sort((a, b) => b.time.compareTo(a.time));
    return all;
  }

  /// 详情栏的消息序列（msgcenter 或 msg_box 二选一）。
  List<MsgBoxMessage> _paneBoxItems(MailSelection sel) {
    final ch = sel.channel;
    if (ch == MsgChannel.activityAssistant) {
      return _boxItems[MsgBoxChannel.sys] ?? const <MsgBoxMessage>[];
    }
    if (sel.entry != null) {
      final all = _entryItems(sel.entry!);
      if (_typeFilter == '全部') return all;
      return [
        for (final m in all)
          if (m.filterLabel == _typeFilter) m,
      ];
    }
    return const <MsgBoxMessage>[];
  }

  /// 互动入口的类型筛选项（词表在 [MsgBoxEntry.filters]，出处
  /// `mainchatinteractivemsg.lua:64-79`）；非互动入口（邮件 / 系统频道）
  /// 无类型维度 → null。
  List<String>? _typeFilterOptions(MailSelection sel) => sel.entry?.filters;

  List<MsgItem> _paneMailItems(MailSelection sel) {
    final ch = sel.channel;
    if (ch == null || ch == MsgChannel.activityAssistant) {
      return const <MsgItem>[];
    }
    return _items[ch] ?? const <MsgItem>[];
  }

  int _paneUnread(MailSelection sel) {
    final box = _paneBoxItems(sel);
    if (box.isNotEmpty) return box.where((m) => m.unread).length;
    return _paneMailItems(sel).where((e) => e.unread).length;
  }

  int _paneRead(MailSelection sel) {
    final box = _paneBoxItems(sel);
    if (box.isNotEmpty) return box.where((m) => !m.unread).length;
    return _paneMailItems(sel).where((e) => !e.unread).length;
  }

  bool _paneLoading(MailSelection sel) {
    final ch = sel.channel;
    if (ch != null && ch != MsgChannel.activityAssistant) {
      return _loading[ch] == true;
    }
    final channels = ch == MsgChannel.activityAssistant
        ? const [MsgBoxChannel.sys]
        : sel.entry!.channels;
    return channels.any((c) => _boxLoading[c] == true);
  }

  String? _paneError(MailSelection sel) {
    final ch = sel.channel;
    if (ch != null && ch != MsgChannel.activityAssistant) return _errors[ch];
    final channels = ch == MsgChannel.activityAssistant
        ? const [MsgBoxChannel.sys]
        : sel.entry!.channels;
    for (final c in channels) {
      final e = _boxErrors[c];
      if (e != null) return e;
    }
    return null;
  }

  int _channelUnread(int channel) {
    if (channel == MsgChannel.activityAssistant) {
      final loaded = _boxItems[MsgBoxChannel.sys];
      if (loaded != null) return loaded.where((m) => m.unread).length;
      return _boxUnread[MsgBoxChannel.sys] ?? 0;
    }
    final loaded = _items[channel];
    if (loaded != null) return loaded.where((e) => e.unread).length;
    return _summaries[channel]?.unread ?? 0;
  }

  int _entryUnread(MsgBoxEntry entry) {
    var n = 0;
    for (final c in entry.channels) {
      final loaded = _boxItems[c];
      if (loaded != null) {
        n += loaded.where((m) => m.unread).length;
      } else {
        n += _boxUnread[c] ?? 0;
      }
    }
    return n;
  }

  /// 左列一行摘要（最新一条的标题 + 时间）。
  ///
  /// 摘要取的是**标题**而非正文（对齐 `MainChatCtrl:SystemItemRenderer`，
  /// mainchatctrl.lua:3204-3236：`tfContent` = GetMailDesc 的 strTitle）；
  /// 动态助手（频道 0）的标题由活动类型决定（mainchatsystemmsg.lua:195-206）。
  ({String text, int time}) _channelLine(int channel) {
    if (channel == MsgChannel.activityAssistant) {
      final list = _boxItems[MsgBoxChannel.sys] ?? const <MsgBoxMessage>[];
      final m = _newestBox(list);
      if (m == null) return (text: '', time: 0);
      return (text: m.actionLabel, time: m.time);
    }
    final item = _newestMail(_items[channel] ?? const <MsgItem>[]);
    if (item == null) return (text: '', time: 0);
    return (text: item.title, time: item.createTime);
  }

  /// 最新一条（按时间取最大；flowlist 顺序不保证新旧）。
  static MsgItem? _newestMail(List<MsgItem> list) {
    MsgItem? best;
    for (final e in list) {
      if (best == null || e.createTime > best.createTime) best = e;
    }
    return best;
  }

  static MsgBoxMessage? _newestBox(List<MsgBoxMessage> list) {
    MsgBoxMessage? best;
    for (final e in list) {
      if (best == null || e.time > best.time) best = e;
    }
    return best;
  }

  String _selectionTitle(MailSelection sel) =>
      sel.entry?.label ?? MsgChannel.name(sel.channel!);

  // ── 构建 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kMailCentreWideWidth;
        // 窄屏下钻实例：仅详情 + 返回。
        if (widget.focus != null && !wide) {
          final options = _typeFilterOptions(_selected);
          return Scaffold(
            appBar: AppBar(
              title: Text(_selectionTitle(_selected)),
              // 窄屏下钻页没有栏头，把「全部 ▾」搬到 AppBar（宽屏在栏头里）。
              actions: [
                if (options != null)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: Center(
                      child: _TypeFilterPill(
                        options: options,
                        value: _typeFilter,
                        onChanged: (v) => setState(() => _typeFilter = v),
                      ),
                    ),
                  ),
              ],
            ),
            body: _buildPane(_selected, wide: false),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('消息中心'),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _refreshSelection,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          // 宽屏：左栏 = 三个圆入口 + 分类列表；右栏 = 详情（卡片流）。
          // 窄屏：只有左栏，点入口 / 分类 push 详情页。
          body: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 340,
                      child: _buildLeftColumn(pushOnTap: false),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildPane(_selected, wide: true)),
                  ],
                )
              : _buildLeftColumn(pushOnTap: true),
        );
      },
    );
  }

  /// 左栏：顶部 3 圆入口 + 分类列表。
  Widget _buildLeftColumn({required bool pushOnTap}) {
    return Column(
      children: [
        _buildTopEntries(pushOnTap: pushOnTap),
        const Divider(height: 1),
        Expanded(child: _buildCategoryList(pushOnTap: pushOnTap)),
      ],
    );
  }

  /// 顶部 3 圆入口（动态互动 / 新增粉丝 / 作品互动）。
  ///
  /// 窄屏没有右栏，点入口必须 push 详情页 —— 否则只更新选中态而看不到内容。
  Widget _buildTopEntries({required bool pushOnTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          for (final e in MsgBoxEntry.values)
            Expanded(
              child: _TopEntryButton(
                entry: e,
                unread: _entryUnread(e),
                selected: _selected.entry == e,
                onTap: () {
                  final sel = MailSelection.entry(e);
                  if (pushOnTap) {
                    _pushDetail(sel);
                  } else {
                    _select(sel);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 左列 7 分类（彩色圆角图标 + 标题 / 时间 / 摘要 / 未读角标，卡片式行）。
  /// 左列分类的显示顺序 —— 对齐 `MainChatSystemMsg:UpdateSystemInfos` 的
  /// `table.sort`（mainchatsystemmsg.lua:226-244）：按该分类最新一条消息的
  /// 时间倒序；都没有消息时按未读数倒序，最后一个也不动。
  List<int> _orderedChannels() {
    const order = MsgChannel.categoryOrder;
    final times = {for (final c in order) c: _channelLine(c).time};
    final unread = {for (final c in order) c: _channelUnread(c)};
    final list = [...order];
    list.sort((a, b) {
      final ta = times[a] ?? 0;
      final tb = times[b] ?? 0;
      if (ta > 0 && tb > 0) return tb.compareTo(ta);
      if (ta > 0) return -1;
      if (tb > 0) return 1;
      return (unread[b] ?? 0).compareTo(unread[a] ?? 0);
    });
    return list;
  }

  Widget _buildCategoryList({required bool pushOnTap}) {
    final channels = _orderedChannels();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      itemCount: channels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, i) => _buildCategoryRow(channels[i], pushOnTap),
    );
  }

  Widget _buildCategoryRow(int channel, bool pushOnTap) {
    final theme = Theme.of(context);
    final style = _categoryStyle(theme, channel);
    final unread = _channelUnread(channel);
    final line = _channelLine(channel);
    final subtitle = line.text.isNotEmpty ? line.text : '暂无消息';
    final time = line.time > 0 ? fmtMailTimeShort(line.time) : '';
    final selected = _selected.channel == channel;
    // M3 选中态：secondaryContainer 铺底 + onSecondaryContainer 前景，无描边。
    final fg = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      borderRadius: AppRadius.inputR,
      child: InkWell(
        borderRadius: AppRadius.inputR,
        onTap: () {
          final sel = MailSelection.channel(channel);
          if (pushOnTap) {
            _pushDetail(sel);
          } else {
            _select(sel);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              _CategoryIcon(style: style),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            MsgChannel.name(channel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: selected ? fg : null,
                            ),
                          ),
                        ),
                        if (time.isNotEmpty)
                          Text(
                            time,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: selected
                                  ? fg
                                  : theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: selected
                                  ? fg
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (unread > 0)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: AppSpacing.sm,
                            ),
                            child: _UnreadBadge(count: unread),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 右侧详情栏（或窄屏下钻页的 body）。
  Widget _buildPane(MailSelection sel, {required bool wide}) {
    final mailItems = _paneMailItems(sel);
    final boxItems = _paneBoxItems(sel);
    final count = mailItems.length + boxItems.length;
    final loading = _paneLoading(sel);
    final error = _paneError(sel);

    Widget body;
    if (loading && count == 0) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && count == 0) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(error, textAlign: TextAlign.center),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: _refreshSelection,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    } else if (count == 0) {
      body = const Center(child: Text('暂无消息'));
    } else {
      body = RefreshIndicator(
        onRefresh: _refreshSelection,
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) {
            if (i < mailItems.length) {
              return _buildMailCard(sel.channel!, mailItems[i]);
            }
            return _buildBoxCard(boxItems[i - mailItems.length]);
          },
        ),
      );
    }

    return Column(
      children: [
        if (wide) _buildPaneHeader(sel),
        Expanded(child: body),
        const Divider(height: 1),
        _buildActionBar(sel),
      ],
    );
  }

  Widget _buildPaneHeader(MailSelection sel) {
    final theme = Theme.of(context);
    final options = _typeFilterOptions(sel);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectionTitle(sel),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (options != null)
            _TypeFilterPill(
              options: options,
              value: _typeFilter,
              onChanged: (v) => setState(() => _typeFilter = v),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar(MailSelection sel) {
    final canRead = _paneUnread(sel) > 0;
    final canDelete = _paneRead(sel) > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: canRead ? _readAll : null,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('一键已读'),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton.icon(
            onPressed: canDelete ? _deleteRead : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除已读'),
          ),
        ],
      ),
    );
  }

  /// 卡片外壳：圆角 + 细描边 + 点击水波（右栏列表项统一外观）。
  Widget _card({required Widget child, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.cardR,
      child: InkWell(
        borderRadius: AppRadius.cardR,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardR,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }

  /// 邮件 / 系统消息卡片：标题 + 时间 / 正文（+ 图片）/ 附件 /
  /// `来自迷你官方` + 详情（对齐截图）。
  Widget _buildMailCard(int channel, MsgItem item) {
    final theme = Theme.of(context);
    final unread = item.unread;
    final image = item.images.isNotEmpty ? item.images.first : null;
    return _card(
      onTap: () => _openMailDetail(channel, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  item.title.isNotEmpty ? item.title : '（无标题）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                fmtMailTime(item.createTime),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          if (item.content.isNotEmpty || image != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.content.isNotEmpty)
                  Expanded(
                    child: Text(
                      item.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                if (image != null) ...[
                  if (item.content.isNotEmpty)
                    const SizedBox(width: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: AppRadius.chipR,
                    child: Image(
                      image: CachedNetworkImageProvider(image),
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (item.attach.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.card_giftcard,
                  size: 16,
                  color: item.attachmentTaken
                      ? theme.colorScheme.outline
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    [
                      for (final a in item.attach)
                        '${a.name.isNotEmpty ? a.name : '物品 ${a.id}'}'
                            '${a.count > 0 ? ' ×${a.count}' : ''}',
                    ].join('、'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  item.attachmentTaken ? '已领取' : '待领取',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: item.attachmentTaken
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                item.senderName.isNotEmpty
                    ? '来自${item.senderName}'
                    : '来自迷你官方',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const Spacer(),
              _DetailButton(onPressed: () => _openMailDetail(channel, item)),
            ],
          ),
        ],
      ),
    );
  }

  /// 互动通知卡片：头像 / 昵称 + 时间 IP / 行动作 + 正文 / 缩略图 /
  /// 粉丝「关注」按钮（对齐截图）。
  Widget _buildBoxCard(MsgBoxMessage m) {
    final theme = Theme.of(context);
    final profile = _profiles[m.uin];
    final head = PlayerProfile.resolveRoleHeadFallback(
      headType: profile?.headType,
      headId: profile?.headId,
      skinId: profile?.headSkinId,
      model: profile?.headModel,
    );
    final name = profile?.nickname.isNotEmpty == true
        ? profile!.nickname
        : (m.nickname.isNotEmpty ? m.nickname : '${m.uin}');
    final isFan = m.channel == MsgBoxChannel.fans;
    // 摘要行 = 行动作（+ 作品名 / 被互动内容预览）；正文行 = 评论 / 回复正文。
    final preview = m.summaryParam(mapNames: _mapNames);
    final actionText = preview.isEmpty
        ? m.actionLabel
        : '${m.actionLabel}：$preview';
    // 正文：优先评论内容；动态助手（post_sys）没有评论时用标题兑底。
    final content = m.content.isNotEmpty ? m.content : m.title;
    final bodyText = content.isNotEmpty && content != preview ? content : '';
    final timeText = (m.time > 0 || m.location.isNotEmpty)
        ? fmtMsgTimeIp(m.time, m.location)
        : '';
    return _card(
      onTap: m.hasDetail ? () => _openDynamics(m.pid) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarView(
            name: name,
            avatarUrl: profile?.avatarUrl,
            frameId: profile?.headFrameId,
            headType: head?.type,
            headId: head?.id,
            radius: 18,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (timeText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Text(
                          timeText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
                if (actionText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 游戏卡片上「赞」是模板图标（控制器 c1），文案本身只是
                      // 半句（「了这条动态：…」）；这里用图标把那个动作补上。
                      if (m.isLikeStyle) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 1, right: 4),
                          child: Icon(
                            Icons.thumb_up,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          actionText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (bodyText.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    bodyText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (m.picUrl.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadius.chipR,
              child: Image(
                image: CachedNetworkImageProvider(m.picUrl),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (isFan && m.uin > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            _FollowButton(
              followed: _followed.contains(m.uin),
              onPressed: () => _follow(m.uin),
            ),
          ],
        ],
      ),
    );
  }
}
