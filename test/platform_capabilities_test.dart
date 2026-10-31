// 平台能力矩阵：Windows 只支持前台聊天（无后台通知/托盘），Linux/Android 全量。
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/platform_capabilities.dart';

void main() {
  test('Linux 与 Android 支持后台通知；Linux 额外有托盘', () {
    final linux = PlatformCapabilities.forTarget(TargetPlatform.linux);
    expect(linux.backgroundNotifications, isTrue);
    expect(linux.tray, isTrue);
    expect(linux.limitation, isNull);

    final android = PlatformCapabilities.forTarget(TargetPlatform.android);
    expect(android.backgroundNotifications, isTrue);
    expect(android.tray, isFalse);
  });

  test('Windows 明确降级为仅前台，并给出提示文案', () {
    final win = PlatformCapabilities.forTarget(TargetPlatform.windows);
    expect(win.backgroundNotifications, isFalse);
    expect(win.tray, isFalse);
    expect(win.limitation, contains('Windows'));
    expect(win.limitation, contains('后台通知'));
  });

  test('未支持平台同样不声称有通知', () {
    for (final p in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      final c = PlatformCapabilities.forTarget(p);
      expect(c.backgroundNotifications, isFalse);
      expect(c.limitation, isNotNull);
    }
  });
}
