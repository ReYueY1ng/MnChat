/// 玩家信息卡（底部弹窗 / 浮窗）的共用部分。
///
/// - [SessionPlayerInfo]：信息卡展示所需的一次性拉取快照（等级 / 主页 /
///   冒险家 / 称号）；
/// - [playerInfoOf]：取快照的进程内缓存入口（[_playerInfoCache] 命中直接返回，
///   进行中的请求用 [_playerInfoPending] 合并，失败不写缓存）；
/// - [PlayerInfoHeader] / [PlayerInfoStats] / [PlayerCircleAction]：两次展示
///   共用的内容片段（头部、等级信息区、圆形操作按钮）。
///
/// 主页字段解析（称号 id / 勋章列表）复用 `core/models/homepage_modules.dart`
/// 的公开解析器，不再各自持有私有拷贝。两种展示的容器与定位仍各自实现
/// （`player_info_sheet.dart` 是底部弹窗，`session_player_info_popup.dart`
/// 是锚定浮窗），此处只提供共享内容。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/homepage_modules.dart'
    show homepageMedals, homepageTitleId;
import '../../core/models/medal_catalog.dart';
import '../../core/services/partner.dart' show PartnerDirectory;
import '../../state/providers.dart';
import '../theme/app_tokens.dart';
import 'avatar_view.dart';
import 'rich_text_view.dart';

/// 玩家信息快照：信息卡展示所需的一次性拉取结果。
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
/// 重开同一玩家的信息卡时直接命中，不再发请求（需求：缓存 medals / 等级 /
/// 称号等）。仅在进程内有效，随账号切换不清理（uin 全局唯一，无串号风险）。
final Map<int, SessionPlayerInfo> _playerInfoCache = <int, SessionPlayerInfo>{};

/// 进行中的拉取（uin → future）：同一玩家并发打开时复用同一请求。
final Map<int, Future<SessionPlayerInfo>> _playerInfoPending =
    <int, Future<SessionPlayerInfo>>{};

/// 取玩家信息：命中缓存 → 复用进行中的请求 → 新请求。
Future<SessionPlayerInfo> playerInfoOf(WidgetRef ref, int uin) {
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
    final tid = homepageTitleId(home);
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

/// 与指定好友的默契度。
///
/// 用**我自己的**拍档目录（`get_list` 对每个好友都会返回 `tacitnum`，
/// 非拍档是 `lab == 0`），而不是对方主页的 `partner` 模块 —— 那是**他**的拍档，
/// 不是我和他的默契度。
int _tacitnumFor(WidgetRef ref, int uin) {
  final directory =
      ref.watch(partnerDirectoryProvider).asData?.value ??
      PartnerDirectory.empty;
  return directory.tacitOf(uin);
}

/// 信息卡头部：头像（含头像框）+ 昵称 + 迷你号。
class PlayerInfoHeader extends StatelessWidget {
  final int uin;
  final String name;
  final String? avatarUrl;
  final int? headType;
  final int? headId;
  final int? headFrameId;

  /// 头像半径（底部弹窗 40 / 浮窗 32）。
  final double radius;

  /// 是否在昵称区下方预留一行（底部弹窗的称号占位间距）。
  final bool reserveTitleLine;

  const PlayerInfoHeader({
    super.key,
    required this.uin,
    required this.name,
    this.avatarUrl,
    this.headType,
    this.headId,
    this.headFrameId,
    this.radius = 40,
    this.reserveTitleLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        AvatarView(
          avatarUrl: avatarUrl,
          name: name,
          radius: radius,
          headType: headType,
          headId: headId,
          frameId: headFrameId,
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichTextView(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Uin: $uin',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (reserveTitleLine) const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ],
    );
  }
}

/// 信息卡资料区：等级 / 默契度 / 冒险家 / 称号 + 勋章行。
///
/// 命中缓存（[playerInfoOf]）时不重新请求。
class PlayerInfoStats extends StatelessWidget {
  final WidgetRef ref;
  final int uin;

  const PlayerInfoStats({super.key, required this.ref, required this.uin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tacit = _tacitnumFor(ref, uin);
    return FutureBuilder<SessionPlayerInfo>(
      future: playerInfoOf(ref, uin),
      builder: (context, snap) {
        final info = snap.data ?? SessionPlayerInfo.empty;
        final adv = info.score == null
            ? '--'
            : '${info.score!['name'] ?? ''} ${info.score!['level'] ?? ''}'.trim();
        final medals = homepageMedals(info.home);
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
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.4,
                  ),
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
    );
  }
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
class PlayerCircleAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 激活态（如已置顶）用主题色高亮。
  final bool highlighted;

  const PlayerCircleAction({
    super.key,
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
