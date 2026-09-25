// 重连退避策略测试：纯逻辑、确定性 —— 无 Timer / 无 Flutter / 无网络。
//
// 关键可测性设计：随机源经构造函数注入。测试要么注入固定值（如 `() => 1.0`）
// 使退避呈确定性指数增长，要么注入带种子的 `Random` 使抖动序列完全可预测。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/chat/reconnect_policy.dart';

void main() {
  group('ReconnectPolicy', () {
    test('attempt 0 的延时落在 [0, base] 内（已应用 jitter）', () {
      final p = ReconnectPolicy(random: Random(42).nextDouble);
      final d = p.next();
      expect(d, greaterThanOrEqualTo(Duration.zero));
      expect(d, lessThanOrEqualTo(const Duration(milliseconds: 1000)));
    });

    test('延时随 attempt 非递减增长并最终饱和于 cap', () {
      // 注入 1.0 的抖动（等价于取满 computed），使序列确定性指数增长。
      final p = ReconnectPolicy(random: () => 1.0);
      var prev = Duration.zero;
      final seen = <Duration>[];
      for (var i = 0; i < 10; i++) {
        final d = p.next();
        expect(
          d,
          greaterThanOrEqualTo(prev),
          reason: 'attempt $i 的延时不应小于上一次',
        );
        prev = d;
        seen.add(d);
      }
      // 1s → 2 → 4 → 8 → 16 → 30 → 30 ...（饱和）
      expect(seen.take(6).toList(), [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
        const Duration(seconds: 16),
        const Duration(seconds: 30),
      ]);
      expect(seen.last, const Duration(seconds: 30));
    });

    test('延时永不超过 cap（即便取满抖动）', () {
      final p = ReconnectPolicy(random: () => 1.0);
      for (var i = 0; i < 100; i++) {
        expect(p.next(), lessThanOrEqualTo(const Duration(seconds: 30)));
      }
    });

    test('延时恒 > 0（jitter 为 0 也不会产生热重连）', () {
      final p = ReconnectPolicy(random: () => 0.0);
      for (var i = 0; i < 50; i++) {
        expect(p.next(), greaterThan(Duration.zero));
      }
    });

    test('reset() 回到 attempt 0', () {
      final p = ReconnectPolicy(random: () => 1.0);
      p.next();
      p.next();
      p.next();
      expect(p.attempt, 3);

      p.reset();
      expect(p.attempt, 0);
      // attempt 0 → base 秒（取满抖动）
      expect(p.next(), const Duration(seconds: 1));
    });

    test('注入带种子 Random 后输出完全可预测', () {
      final p = ReconnectPolicy(random: Random(123).nextDouble);
      final r = Random(123);
      const capMs = 30000;
      for (var attempt = 0; attempt < 6; attempt++) {
        var computedMs = 1000 * (1 << attempt);
        if (computedMs > capMs) computedMs = capMs;
        final expectedMs = (r.nextDouble() * computedMs).round().clamp(
          1,
          capMs,
        );
        expect(
          p.next(),
          Duration(milliseconds: expectedMs),
          reason: 'attempt $attempt 应为确定性抖动结果',
        );
      }
    });

    test('自定义 base / factor / cap 生效', () {
      final p = ReconnectPolicy(
        base: const Duration(milliseconds: 500),
        factor: 3,
        cap: const Duration(seconds: 5),
        random: () => 1.0,
      );
      expect(p.next(), const Duration(milliseconds: 500));
      expect(p.next(), const Duration(milliseconds: 1500));
      expect(p.next(), const Duration(milliseconds: 4500));
      expect(p.next(), const Duration(seconds: 5)); // 饱和
    });

    test('极大 attempt 不会溢出（退化为 cap）', () {
      final p = ReconnectPolicy(random: () => 1.0);
      final d = p.computeDelay(1000);
      expect(d, const Duration(seconds: 30));
    });
  });
}
