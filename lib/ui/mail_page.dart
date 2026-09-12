/// 消息中心（邮件）页 —— /miniw/msgcenter 客户端 UI。
///
/// 两个频道 tab：官方邮件(1) / 好友邮件(2)。每条消息：
/// - 未读红点 + 标题 + 内容摘要 + 相对时间；
/// - 点击进详情：全文、图片、附件（可领取）、跳转按钮、删除、标记已读。
/// 官方邮件红点（fetch_reddot）在进入页面时拉取一次。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/message_center.dart';
import '../state/providers.dart';

/// 消息中心主页面（AppBar 返回 + 频道切换）。
class MailPage extends ConsumerStatefulWidget {
  const MailPage({super.key});

  @override
  ConsumerState<MailPage> createState() => _MailPageState();
}

class _MailPageState extends ConsumerState<MailPage> {
  int _channel = MsgChannel.systemMail;
  final Map<int, List<MsgItem>> _items = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  MessageCenterClient? get _client => ref.read(chatServiceProvider).messageCenter;

  /// 拉消息流 + 按 id 取详情。type=1（新增）条目转详情。
  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      setState(() {
        _error = '未登录';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (flow, _) = await client.fetchMsgFlow(_channel);
      if (flow.isEmpty) {
        setState(() {
          _items[_channel] = [];
          _loading = false;
        });
        return;
      }
      final details = await client.fetchMsgByIDs(
        _channel,
        flow.map((e) => e.id).toList(),
      );
      final list = <MsgItem>[];
      for (final e in flow) {
        final d = details[e.id];
        if (d != null) list.add(d);
      }
      setState(() {
        _items[_channel] = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  void _switchChannel(int c) {
    if (c == _channel) return;
    setState(() => _channel = c);
    if (_items[c] == null) _load();
  }

  Future<void> _onDelete(MsgItem item) async {
    final client = _client;
    if (client == null) return;
    final ok = await client.deleteMessages(_channel, [item.id]);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _items[_channel]?.removeWhere((e) => e.id == item.id);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }

  Future<void> _onTake(MsgItem item) async {
    final client = _client;
    if (client == null) return;
    final ok = await client.takeAttachments(_channel, [item.id]);
    if (!mounted) return;
    if (ok.contains(item.id)) {
      setState(() {
        final list = _items[_channel];
        if (list != null) {
          final i = list.indexWhere((e) => e.id == item.id);
          if (i >= 0) list[i] = list[i].copyWith(attachmentTaken: true);
        }
      });
    }
  }

  Future<void> _onRead(MsgItem item) async {
    final client = _client;
    if (client == null) return;
    await client.readMessages(_channel, [item.id]);
    if (!mounted) return;
    setState(() {
      final list = _items[_channel];
      if (list != null) {
        final i = list.indexWhere((e) => e.id == item.id);
        if (i >= 0) list[i] = list[i].copyWith(readState: 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('消息中心'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            onTap: (i) => _switchChannel(
              i == 0 ? MsgChannel.systemMail : MsgChannel.friendMail,
            ),
            tabs: const [
              Tab(text: '官方邮件'),
              Tab(text: '好友邮件'),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && (_items[_channel]?.isEmpty ?? true)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (_items[_channel]?.isEmpty ?? true)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final list = _items[_channel] ?? const <MsgItem>[];
    if (list.isEmpty) {
      return const Center(child: Text('暂无邮件'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final item = list[i];
          return ListTile(
            leading: Icon(
              item.unread ? Icons.mark_email_unread : Icons.drafts_outlined,
              color: item.unread
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            title: Text(
              item.title.isNotEmpty ? item.title : '（无标题）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: item.unread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            subtitle: Text(
              item.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_fmtTime(item.createTime)),
                if (item.attach.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.card_giftcard,
                      size: 16,
                      color: item.attachmentTaken
                          ? Theme.of(context).colorScheme.outline
                          : Colors.orange,
                    ),
                  ),
              ],
            ),
            onTap: () async {
              // 进详情前先标已读
              await _onRead(item);
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MailDetailPage(
                    item: item,
                    onTake: item.attach.isNotEmpty ? () => _onTake(item) : null,
                    onDelete: () => _onDelete(item),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 相对时间显示（对齐 messagecenterdatamgr.lua convertTime）。
  static String _fmtTime(int ts) {
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
        title: Text(_item.title.isNotEmpty ? _item.title : '邮件详情'),
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
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _item.title.isNotEmpty ? _item.title : '（无标题）',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '时间：${_MailPageState._fmtTime(_item.createTime)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          // 图片
          if (_item.images.isNotEmpty) ...[
            for (final url in _item.images)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
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
            const SizedBox(height: 8),
          ],
          // 正文
          Text(
            _item.content.isEmpty ? '（无内容）' : _item.content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 24),
          // 附件
          if (_item.attach.isNotEmpty) ...[
            Text('附件', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final a in _item.attach)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.card_giftcard,
                  color: _item.attachmentTaken
                      ? theme.colorScheme.outline
                      : Colors.orange,
                ),
                title: Text(a.name.isNotEmpty ? a.name : '物品 ${a.id}'),
                trailing: a.count > 0 ? Text('×${a.count}') : null,
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  _item.attachmentTaken || widget.onTake == null ? null : () async {
                await widget.onTake?.call();
                if (mounted) {
                  setState(() => _item = _item.copyWith(attachmentTaken: true));
                }
              },
              icon: const Icon(Icons.card_giftcard),
              label: Text(_item.attachmentTaken ? '已领取' : '领取附件'),
            ),
            const SizedBox(height: 16),
          ],
          // 跳转
          if (_item.jumpTo.isNotEmpty && _item.jumpTo != '0')
            OutlinedButton.icon(
              onPressed: () {
                // 仅 HTTP 链接可直接复制；跳转号当前客户端不支持跳转
                final jt = _item.jumpTo;
                if (jt.startsWith('http')) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('链接')),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
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
