part of 'mail_page.dart';

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
          // 游戏邮件详情显示的是**有效期**文案（GetCurMailTimeStr），不是创建时间。
          Text(
            mailValidityText(_item.endTime),
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
                  child: Image(image: CachedNetworkImageProvider(url),
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
                      : theme.colorScheme.primary,
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
