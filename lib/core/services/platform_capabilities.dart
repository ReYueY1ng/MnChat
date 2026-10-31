/// 平台能力矩阵：把「哪些平台支持后台通知/托盘」集中成一份可测试的事实，
/// 避免 README、设置页与实现三处各说一套。
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// 某平台的聊天外围能力。
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.backgroundNotifications,
    required this.tray,
    this.limitation,
  });

  /// 退到后台后能否弹系统通知（Android 前台服务 / Linux DBus）。
  final bool backgroundNotifications;

  /// 是否有系统托盘（目前只有 Linux 的 SNI 实现）。
  final bool tray;

  /// 能力缺失时给用户看的一句话。
  final String? limitation;

  /// 按目标平台取能力（纯函数，便于单测）。
  static PlatformCapabilities forTarget(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android => const PlatformCapabilities(
          backgroundNotifications: true,
          tray: false,
        ),
        TargetPlatform.linux => const PlatformCapabilities(
          backgroundNotifications: true,
          tray: true,
        ),
        TargetPlatform.windows => const PlatformCapabilities(
          backgroundNotifications: false,
          tray: false,
          limitation: 'Windows 版目前仅支持前台聊天：没有后台通知与系统托盘。',
        ),
        TargetPlatform.macOS => const PlatformCapabilities(
          backgroundNotifications: false,
          tray: false,
          limitation: 'macOS 不是受支持的发布平台。',
        ),
        _ => const PlatformCapabilities(
          backgroundNotifications: false,
          tray: false,
          limitation: '当前平台不支持后台通知。',
        ),
      };

  /// 当前运行平台。
  static PlatformCapabilities get current => forTarget(defaultTargetPlatform);
}
