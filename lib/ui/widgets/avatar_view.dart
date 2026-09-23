import 'package:flutter/material.dart';

import '../../core/models/messages.dart';
import '../../core/models/nickname.dart' show plainNickname;
import '../../core/models/skin_head_catalog.dart' show headIconAsset;
import 'head_frame.dart';
import '../../core/services/image_disk_cache.dart';

/// 头像本体盒子（始终为 `radius * 2`，有框/无框一致）的测试定位 Key。
const Key avatarViewAvatarBoxKey = Key('avatarViewAvatarBox');

/// 会话/用户头像。
/// 渲染时用 ClipOval + 本地头像图标 / Image.network，加载失败/加载中显示
/// 不透明的首字占位（避免 CircleAvatar.foregroundImage 的半透明叠加问题）。
class AvatarView extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final ChatSessionType? type;
  final double radius;
  final IconData fallbackIcon;
  final int? frameId;

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）；有本地图标时优先于网络头像。
  final int? headType;
  final int? headId;

  const AvatarView({
    super.key,
    this.avatarUrl,
    required this.name,
    this.type,
    this.radius = 24,
    this.fallbackIcon = Icons.person,
    this.frameId,
    this.headType,
    this.headId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urlText = avatarUrl;
    final isGroup = type == ChatSessionType.group;
    // 头像本体始终保持原尺寸 radius * 2，不因头像框而缩小；需要放大的是外层
    // 槽位：框图案铺满 128×128 画布、透明开口仅约 0.664，因此框盒至少要是
    // 头像的 1/0.76（见 [headFrameSlotSize]），外圈才能真正包围头像。
    final avatarSize = radius * 2;
    // 有框/无框统一使用同一槽位尺寸，行高不会在有框与无框用户之间跳动。
    final slotSize = headFrameSlotSize(radius);
    final framed = frameId != null && !isGroup;
    // 昵称含游戏富文本标记（如 `[i][color][b]顾念` / `<a>谢俞`）时先清洗，
    // 否则首字母会取到 `[` 或 `<`。
    final displayName = plainNickname(name);

    // 方形圆角头像（游戏内头像为圆角方形，头像框环绕其外）；
    // 圆角半径保持原始比例 radius * 0.5（即 avatarSize * 0.25）。
    final br = BorderRadius.circular(avatarSize * 0.25);

    final fallback = Container(
      width: avatarSize,
      height: avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isGroup
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.primaryContainer,
        borderRadius: br,
      ),
      child: displayName.isNotEmpty
          ? Text(
              displayName.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: avatarSize * 0.4,
                fontWeight: FontWeight.w600,
                color: isGroup
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.onPrimaryContainer,
              ),
            )
          : Icon(
              isGroup ? Icons.group : fallbackIcon,
              size: avatarSize * 0.5,
              color: isGroup
                  ? theme.colorScheme.onTertiaryContainer
                  : theme.colorScheme.onPrimaryContainer,
            ),
    );

    // 头像来源优先级：**网络头像优先，本地角色头像仅作兜底**。
    //
    // 原实现相反（角色头像本体优先于 URL）。实测真机数据：人物中心
    // （getPersonCenterHeadInfos）经常整体不返回（所有人 type/id 都是 null），
    // 于是 headType/headId 只能由 SkinID/Model 推导 —— 结果是**用推导出来的
    // 角色头像盖掉了服务端给的网络头像**（自定义头像用户尤其明显：刚进会话时
    // 还没有推导值所以显示自定义头像，资料一回来就被角色头像覆盖）。
    // 好友几乎都有 per-user 的网络头像 URL，优先用它才符合服务端事实。
    final hasUrl = urlText != null && urlText.isNotEmpty;
    final localHead = (!hasUrl && headType != null && headId != null && headId! > 0)
        ? headIconAsset(headType!, headId!)
        : null;

    final Widget? imageLayer;
    if (localHead != null) {
      // 本地头像图标是带透明背景的整头图，用 contain 避免裁切
      imageLayer = Image.asset(
        localHead,
        fit: BoxFit.contain,
        // 加载中：先不显示半透明图像层，避免闪烁/半透明
        frameBuilder: (context, child, frame, wasSync) {
          if (frame == null) return const SizedBox.shrink();
          return child;
        },
        // 加载失败：显示底层首字占位（不透明）
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else if (urlText != null && urlText.isNotEmpty) {
      imageLayer = Image(image: CachedNetworkImageProvider(urlText),
        fit: BoxFit.cover,
        // 加载中：先不显示半透明图像层，避免闪烁/半透明
        frameBuilder: (context, child, frame, wasSync) {
          if (frame == null) return const SizedBox.shrink();
          return child;
        },
        // 加载失败：显示底层首字占位（不透明）
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    } else {
      imageLayer = null;
    }

    final Widget avatar = imageLayer == null
        ? fallback
        : ClipRRect(
            borderRadius: br,
            child: SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: Stack(
                fit: StackFit.expand,
                children: [fallback, imageLayer],
              ),
            ),
          );

    // 群组/无框用户不叠加头像框；框层铺满整个槽位、不做裁剪，避免裁掉外圈装饰。
    // 外框恒为 slotSize，头像本体 radius * 2 居中：有框/无框几何完全一致。
    return SizedBox(
      width: slotSize,
      height: slotSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            key: avatarViewAvatarBoxKey,
            width: avatarSize,
            height: avatarSize,
            child: avatar,
          ),
          if (framed) HeadFrameOverlay(frameId: frameId, size: slotSize),
        ],
      ),
    );
  }
}
