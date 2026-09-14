/// 玩家简要信息浮窗（会话头像 / 侧栏本人头像共用）。
///
/// - [showSessionPlayerInfoPopup]：在头像附近弹出的浮动信息卡（等级 / 默契度 /
///   冒险家 / 称号 / 勋章 + 个人中心 / 置顶 / 赠送 / 更多），替代原先的全屏
///   底部弹窗；
/// - 拉取结果放进程内缓存 [_playerInfoCache]（uin → 快照），重开同一玩家直接
///   命中、不再请求；进行中的请求用 [_playerInfoPending] 合并。
///
/// 内容与 `player_info_sheet.dart` 的底部弹窗同源（同一批 ChatService 接口 +
/// 同一套主页字段解析）；该文件的渲染与解析辅助均为私有且不在本次改动范围，
/// 因此这里按浮窗布局重新实现，数据口径保持一致。
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/medal_catalog.dart';
import '../../core/models/messages.dart';
import '../../core/storage/settings_store.dart';
import '../../state/providers.dart';
import '../player_home_page.dart';
import '../theme/app_tokens.dart';
import 'avatar_view.dart';
import 'player_info_sheet.dart' show showFriendMenu;
import 'rich_text_view.dart';

/// 玩家信息快照：浮窗展示所需的一次性拉取结果。
class SessionPlayerInfo {
  /// 平台等级（`platformLevel`；0 = 未知）。
  final int level;

  /// 个人主页数据（`userHomepage`：默契度 / 勋章 / 称号等）。
  final Map<String, Object?>? home;

  /// 冒险家评分（`otherPlayerScore`；null = 未知）。
  final Map<String, Object?>? score;

  /// 当前佩戴称号名（`titleName`；null = 未佩戴）。
  final String? title;

  const SessionPlayerInfo({
    required this.level,
    required this.home,
    required this.score,
    required this.title,
  });

  /// 拉取失败 / 无数据时的占位快照。
  static const SessionPlayerInfo empty = SessionPlayerInfo(
    level: 0,
    home: null,
    score: null,
    title: null,
  );
}

/// 玩家信息进程内缓存（uin → 快照）。
///
/// 重开同一玩家的浮窗时直接命中，不再发请求（需求：缓存 medals / 等级 /
/// 称号等）。仅在进程内有效，随账号切换不清理（uin 全局唯一，无串号风险）。
final Map<int, SessionPlayerInfo> _playerInfoCache = <int, SessionPlayerInfo>{};

/// 进行中的拉取（uin → future）：同一玩家并发打开时复用同一请求。
final Map<int, Future<SessionPlayerInfo>> _playerInfoPending =
    <int, Future<SessionPlayerInfo>>{};

/// 取玩家信息：命中缓存 → 复用进行中的请求 → 新请求。
Future<SessionPlayerInfo> _playerInfoOf(WidgetRef ref, int uin) {
  final cached = _playerInfoCache[uin];
  if (cached != null) return Future<SessionPlayerInfo>.value(cached);
  final pending = _playerInfoPending[uin];
  if (pending != null) return pending;
  final future = _fetchPlayerInfo(ref, uin);
  _playerInfoPending[uin] = future;
  return future;
}

/// 拉取玩家信息（等级 / 主页 / 冒险家 / 称号）并写入缓存。
///
/// 失败返回 [SessionPlayerInfo.empty] 且**不写缓存**，下次打开可重试。
Future<SessionPlayerInfo> _fetchPlayerInfo(WidgetRef ref, int uin) async {
  try {
    final svc = ref.read(chatServiceProvider);
    final level = await svc.platformLevel(uin);
    final home = await svc.userHomepage(uin);
    final score = await svc.otherPlayerScore(uin);
    final tid = _useTitleId(home);
    final title = tid > 0 ? await svc.titleName(tid) : null;
    final info = SessionPlayerInfo(
      level: level,
      home: home,
      score: score,
      title: title,
    );
    _playerInfoCache[uin] = info;
    return info;
  } catch (_) {
    return SessionPlayerInfo.empty;
  } finally {
    _playerInfoPending.remove(uin);
  }
}

/// 在 [anchor]（头像的屏幕矩形）附近弹出玩家信息浮窗。
///
/// 采用 `showDialog` + `Stack/Positioned`：路由自带遮罩点击 / 返回键关闭，
/// 无需自行管理 OverlayEntry；卡片位置按锚点自动翻转（锚点在下半屏时向上
/// 弹），保证不越出屏幕。[anchor] 为空时落在左上角（无锚点 / 测试场景）。
Future<void> showSessionPlayerInfoPopup(
  BuildContext context,
  WidgetRef ref, {
  required int uin,
  required String name,
  Rect? anchor,
  String? avatarUrl,
  int? headType,
  int? headId,
  int? headFrameId,
  bool showActions = true,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => _SessionPlayerInfoPopup(
      anchor: anchor,
      hostContext: context,
      ref: ref,
      uin: uin,
      name: name,
      avatarUrl: avatarUrl,
      headType: headType,
      headId: headId,
      headFrameId: headFrameId,
      showActions: showActions,
    ),
  );
}

/// 浮窗定位：只负责把信息卡摆到头像旁边，不承载内容。
class _SessionPlayerInfoPopup extends StatelessWidget {
  final Rect? anchor;

  /// 触发浮窗的宿主 context：浮窗关闭后继续用它打开菜单 / 页面。
  final BuildContext hostContext;

  final WidgetRef ref;
  final int uin;
  final String name;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? headFrameId;

  /// 是否展示底部操作行（本人信息卡只展示资料，不带好友操作）。
  final bool showActions;

  const _SessionPlayerInfoPopup({
    required this.anchor,
    required this.hostContext,
    required this.ref,
    required this.uin,
    required this.name,
    this.avatarUrl,
    this.headType,
    this.headId,
    this.headFrameId,
    this.showActions = true,
  });

  /// 浮窗最大宽度（与底部弹窗信息区相当的紧凑卡片）。
  static const double _maxWidth = 340;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rect = anchor ?? Rect.fromLTWH(AppSpacing.lg, AppSpacing.lg, 1, 1);
    final maxLeft = size.width - _maxWidth - AppSpacing.sm;
    final left = maxLeft <= AppSpacing.sm
        ? AppSpacing.sm
        : rect.left.clamp(AppSpacing.sm, maxLeft).toDouble();
    // 锚点在上半屏 → 向下展开；否则向上弹，避免越出底边。
    final below = rect.center.dy <= size.height / 2;
    final maxHeight = (size.height - AppSpacing.xxl).clamp(
      160.0,
      double.infinity,
    );
    return Stack(
      children: [
        Positioned(
          left: left,
          top: below ? rect.bottom + AppSpacing.sm : null,
          bottom: below ? null : size.height - rect.top + AppSpacing.sm,
          width: _maxWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: _SessionPlayerInfoCard(
                hostContext: hostContext,
                ref: ref,
                uin: uin,
                name: name,
                avatarUrl: avatarUrl,
                headType: headType,
                headId: headId,
                headFrameId: headFrameId,
                showActions: showActions,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 信息卡内容：头像 + 昵称 + 迷你号 + 等级/默契度/称号 + 勋章 + 操作行。
class _SessionPlayerInfoCard extends StatefulWidget {
  final BuildContext hostContext;
  final WidgetRef ref;
  final int uin;
  final String name;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? headFrameId;

  /// 是否展示底部操作行（本人信息卡为 false，只展示资料）。
  final bool showActions;

  const _SessionPlayerInfoCard({
    required this.hostContext,
    required this.ref,
    required this.uin,
    required this.name,
    this.avatarUrl,
    this.headType,
    this.headId,
    this.headFrameId,
    this.showActions = true,
  });

  @override
  State<_SessionPlayerInfoCard> createState() => _SessionPlayerInfoCardState();
}

class _SessionPlayerInfoCardState extends State<_SessionPlayerInfoCard> {
  /// 本地置顶状态；null = 读取中（按钮先按未置顶绘制）。
  bool? _pinned;

  /// 会话置顶 key（好友类型，与底部弹窗一致）。
  String get _pinKey =>
      SettingsKeys.sessionKey(ChatSessionType.friend.name, widget.uin);

  @override
  void initState() {
    super.initState();
    if (widget.showActions) _readPinned();
  }

  Future<void> _readPinned() async {
    try {
      final pinned = await widget.ref.read(settingsProvider).isPinned(_pinKey);
      if (mounted) setState(() => _pinned = pinned);
    } catch (_) {
      if (mounted) setState(() => _pinned = false);
    }
  }

  Future<void> _togglePinned() async {
    final next = !(_pinned ?? false);
    setState(() => _pinned = next);
    try {
      await widget.ref.read(settingsProvider).setPinned(_pinKey, next);
    } catch (_) {
      // 设置不可用（测试等）时忽略持久化失败，保持本地状态。
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(next ? '已置顶' : '已取消置顶')));
  }

  /// 个人中心：先关浮窗，再推入玩家主页。
  void _openHomePage() {
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerHomePage(targetUin: widget.uin),
        ),
      ),
    );
  }

  /// 赠送：暂未开放（与底部弹窗一致）。
  void _gift() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('暂未开放')));
    Navigator.of(context).pop();
  }

  /// 更多：关浮窗后打开好友操作菜单（与长按 / 右键共用）。
  Future<void> _openMoreMenu() async {
    Navigator.of(context).pop();
    final host = widget.hostContext;
    if (!host.mounted) return;
    await showFriendMenu(host, widget.ref, uin: widget.uin, name: widget.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinned = _pinned ?? false;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: AppRadius.cardR,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：头像 + 昵称 + 迷你号
            Row(
              children: [
                AvatarView(
                  avatarUrl: widget.avatarUrl,
                  name: widget.name,
                  radius: 32,
                  headType: widget.headType,
                  headId: widget.headId,
                  frameId: widget.headFrameId,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichTextView(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Uin: ${widget.uin}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // 等级 + 默契度 + 冒险家 + 称号 + 勋章（命中缓存时不重新请求）
            FutureBuilder<SessionPlayerInfo>(
              future: _playerInfoOf(widget.ref, widget.uin),
              builder: (context, snap) {
                final info = snap.data ?? SessionPlayerInfo.empty;
                final tacit = _tacitnumFor(info.home, widget.uin);
                final adv = info.score == null
                    ? '--'
                    : '${info.score!['name'] ?? ''} ${info.score!['level'] ?? ''}'
                          .trim();
                final medals = _medalList(info.home);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (info.level > 0)
                          _infoChip(
                            theme,
                            Icons.workspace_premium_outlined,
                            'Lv${info.level}',
                            color: theme.colorScheme.tertiary,
                          ),
                        _infoChip(
                          theme,
                          Icons.favorite_border,
                          '默契度：$tacit',
                          color: Colors.pinkAccent,
                        ),
                        _infoChip(
                          theme,
                          Icons.military_tech_outlined,
                          '冒险家：$adv',
                          color: theme.colorScheme.primary,
                        ),
                        _infoChip(
                          theme,
                          Icons.local_police_outlined,
                          '称号：${info.title ?? '未佩戴'}',
                          color: theme.colorScheme.tertiary,
                        ),
                      ],
                    ),
                    // 勋章行（最多 6 枚，图标 + 等级边框）
                    if (medals.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: AppRadius.inputR,
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final m in medals.take(6))
                              _medalBadge(theme, m.$1, m.$2),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            if (widget.showActions) ...[
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              // 操作行：个人中心 / 置顶 / 赠送 / 更多
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _CircleAction(
                    icon: Icons.person_outline,
                    label: '个人中心',
                    onTap: _openHomePage,
                  ),
                  _CircleAction(
                    icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: pinned ? '取消置顶' : '置顶',
                    highlighted: pinned,
                    onTap: () => unawaited(_togglePinned()),
                  ),
                  _CircleAction(
                    icon: Icons.card_giftcard,
                    label: '赠送',
                    onTap: _gift,
                  ),
                  _CircleAction(
                    icon: Icons.more_horiz,
                    label: '更多',
                    onTap: () => unawaited(_openMoreMenu()),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 从主页 `partner` 模块取与指定好友的默契度（无匹配则退回首项，仍无则 0）。
int _tacitnumFor(Map<String, Object?>? home, int uin) {
  final partner = home?['partner'];
  if (partner is! List) return 0;
  int? fallback;
  for (final e in partner) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final t = m['tacitnum'];
    final tv = t is num ? t.toInt() : int.tryParse('$t') ?? 0;
    final bu = m['bestUin'];
    final buv = bu is num ? bu.toInt() : int.tryParse('$bu') ?? 0;
    if (buv == uin) return tv;
    fallback ??= tv;
  }
  return fallback ?? 0;
}

/// 从主页 `title` 模块取当前佩戴称号 id（`title.data.match_title.use_title.id`）。
int _useTitleId(Map<String, Object?>? home) {
  final title = home?['title'];
  if (title is! Map) return 0;
  final data = title['data'];
  if (data is! Map) return 0;
  final match = data['match_title'];
  if (match is! Map) return 0;
  final use = match['use_title'];
  if (use is! Map) return 0;
  final id = use['id'] ?? use['ID'];
  if (id is num) return id.toInt();
  return int.tryParse('$id') ?? 0;
}

/// 信息行内的小项：图标 + 文本。
Widget _infoChip(ThemeData theme, IconData icon, String text, {Color? color}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
      const SizedBox(width: AppSpacing.xs),
      Text(text, style: theme.textTheme.bodySmall),
    ],
  );
}

/// 从主页 `achieve` 模块取勋章列表（`achieve.data.medal_list` → [(id, level)]）。
List<(int, int)> _medalList(Map<String, Object?>? home) {
  final achieve = home?['achieve'];
  if (achieve is! Map) return const [];
  final data = achieve['data'];
  if (data is! Map) return const [];
  final list = data['medal_list'];
  if (list is! List) return const [];
  final out = <(int, int)>[];
  for (final e in list) {
    if (e is! Map) continue;
    final m = e.cast<String, Object?>();
    final id = m['id'];
    final lv = m['level'];
    final idv = id is num ? id.toInt() : int.tryParse('$id') ?? 0;
    final lvv = lv is num ? lv.toInt() : int.tryParse('$lv') ?? 0;
    if (idv > 0) out.add((idv, lvv));
  }
  return out;
}

/// 单枚勋章：普通勋章=图标+等级边框；isNew 勋章=按等级的徽章图标（40×40）。
Widget _medalBadge(ThemeData theme, int id, int level) {
  final lvlIcons = kMedalLevelIcons[id];
  if (lvlIcons != null && lvlIcons.isNotEmpty) {
    final idx = (level >= 1 && level <= lvlIcons.length) ? level - 1 : 0;
    return SizedBox(
      width: 40,
      height: 40,
      child: Image.asset(
        medalIconAsset(lvlIcons[idx]),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
  final icon = kMedalIconName[id];
  final frame = (level >= 1 && level <= kMedalFrameByLevel.length)
      ? kMedalFrameByLevel[level - 1]
      : null;
  return SizedBox(
    width: 40,
    height: 40,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (icon != null)
          Image.asset(
            medalIconAsset(icon),
            width: 30,
            height: 30,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (frame != null)
          Image.asset(
            medalIconAsset(frame),
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
      ],
    ),
  );
}

/// 信息卡操作按钮：圆形图标 + 文字标签。
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 激活态（如已置顶）用主题色高亮。
  final bool highlighted;

  const _CircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onTap,
          tooltip: label,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: highlighted
                ? theme.colorScheme.primaryContainer
                : null,
            foregroundColor: highlighted
                ? theme.colorScheme.onPrimaryContainer
                : null,
          ),
          icon: Icon(icon),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}
