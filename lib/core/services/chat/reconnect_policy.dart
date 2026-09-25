import 'dart:math';

/// 聊天长连接重连退避策略：指数增长 + 全抖动（full jitter）。
///
/// 设计目标：
/// - 首次重连尽快（[base] 内），避免掉线后长时间静默；
/// - 连续失败时按 [factor] 指数放大，最大不超过 [cap]；
/// - 每次延时叠加随机抖动（`random() * computed`），防止大量客户端同时掉线
///   后「惊群」式同时重连；
/// - 延时恒 `> Duration.zero`，避免 0 延时造成的热重连循环。
///
/// 随机源经构造函数注入（[random]），默认使用共享的 [Random]；
/// 测试可注入固定值（如 `() => 1.0`）或带种子的 [Random] 使输出完全可预测。
///
/// 纯逻辑、无副作用，仅依赖 `dart:math`。
class ReconnectPolicy {
  /// 首次重连（attempt 0）的基础延时。
  final Duration base;

  /// 指数放大因子（每次失败后 computed 乘以此值）。
  final double factor;

  /// 延时上限，抖动前后均不超过。
  final Duration cap;

  /// 抖动随机源：返回 `[0, 1)` 的 double。
  final double Function() _random;

  static final Random _defaultRandom = Random();

  int _attempt = 0;

  /// [random] 缺省为进程内共享的 [Random]。
  ReconnectPolicy({
    this.base = const Duration(seconds: 1),
    this.factor = 2.0,
    this.cap = const Duration(seconds: 30),
    double Function()? random,
  }) : _random = random ?? _defaultRandom.nextDouble;

  /// 当前已连续尝试次数（初始 0）。成功连接后应调用 [reset]。
  int get attempt => _attempt;

  /// 计算并返回下一次重连延时，同时把内部 attempt 自增。
  ///
  /// 公式：`computed = min(cap, base * factor^attempt)`；
  ///       返回 `clamp(round(random() * computed), 1ms, cap)`（full jitter）。
  Duration next() {
    final delay = computeDelay(_attempt);
    _attempt++;
    return delay;
  }

  /// 计算第 [attempt] 次（0 基）重连的抖动后延时，不改变内部状态。
  ///
  /// 供测试与只读预览使用；[next] 内部亦走此路径。
  Duration computeDelay(int attempt) {
    final capMs = cap.inMilliseconds;
    final baseMs = base.inMilliseconds;
    var computedMs = baseMs * pow(factor, attempt);
    if (computedMs.isNaN || computedMs.isInfinite || computedMs > capMs) {
      computedMs = capMs.toDouble();
    }
    final jittered = (_random() * computedMs).round();
    // 下界 1ms 保证 `> Duration.zero`；上界 cap 保证不越限。
    final clamped = jittered.clamp(1, capMs).toInt();
    return Duration(milliseconds: clamped);
  }

  /// 连接成功后重置退避（回到 attempt 0）。
  void reset() => _attempt = 0;
}
