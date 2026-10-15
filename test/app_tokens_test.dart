import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/ui/theme/app_tokens.dart';

/// `app_tokens.dart` 里两个纯函数的响应式回归。
///
/// - [usesRailLayout]：主壳与会话列表**共用**的侧栏判定。以前会话列表自己写
///   「横屏 && ≥800」，在主壳用侧栏（桌面 ≥480、且不看方向）而它判定为「不是
///   侧栏」时，会话列表会在 AppBar 里再放一个账号入口，出现两个账号入口。
/// - [composeTextScaler]：把应用内字号**乘**在系统无障碍字号上，而不是替换。
void main() {
  /// 平台判定必须显式钉住，否则结果取决于跑测试的宿主机。
  void usePlatform(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  group('usesRailLayout', () {
    test('移动端：≥800 才出侧栏，且与屏幕方向无关', () {
      // 竖屏平板（800 宽、非横屏）也必须出侧栏 —— 老写法要求横屏，会判错。
      usePlatform(TargetPlatform.android);
      expect(usesRailLayout(800), isTrue);
      expect(usesRailLayout(799), isFalse);
      expect(usesRailLayout(412), isFalse);
    });

    test('桌面端：≥480 就出侧栏，窄而高的窗口不退回底部栏', () {
      usePlatform(TargetPlatform.linux);
      expect(usesRailLayout(480), isTrue);
      expect(usesRailLayout(479), isFalse);
      expect(usesRailLayout(1000), isTrue);
    });
  });

  group('composeTextScaler', () {
    test('应用倍率 1.0 时原样返回系统 scaler（不额外包装）', () {
      const system = TextScaler.linear(1.5);
      expect(identical(composeTextScaler(system, 1.0), system), isTrue);
    });

    test('与系统字号相乘：系统 1.5x + 应用 1.2x → 1.8x', () {
      final scaler = composeTextScaler(const TextScaler.linear(1.5), 1.2);
      expect(scaler.scale(10), closeTo(18, 0.001));
      expect(scaler.scale(20), closeTo(36, 0.001));
    });

    test('系统未放大时等于应用倍率（chatFontScale 单独生效）', () {
      final scaler = composeTextScaler(TextScaler.noScaling, 1.6);
      expect(scaler.scale(10), closeTo(16, 0.001));
    });

    test('clamp 仍可用（继承 TextScaler 的实现）', () {
      final scaler = composeTextScaler(
        const TextScaler.linear(1.5),
        1.2,
      ).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.4);
      expect(scaler.scale(10), closeTo(14, 0.001));
    });
  });
}
