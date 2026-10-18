part of 'chat_page.dart';

/// 单条消息的长按操作。
enum MessageAction {
  copy,
  quote,
  forward,
  multiSelect,
  favorite,
  unfavorite,
  deleteLocal,
  resend,
}

/// 消息长按菜单（贴指针弹出，与 `widgets/session_menu.dart` 同风格）。
///
/// 用 `showMenu` + 指针位置换算的 [RelativeRect]，而不是底部弹窗：桌面端右键
/// （长按在鼠标上是 `LongPressStartDetails`）落点就在指针处，手机上也是长按点
/// 附近，比从屏幕底部滑上来更贴近"就地操作"。
Future<MessageAction?> showMessageActionMenu(
  BuildContext context, {
  required Offset position,
  required bool isMine,
  required bool isSystem,
  required bool hasText,
  required bool isFavorite,
  required bool canResend,
}) {
  final overlay = Overlay.of(context).context.findRenderObject();
  final overlaySize = overlay is RenderBox
      ? overlay.size
      : MediaQuery.sizeOf(context);
  final rect = RelativeRect.fromRect(
    Rect.fromLTWH(position.dx, position.dy, 1, 1),
    Offset.zero & overlaySize,
  );
  final theme = Theme.of(context);
  final errorColor = theme.colorScheme.error;
  final l10n = l10nOf(context);

  PopupMenuItem<MessageAction> item(
    MessageAction action,
    IconData icon,
    String label, {
    Color? color,
  }) => PopupMenuItem<MessageAction>(
    value: action,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.md),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );

  return showMenu<MessageAction>(
    context: context,
    position: rect,
    items: [
      // 系统消息没有正文/发送方，只给它"删除（仅本机）"。
      if (hasText) item(MessageAction.copy, Icons.copy, l10n?.menuCopy ?? '复制'),
      if (hasText && !isSystem)
        item(MessageAction.quote, Icons.format_quote, l10n?.menuQuote ?? '引用'),
      if (!isSystem)
        item(MessageAction.forward, Icons.forward, l10n?.menuForward ?? '转发'),
      if (!isSystem)
        item(
          MessageAction.multiSelect,
          Icons.checklist,
          l10n?.menuMultiSelect ?? '多选',
        ),
      if (canResend)
        item(MessageAction.resend, Icons.refresh, l10n?.menuResend ?? '重新发送'),
      if (!isSystem)
        item(
          isFavorite ? MessageAction.unfavorite : MessageAction.favorite,
          isFavorite ? Icons.star : Icons.star_border,
          isFavorite
              ? (l10n?.menuUnfavorite ?? '取消收藏')
              : (l10n?.menuFavorite ?? '收藏'),
          color: isFavorite ? theme.colorScheme.primary : null,
        ),
      if (!isSystem) const PopupMenuDivider(),
      if (!isSystem)
        item(
          MessageAction.deleteLocal,
          Icons.delete_outline,
          l10n?.menuDeleteLocal ?? '删除（仅本机）',
          color: errorColor,
        ),
    ],
  );
}

/// 多选模式的操作条（消息区下方的批量操作栏）。
class _SelectionBar extends StatelessWidget {
  /// 已选条数。
  final int count;

  final VoidCallback onFavorite;
  final VoidCallback onForward;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.count,
    required this.onFavorite,
    required this.onForward,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = l10nOf(context);
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: l10n?.commonCancel ?? '取消',
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
            Expanded(
              child: Text(
                l10n?.selectedCount(count) ?? '已选 $count 条',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: l10n?.actionFavorite ?? '收藏',
              icon: const Icon(Icons.star_border),
              onPressed: count == 0 ? null : onFavorite,
            ),
            IconButton(
              tooltip: l10n?.actionForward ?? '转发',
              icon: const Icon(Icons.forward),
              onPressed: count == 0 ? null : onForward,
            ),
            IconButton(
              tooltip: l10n?.actionDelete ?? '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: count == 0 ? null : onDelete,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

/// 转发目标选择器：列出全部会话（好友 + 群），返回选中的会话。
///
/// 只列会话列表里已有的会话（与服务端一致：转发目标就是能聊的会话）。
class _ForwardTargetPicker extends StatelessWidget {
  /// 候选会话（已按当前列表顺序，置顶在前）。
  final List<ChatSession> sessions;

  const _ForwardTargetPicker({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            l10n?.forwardPickSession ?? '选择要转发到的会话',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sessions.length,
            itemBuilder: (context, i) {
              final s = sessions[i];
              return ListTile(
                dense: true,
                leading: AvatarView(
                  name: s.name,
                  avatarUrl: s.avatar,
                  type: s.type,
                  radius: 18,
                  headType: s.headType,
                  headId: s.headId,
                  frameId: s.headFrameId,
                ),
                title: RichTextView(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  s.type == ChatSessionType.group ? '群聊' : '迷你号 ${s.id}',
                ),
                onTap: () => Navigator.of(context).pop(s),
              );
            },
          ),
        ),
      ],
    );
  }
}
