/// 消息中心 —— 对齐游戏内 MainChat 系统页（双栏 / 窄屏单栏下钻）。
///
/// 结构（参考游戏内截图）：
/// - 顶部 3 个圆入口：动态互动 / 新增粉丝 / 作品互动（`/miniw/msg_box`；
///   动态互动 = post_rep + post_prize + post_at 合并）；
/// - 左侧 7 分类：礼物消息(10005) / 官方邮件(1) / 创作者助手(20001) /
///   系统消息(20002) / 好友邮件(2) / 动态助手(0→msg_box post_sys) / 运营活动(20003)，
///   每行 = 彩色图标 + 标题 + 右侧时间 + 一行摘要 + 未读角标；
/// - 右侧详情：所选分类的消息列表（标题/正文/`详情`/时间）+ 底部
///   `一键已读` / `删除已读`；互动通知条目标题/正文/缩略图 + `N小时前 IP 省`。
///
/// 宽窄判定与 `home_shell` 会话双栏一致（内容宽 ≥760 双栏，否则单栏
/// push-on-tap）。互动通知头像复用 [AvatarView]（角色头 / 头像框走本地资源）。
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/dynamics.dart' show DynamicsClient;
import '../core/services/message_center.dart';
import '../core/services/msg_box.dart';
import '../core/services/profile.dart' show PlayerProfile, ProfileClient;
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart' show headFrameSlotSize, kAvatarListTileDensity;

/// 宽窄分界：内容宽 ≥760 双栏（对齐 home_shell 会话双栏阈值）。
const double kMailCentreWideWidth = 760;

/// 消息中心选中项：顶部互动入口 或 左列邮件/系统分类（二者互斥）。
class MailSelection {
  /// 顶部 3 入口之一；与 [channel] 互斥。
  final MsgBoxEntry? entry;

  /// `MsgChannel` 频道 id（含动态助手 [MsgChannel.activityAssistant]=0）。
  final int? channel;

  const MailSelection.entry(MsgBoxEntry e)
      : entry = e,
        channel = null;

  const MailSelection.channel(int c)
      : entry = null,
        channel = c;

  bool get isEntry => entry != null;

  @override
  bool operator ==(Object other) =>
      other is MailSelection && other.entry == entry && other.channel == channel;

  @override
  int get hashCode => Object.hash(entry, channel);
}

/// 消息中心主页面。
class MailPage extends ConsumerStatefulWidget {
  /// 打开时聚焦的分类/入口（动态通知 → 动态互动）。
  ///
  /// 窄屏（<[kMailCentreWideWidth]）下非空时直接渲染该分类的详情页（带返回），
  /// 用于列表页 push 下钻；宽屏则作为双栏右栏的初始选中。
  final MailSelection? focus;

  const MailPage({super.key, this.focus});

  @override
  ConsumerState<MailPage> createState() => _MailPageState();
}

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

  bool _started = false;

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

  Future<void> _refreshSelection() async {
    final ch = _selected.channel;
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _select(MailSelection sel) {
    setState(() => _selected = sel);
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
    if (sel.entry != null) return _entryItems(sel.entry!);
    return const <MsgBoxMessage>[];
  }

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

  /// 左列一行摘要（最新一条的正文/标题 + 时间）。
  ({String text, int time}) _channelLine(int channel) {
    if (channel == MsgChannel.activityAssistant) {
      final list = _boxItems[MsgBoxChannel.sys] ?? const <MsgBoxMessage>[];
      final m = _newestBox(list);
      if (m == null) return (text: '', time: 0);
      return (text: m.headline, time: m.time);
    }
    final item = _newestMail(_items[channel] ?? const <MsgItem>[]);
    if (item == null) return (text: '', time: 0);
    return (
      text: item.content.isNotEmpty ? item.content : item.title,
      time: item.createTime,
    );
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
          return Scaffold(
            appBar: AppBar(title: Text(_selectionTitle(_selected))),
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
          body: Column(
            children: [
              _buildTopEntries(),
              const Divider(height: 1),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 320,
                            child: _buildCategoryList(pushOnTap: false),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildPane(_selected, wide: true)),
                        ],
                      )
                    : _buildCategoryList(pushOnTap: true),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 顶部 3 圆入口（动态互动 / 新增粉丝 / 作品互动）。
  Widget _buildTopEntries() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
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
                onTap: () => _select(MailSelection.entry(e)),
              ),
            ),
        ],
      ),
    );
  }

  /// 左列 7 分类。
  Widget _buildCategoryList({required bool pushOnTap}) {
    final channels = MsgChannel.categoryOrder;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: channels.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) => _buildCategoryRow(channels[i], pushOnTap),
    );
  }

  Widget _buildCategoryRow(int channel, bool pushOnTap) {
    final theme = Theme.of(context);
    final style = _categoryStyle(theme, channel);
    final unread = _channelUnread(channel);
    final line = _channelLine(channel);
    final subtitle = line.text.isNotEmpty ? line.text : '暂无消息';
    final time = line.time > 0 ? fmtMsgTime(line.time) : '';
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: style.color.withValues(alpha: 0.14),
        child: Icon(style.icon, size: 20, color: style.color),
      ),
      title: Text(
        MsgChannel.name(channel),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (time.isNotEmpty)
            Text(
              time,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: _UnreadBadge(count: unread),
            ),
        ],
      ),
      selected: _selected.channel == channel,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.35,
      ),
      onTap: () {
        final sel = MailSelection.channel(channel);
        if (pushOnTap) {
          _pushDetail(sel);
        } else {
          _select(sel);
        }
      },
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
          itemCount: count,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i < mailItems.length) {
              return _buildMailItem(sel.channel!, mailItems[i]);
            }
            return _buildBoxItem(boxItems[i - mailItems.length]);
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectionTitle(sel),
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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

  /// 邮件/系统消息行：标题 / 正文 / 详情 / 时间。
  Widget _buildMailItem(int channel, MsgItem item) {
    final theme = Theme.of(context);
    final unread = item.unread;
    return ListTile(
      leading: Icon(
        unread ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
        color: unread ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(
        item.title.isNotEmpty ? item.title : '（无标题）',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: unread ? FontWeight.w600 : FontWeight.w400),
      ),
      subtitle: Text(
        item.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            fmtMsgTime(item.createTime),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          _DetailButton(onPressed: () => _openMailDetail(channel, item)),
        ],
      ),
      onTap: () => _openMailDetail(channel, item),
    );
  }

  /// 互动通知行：头像 / 行动作+正文 / 缩略图 / `N小时前 IP 省` / 详情。
  Widget _buildBoxItem(MsgBoxMessage m) {
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
    final body = _boxBody(m);
    return ListTile(
      visualDensity: kAvatarListTileDensity,
      minTileHeight: headFrameSlotSize(18),
      leading: AvatarView(
        name: name,
        avatarUrl: profile?.avatarUrl,
        frameId: profile?.headFrameId,
        headType: head?.type,
        headId: head?.id,
        radius: 18,
      ),
      title: Text(
        m.title.isNotEmpty ? m.title : m.headline,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: m.unread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: (body.isEmpty && m.picUrl.isEmpty)
          ? null
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.picUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      child: Image.network(
                        m.picUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                if (body.isNotEmpty)
                  Expanded(
                    child: Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (m.time > 0 || m.location.isNotEmpty)
            Text(
              fmtMsgTimeIp(m.time, m.location),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          if (m.hasDetail)
            _DetailButton(onPressed: () => _openDynamics(m.pid)),
        ],
      ),
      onTap: m.hasDetail ? () => _openDynamics(m.pid) : null,
    );
  }

  /// 互动通知副行正文（评论正文等；与被互动动态正文不同才显示）。
  static String _boxBody(MsgBoxMessage m) {
    if (m.question.isNotEmpty && m.content.isNotEmpty) return m.content;
    if (m.pidContent.isNotEmpty && m.content.isNotEmpty) return m.content;
    return '';
  }
}

/// 顶部圆入口按钮（圆底图标 + 标题 + 未读角标）。
class _TopEntryButton extends StatelessWidget {
  final MsgBoxEntry entry;
  final int unread;
  final bool selected;
  final VoidCallback onTap;

  const _TopEntryButton({
    required this.entry,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _entryStyle(theme, entry);
    final circle = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: selected ? Border.all(color: style.color, width: 2) : null,
      ),
      child: Icon(style.icon, color: style.color, size: 26),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            if (unread > 0)
              Badge(
                label: Text(entry == MsgBoxEntry.fans ? 'NEW' : '$unread'),
                child: circle,
              )
            else
              circle,
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 未读角标（红底白字，>99 显示 99+）。
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: AppRadius.pillR,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.colorScheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 行内 `详情` 链接。
class _DetailButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DetailButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 28),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('详情'),
    );
  }
}

/// 分类图标 / 颜色。
({IconData icon, Color color}) _categoryStyle(ThemeData theme, int channel) {
  switch (channel) {
    case MsgChannel.gift:
      return (icon: Icons.card_giftcard, color: const Color(0xFFE91E63));
    case MsgChannel.systemMail:
      return (icon: Icons.mail_outline, color: theme.colorScheme.primary);
    case MsgChannel.creator:
      return (icon: Icons.auto_awesome_outlined, color: const Color(0xFF7C4DFF));
    case MsgChannel.sysMsg:
      return (icon: Icons.notifications_none, color: const Color(0xFF546E7A));
    case MsgChannel.friendMail:
      return (icon: Icons.drafts_outlined, color: const Color(0xFFFF9800));
    case MsgChannel.activityAssistant:
      return (icon: Icons.assistant_outlined, color: const Color(0xFF009688));
    case MsgChannel.activity:
      return (icon: Icons.campaign_outlined, color: const Color(0xFFF44336));
    default:
      return (icon: Icons.mail_outline, color: theme.colorScheme.primary);
  }
}

/// 顶部入口图标 / 颜色。
({IconData icon, Color color}) _entryStyle(ThemeData theme, MsgBoxEntry entry) {
  switch (entry) {
    case MsgBoxEntry.dynamics:
      return (icon: Icons.favorite_border, color: const Color(0xFFE91E63));
    case MsgBoxEntry.fans:
      return (
        icon: Icons.person_add_alt_1_outlined,
        color: const Color(0xFFFF9800),
      );
    case MsgBoxEntry.works:
      return (
        icon: Icons.photo_library_outlined,
        color: theme.colorScheme.primary,
      );
  }
}

/// 相对时间（对齐 messagecenterdatamgr.lua convertTime）。
String fmtMsgTime(int ts) {
  if (ts <= 0) return '';
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final sub = now - ts;
  if (sub <= 60) return '刚刚';
  if (sub <= 3600) return '${sub ~/ 60}分钟前';
  if (sub <= 86400) return '${sub ~/ 3600}小时前';
  if (sub <= 2592000) return '${sub ~/ 86400}天前';
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

/// `N小时前 IP 省`（互动通知时间行；location 为空时只显示相对时间）。
String fmtMsgTimeIp(int ts, String location) {
  final t = fmtMsgTime(ts);
  if (location.isEmpty) return t;
  return t.isEmpty ? 'IP $location' : '$t IP $location';
}

/// 邮件详情页。
class MailDetailPage extends ConsumerStatefulWidget {
  final MsgItem item;
  final Future<void> Function()? onTake;
  final Future<void> Function()? onDelete;

  const MailDetailPage({
    super.key,
    required this.item,
    this.onTake,
    this.onDelete,
  });

  @override
  ConsumerState<MailDetailPage> createState() => _MailDetailPageState();
}

class _MailDetailPageState extends ConsumerState<MailDetailPage> {
  late MsgItem _item;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_item.title.isNotEmpty ? _item.title : '消息详情'),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await widget.onDelete?.call();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          Text(
            _item.title.isNotEmpty ? _item.title : '（无标题）',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '时间：${fmtMsgTime(_item.createTime)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 图片
          if (_item.images.isNotEmpty) ...[
            for (final url in _item.images)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: Image.network(
                    url,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 120,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // 正文
          Text(
            _item.content.isEmpty ? '（无内容）' : _item.content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: AppSpacing.xl),
          // 附件
          if (_item.attach.isNotEmpty) ...[
            Text('附件', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final a in _item.attach)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.card_giftcard,
                  color: _item.attachmentTaken
                      ? theme.colorScheme.outline
                      : AppSemanticColors.of(context).warning,
                ),
                title: Text(a.name.isNotEmpty ? a.name : '物品 ${a.id}'),
                trailing: a.count > 0 ? Text('×${a.count}') : null,
              ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _item.attachmentTaken || widget.onTake == null
                  ? null
                  : () async {
                      await widget.onTake?.call();
                      if (mounted) {
                        setState(
                          () => _item = _item.copyWith(attachmentTaken: true),
                        );
                      }
                    },
              icon: const Icon(Icons.card_giftcard),
              label: Text(_item.attachmentTaken ? '已领取' : '领取附件'),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          // 跳转
          if (_item.jumpTo.isNotEmpty && _item.jumpTo != '0')
            OutlinedButton.icon(
              onPressed: () {
                // 仅 HTTP 链接可直接展示；跳转号当前客户端不支持跳转
                final jt = _item.jumpTo;
                if (jt.startsWith('http')) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('链接')),
                        body: SingleChildScrollView(
                          padding: AppSpacing.pagePadding,
                          child: SelectableText(jt),
                        ),
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('该跳转类型暂不支持')),
                  );
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(_item.jumpName.isNotEmpty ? _item.jumpName : '前往'),
            ),
        ],
      ),
    );
  }
}
