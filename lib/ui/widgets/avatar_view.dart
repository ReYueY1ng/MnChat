import 'package:flutter/material.dart';

import '../../core/models/messages.dart';

/// 会话/用户头像。
/// 渲染时用 ClipOval + Image.network，加载失败/加载中显示不透明的首字占位
/// （避免 CircleAvatar.foregroundImage 的半透明叠加问题）。
class AvatarView extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final ChatSessionType? type;
  final double radius;
  final IconData fallbackIcon;

  const AvatarView({
    super.key,
    this.avatarUrl,
    required this.name,
    this.type,
    this.radius = 24,
    this.fallbackIcon = Icons.person,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urlText = avatarUrl;
    final isGroup = type == ChatSessionType.group;

    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isGroup
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: name.isNotEmpty
          ? Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: radius * 0.8,
                fontWeight: FontWeight.w600,
                color: isGroup
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.onPrimaryContainer,
              ),
            )
          : Icon(
              isGroup ? Icons.group : fallbackIcon,
              size: radius,
              color: isGroup
                  ? theme.colorScheme.onTertiaryContainer
                  : theme.colorScheme.onPrimaryContainer,
            ),
    );

    if (urlText == null || urlText.isEmpty) return fallback;

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            Image.network(
              urlText,
              fit: BoxFit.cover,
              // 加载中：先不显示半透明图像层，避免闪烁/半透明
              frameBuilder: (context, child, frame, wasSync) {
                if (frame == null) return const SizedBox.shrink();
                return child;
              },
              // 加载失败：显示底层首字占位（不透明）
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}