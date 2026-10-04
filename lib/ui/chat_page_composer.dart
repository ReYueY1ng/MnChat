part of 'chat_page.dart';

/// 中文空状态：覆盖 flutter_chat_ui 内置的英文 "No messages yet"。
///
/// 「打个招呼」按钮只把招呼语填进输入框（同快捷短语），发送由用户自己按发送键 ——
/// 空态里任何一键直发都会在误触时真的给对方发消息。
class _EmptyChatState extends StatelessWidget {
  final VoidCallback onInsert;

  const _EmptyChatState({required this.onInsert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '暂无消息，打个招呼吧 👋',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '发送第一条消息，开启你们的冒险',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onInsert,
              icon: const Icon(Icons.waving_hand_outlined, size: 16),
              label: const Text('打个招呼'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表情按钮：弹出游戏表情面板（「基础」内置表情 + 「我的」服务端表情包）。
class _ComposerBar extends ConsumerWidget {
  final ValueChanged<String> onInsert;
  final List<String> phrases;

  /// 互动表情（骰子/猜拳）：点按即发送，不走输入框。
  final ValueChanged<ImfcEmoji>? onImfc;

  /// @群成员：仅群聊传入；为空时不显示「@」按钮。
  final VoidCallback? onMention;

  const _ComposerBar({
    required this.onInsert,
    required this.phrases,
    this.onImfc,
    this.onMention,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 快捷短语 chips
        if (phrases.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              itemCount: phrases.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onInsert(phrases[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(phrases[i], style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ),
        // 工具栏：emoji / 礼物（图片入口已移除）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _ToolBtn(
                tooltip: '表情',
                icon: Icons.emoji_emotions_outlined,
                anchorKey: _emojiKey,
                onTap: () => _showEmojiPicker(context, ref),
              ),
              _ToolBtn(
                tooltip: '礼物',
                icon: Icons.card_giftcard_outlined,
                anchorKey: _giftKey,
                onTap: () => _showGiftPicker(context, ref),
              ),
              if (onMention != null)
                _ToolBtn(
                  tooltip: '@群成员',
                  icon: Icons.alternate_email,
                  onTap: onMention!,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 表情 / 礼物按钮的锚点：浮动面板要贴在按钮上方。
  static final GlobalKey _emojiKey = GlobalKey();
  static final GlobalKey _giftKey = GlobalKey();

  Rect? _anchorOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _showEmojiPicker(BuildContext context, WidgetRef ref) {
    showEmojiPicker(
      context,
      ref,
      onPick: onInsert,
      onImfc: onImfc,
      anchor: _anchorOf(_emojiKey),
    );
  }

  /// 当前会话的对方 uin（礼物只能送给好友）。群聊 / 未选中时不弹面板。
  void _showGiftPicker(BuildContext context, WidgetRef ref) {
    final active = ref.read(activeSessionProvider);
    if (active == null || active.type != ChatSessionType.friend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('礼物只能送给好友会话')),
      );
      return;
    }
    showGiftPicker(
      context,
      ref,
      uin: active.id,
      name: ref.read(sessionListProvider).asData?.value.sessions
              .where((s) => s.type == active.type && s.id == active.id)
              .firstOrNull
              ?.name ??
          '${active.id}',
      anchor: _anchorOf(_giftKey),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  /// 浮动面板的锚点（面板贴这个按钮弹出）。
  final Key? anchorKey;

  const _ToolBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.anchorKey,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: anchorKey,
      tooltip: tooltip,
      visualDensity: adaptiveDensity(context),
      icon: Icon(icon, size: 22),
      onPressed: onTap,
    );
  }
}

/// 发送按钮图标：输入为空时用弱化色（onSurfaceVariant），有非空白文本时
/// 切换为主题强调色（primary）。
///
/// Composer 的 M3 发送按钮在 `onPressed == null` 时统一走禁用色
///（`disabledColor`），传空的 `emptyFieldSendIconColor` 不生效；这里直接监听
/// 外部输入控制器自行着色，保证每次按键都即时更新（触屏/桌面一致）。
class _SendButtonIcon extends StatelessWidget {
  final TextEditingController controller;

  const _SendButtonIcon({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => Icon(
        Icons.send,
        color: value.text.trim().isEmpty
            ? scheme.onSurfaceVariant
            : scheme.primary,
      ),
    );
  }
}

/// @成员选择器：搜索并选中一个群成员，返回其昵称。
///
/// 昵称取自 `ChatService.groupMemberProfile`（进群详情时已批量拉取）；还没拉到
/// 资料时退化成迷你号 —— 至少让用户能选对人，而不是白屏。
class _MentionPicker extends StatefulWidget {
  const _MentionPicker({required this.members, required this.onPick});

  final List<({int uin, String name})> members;
  final ValueChanged<String> onPick;

  @override
  State<_MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<_MentionPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final q = _filter.trim().toLowerCase();
    final items = [
      for (final m in widget.members)
        if (q.isEmpty ||
            m.name.toLowerCase().contains(q) ||
            '${m.uin}'.contains(q))
          m,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _filter = v),
            decoration: const InputDecoration(
              hintText: '搜索群成员',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('没有匹配的成员'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    title: Text(items[i].name),
                    subtitle: Text('迷你号 ${items[i].uin}'),
                    onTap: () => widget.onPick(items[i].name),
                  ),
                ),
        ),
      ],
    );
  }
}
