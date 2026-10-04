part of 'chat_page.dart';

/// 聊天气泡：把 `#A1xx` 表情码渲染为行内真实游戏贴图（EmoticonImage），
/// 其余为普通文本；按是否我发出对齐并应用气泡底色。
class _InlineEmojiBubble extends StatelessWidget {
  final Message message;
  final bool isSentByMe;

  const _InlineEmojiBubble({required this.message, required this.isSentByMe});

  /// 只有「本进程运行期间到的」（新收到 / 自己刚发）才播动画；
  /// 历史消息直接显示结果帧 —— 骰子/猜拳是即时反馈，翻旧记录不该重播。
  bool get _animateEmoji => message.metadata?['live'] == true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw =
        (message.metadata?['raw'] as String?) ??
        switch (message) {
          TextMessage m => m.text,
          SystemMessage m => m.text,
          _ => '',
        };
    // 动态/互动表情的真身在 extend_data.interCode 里（文本只是低版本提示文案）。
    final emojiCode = emojiCodeForMessage(
      text: raw,
      interCode: message.metadata?['interCode']?.toString(),
    );
    final maxWidth =
        MediaQuery.of(context).size.width * _kBubbleMaxWidthFactor;
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSentByMe
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: isSentByMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 动态/互动表情：渲染成图，不显示低版本提示文案或 JSON 原文。
              if (emojiCode != null)
                _EmojiMessageBody(code: emojiCode, animate: _animateEmoji)
              else if (isDynamicEmojiHint(raw))
                // 解不出表情代码（老数据 / 离线历史 / 素材缺失）时，也别把
                // 那句「请升级到最新版本查看」当正文显示 —— 给个中性提示。
                const _DynamicEmojiHintChip()
              else
                // 复用共享富文本解析：支持 [color=] / #cRRGGBB / #n / #A1xx 表情 /
                // @提及 等（见 rich_text_view.dart）。
                Text.rich(
                  TextSpan(
                    children: buildRichSpans(
                      raw,
                      context: context,
                      emojiSize: 24,
                      emojiAnimate: _animateEmoji,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 时间分隔条文案：同一天 → `HH:mm`，跨天 → `MM-DD HH:mm`。
///
/// 与 `session_list_page.dart` / `friend_request_page.dart` 的 `_fmtTime`
/// 同源（同天只显示时分），跨天追加月日以免丢失日期信息。
String _fmtDividerTime(DateTime dt) {
  final l = dt.toLocal();
  final now = DateTime.now();
  final sameDay =
      l.year == now.year && l.month == now.month && l.day == now.day;
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  final mo = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '$mo-$dd $hh:$mm';
}

/// 富媒体气泡（share / custom 消息卡片）。
///
/// 从 [CustomMessage.metadata] 的 `extend`（url→base64→JSON）解码 [RichMedia]：
/// - 红包（Type=SendFriendRedPocket）→ 红包卡（点击占位提示，无法在外部客户端领取）
/// - 动态通知/动态分享（shareType 19/18）→ 动态卡（点击打开详情）
/// - 地图分享（shareType 1）→ 地图卡
/// - 链接（shareType 9）→ 链接卡
/// - 其余 → 回退为纯文本卡片。
class _RichMediaBubble extends ConsumerWidget {
  final CustomMessage message;
  final bool isSentByMe;

  /// 点击动态卡片回调（仅好友会话有效；群会话不跳动态详情）。
  final ValueChanged<String>? onOpenDynamics;

  /// 同上：只有运行期间新到的才播动画。
  bool get _isLive => message.metadata?['live'] == true;

  const _RichMediaBubble({
    required this.message,
    required this.isSentByMe,
    this.onOpenDynamics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rawExt = message.metadata?['extend']?.toString();
    final media = RichMedia.decode(rawExt);

    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width * _kBubbleMaxWidthFactor,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          decoration: BoxDecoration(
            color: isSentByMe
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: media == null
              ? _plainText()
              : media.isFriendGift
              ? _giftCard(context, ref, media, theme)
              : (media.isMap || media.isRoomInvite)
              ? _mapCard(context, media, theme)
              : _card(context, media, theme),
        ),
      ),
    );
  }

  /// 礼物卡（紧凑两行）：礼物图 + 名称×数量，次行「默契礼物 · 来源 · 默契度」。
  ///
  /// 名称/图标来自服务端 visual-cfg（`new_give_gift_config` + `items`），
  /// 还没加载出来时退回「礼物 #id」+ 通用礼物图标。刻意做窄做矮：礼物在会话里
  /// 常连发，原三行大卡（56 图 + 独立标题行）太占竖向空间。
  Widget _giftCard(
    BuildContext context,
    WidgetRef ref,
    RichMedia media,
    ThemeData theme,
  ) {
    final gift = ref
        .watch(giftCatalogProvider)
        .asData
        ?.value
        .byId(media.giftItemId);
    final name = gift?.displayName ?? '礼物 ${media.giftItemId}';
    final icon = gift?.icon;
    final num = media.giftNum > 0 ? media.giftNum : 1;
    final who = media.giftSrcName.isNotEmpty
        ? media.giftSrcName
        : media.nickname;
    final meta = [
      '默契礼物',
      if (who.isNotEmpty) who,
      if (media.giftAddValue > 0) '默契度 +${media.giftAddValue}',
    ].join(' · ');
    return InkWell(
      borderRadius: AppRadius.inputR,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name ×$num')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: icon != null && icon.startsWith('http')
                    ? Image.network(
                        icon,
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.card_giftcard, size: 22),
                      )
                    : const Icon(Icons.card_giftcard, size: 22),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name ×$num',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 无法解码 → 回退纯文本卡。
  ///
  /// 但动态表情要先看一眼 `extend_data.interCode`：它可能被归成 share/custom
  /// 类型走到这里，此时正文只是「请升级到最新版本查看」，必须改成渲染表情。
  Widget _plainText() {
    final code = _emojiCodeOrNull;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (code != null)
            _EmojiMessageBody(code: code, animate: _isLive)
          else if (isDynamicEmojiHint(customMessageText(message)))
            const _DynamicEmojiHintChip()
          else
            Text(
              customMessageText(message),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  /// 本条消息应渲染的表情代码（interCode 优先，其次动态表情的 JSON 信封）。
  String? get _emojiCodeOrNull {
    final ext = message.metadata?['extend']?.toString();
    final interCode =
        message.metadata?['interCode']?.toString() ??
        decodeChatExtendData(ext)?['interCode']?.toString();
    return emojiCodeForMessage(
      text: message.metadata?['text']?.toString() ?? ext,
      interCode: interCode,
    );
  }

  /// 地图 / 房间分享：两列卡（缩略图 + 标题 + 说明 + 标签），对齐游戏样式。
  Widget _mapCard(BuildContext context, RichMedia media, ThemeData theme) {
    final isRoom = media.isRoomInvite;
    final title = isRoom
        ? (media.roomName.isNotEmpty ? media.roomName : '房间邀请')
        : (media.name.isNotEmpty ? media.name : '地图分享');
    final desc = isRoom ? '邀请你一起玩 · 需在游戏内加入房间' : '邀请你一起玩 · 发现一个好玩的地图，快来一起吧';
    return InkWell(
      borderRadius: AppRadius.inputR,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isRoom ? '房间需在游戏内加入' : '地图需在游戏内打开')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 76,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.inputR,
                    color: theme.colorScheme.primaryContainer,
                  ),
                  child: Icon(
                    isRoom ? Icons.meeting_room_outlined : Icons.map_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isRoom ? '房间' : '地图',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, RichMedia media, ThemeData theme) {
    // 除图标+标题外是否有可展示的细节；没有则给一句兜底说明，避免空卡片。
    final hasDetail =
        media.name.isNotEmpty ||
        media.author.isNotEmpty ||
        media.content.isNotEmpty ||
        media.picList.isNotEmpty ||
        (media.isUrl && media.url.isNotEmpty) ||
        media.isRedPacket ||
        ((media.isPat || media.isCustomPanel) && media.subtitle.isNotEmpty);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: media.isDynamicNotice || media.isDynamics
          ? (media.pid.isNotEmpty && onOpenDynamics != null
                ? () => onOpenDynamics!(media.pid)
                : null)
          : media.isRedPacket
          ? () {
              // 外部客户端无支付流，无法领取红包；仅提示。
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('红包需在游戏内领取')));
            }
          : media.isRoomInvite
          ? () {
              // 外部客户端无法进入游戏房间；展示房间信息。
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '房间: ${media.roomName.isNotEmpty ? media.roomName : media.roomUin}'
                    '（需在游戏内加入）',
                  ),
                ),
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: isSentByMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconFor(media),
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  media.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 图片预览（动态/红包图）
            if (media.picList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image(image: CachedNetworkImageProvider(media.picList.first),
                    width: 120,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 120,
                      height: 90,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_outlined),
                    ),
                  ),
                ),
              ),
            // 名称 / 内容摘要
            if (media.name.isNotEmpty)
              Text(
                media.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (media.author.isNotEmpty)
              Text(
                '作者: ${media.author}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            if (media.content.isNotEmpty)
              Text(
                media.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            // 拍一拍 / 自定义面板：正文取 tapText / customData.strContent。
            if ((media.isPat || media.isCustomPanel) &&
                media.content.isEmpty &&
                media.subtitle.isNotEmpty)
              Text(
                media.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            if (media.isUrl && media.url.isNotEmpty)
              Text(
                media.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            if (media.isRedPacket)
              Text(
                '金额 ¥${media.amount > 0 ? media.amount / 10 : '?'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (!hasDetail)
              Text(
                media.hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(RichMedia media) {
    if (media.isFriendGift) return Icons.card_giftcard;
    if (media.isRedPacket || media.shareType == ShareType.familyRedPacket) {
      return Icons.redeem;
    }
    if (media.isRoomInvite) return Icons.videogame_asset_outlined;
    if (media.isPat) return Icons.touch_app_outlined;
    if (media.isAchieve) return Icons.emoji_events_outlined;
    if (media.isCustomPanel) return Icons.style_outlined;
    if (media.isDynamicNotice || media.isDynamics) return Icons.public;
    if (media.isMap) return Icons.map_outlined;
    if (media.isUrl) return Icons.link;
    switch (media.shareType) {
      case ShareType.role:
        return Icons.person_outline;
      case ShareType.skin:
      case ShareType.chameleon:
        return Icons.checkroom_outlined;
      case ShareType.ride:
        return Icons.directions_car_outlined;
      case ShareType.weapon:
        return Icons.hardware_outlined;
      case ShareType.avatar:
      case ShareType.avatarMatch:
        return Icons.account_circle_outlined;
      case ShareType.familyRecruit:
      case ShareType.familyInvite:
      case ShareType.familyServer:
      case ShareType.familyDynamics:
        return Icons.family_restroom_outlined;
      case ShareType.rankSystem:
        return Icons.leaderboard_outlined;
      case ShareType.contentFavsShare:
        return Icons.bookmark_outline;
      case ShareType.qixiPartnerInvite:
      case ShareType.customPeerShare:
        return Icons.favorite_outline;
      case ShareType.resourceGoodShare:
      case ShareType.versionResCrShare:
        return Icons.inventory_2_outlined;
      case ShareType.action:
        return Icons.sports_martial_arts_outlined;
      case ShareType.customPic:
        return Icons.image_outlined;
      default:
        return Icons.article_outlined;
    }
  }
}

/// 把表情代码渲染成消息里的图。
///
/// 互动表情（骰子/猜拳 `@IMFC&N_M`）用图集结果帧/动图；动态表情（`[mdemo]...`）
/// 用内置动图。
class _EmojiMessageBody extends StatelessWidget {
  /// 气泡里表情的渲染尺寸（比行内表情大得多，和游戏里一致）。
  static const double kSize = 96;

  final String code;

  /// 是否播动画：新收到/刚发的播，历史消息直接显示结果帧。
  final bool animate;

  const _EmojiMessageBody({required this.code, this.animate = true});

  @override
  Widget build(BuildContext context) {
    final imfc = parseImfc(code);
    return imfc != null
        ? ImfcEmojiImage(ref: imfc, size: kSize, animate: animate)
        : EmojiCodeImage(code: code, size: kSize, animate: animate);
  }
}

/// 「拿不到表情代码的动态表情」的中性提示。
///
/// 老数据 / 离线历史（`chat_query` 只回三元组）/ 游戏本身就缺素材的那一个，
/// 都解不出 interCode —— 此时不要把「请升级到最新版本查看」当正文显示。
class _DynamicEmojiHintChip extends StatelessWidget {
  const _DynamicEmojiHintChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.emoji_emotions_outlined,
          size: 18,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Text(
          '动态表情',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
