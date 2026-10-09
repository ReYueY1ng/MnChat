/// 重复请求的进程内计数（观测用，**不改变任何请求行为**）。
///
/// 为什么需要它：同一个接口经常在极短时间内被发两次 —— provider 依赖的高频事件
/// 重跑、页面与浮窗同时要数据、重连补偿刷新…… 而网关是**按账号排队**的，连发的
/// 第二条可能直接回 `code=9`（NO_ROUTE）/ `code=23`（WAITTING）。所以「同一接口
/// 在 2 秒内发了几次」本身就是需要盯的健康指标。
///
/// [createDio] 的拦截器每次请求都会调 [DuplicateRequestMonitor.record]；第 2 次
/// 起回调 + 打 warn（第 2 次，之后每 10 次），并计入 [DuplicateRequestMonitor.repeats]。
library;

/// 不参与指纹的参数：这些值**每次请求都不同**（时间戳 / 一次性令牌 / 签名）。
const Set<String> kVolatileQueryKeys = <String>{
  'time',
  's2t',
  's2',
  'md5',
  'sign',
  's7',
  's7t',
  's7e',
  'auth',
  'loginauth',
  'jwt',
  'token',
  'nonce',
  'seq',
  'ts',
  'timestamp',
  'server_ts',
  '_t',
};

/// 请求指纹：`METHOD path?稳定参数`（参数按 key 排序，与书写顺序无关）。
///
/// 局限（有意为之，写在明处）：s7 包裹的接口（`miniw/bestpartner` 等）真实参数
/// 全在 `s7` 里，而 `s7` 每次都变，因此这类接口的指纹退化为 path 级别 —— 这仍然
/// 抓得到要盯的形态：「同一接口在窗口内连发」。
String requestFingerprint(String method, Uri uri) {
  final keys = uri.queryParametersAll.keys.toList()..sort();
  final stable = <String>[];
  for (final k in keys) {
    if (kVolatileQueryKeys.contains(k)) continue;
    final v = uri.queryParametersAll[k]!;
    stable.add(v.length == 1 ? '$k=${v.single}' : '$k=${v.join('|')}');
  }
  final query = stable.isEmpty ? '' : '?${stable.join('&')}';
  return '${method.toUpperCase()} ${uri.path}$query';
}

/// 同一指纹在 [window] 内的出现次数统计。
class DuplicateRequestMonitor {
  DuplicateRequestMonitor({
    this.window = const Duration(seconds: 2),
    DateTime Function()? clock,
    this.onDuplicate,
  }) : _now = clock ?? DateTime.now;

  /// 全局实例（[createDio] 的拦截器写它）；测试可替换或 [reset]。
  static DuplicateRequestMonitor instance = DuplicateRequestMonitor();

  /// 指纹表上限。这是观测用的内存表，长跑不能无限增长（指纹含 uin 集合，
  /// 取值空间不封顶）。超过就丢掉窗口外的旧记录，仍超则整体清空。
  static const int maxEntries = 512;

  /// 计数窗口：超过这个间隔没再出现，就重新从 1 计数。
  final Duration window;

  final DateTime Function() _now;

  /// 第 2 次及以后每次重复都会调用（[count] = 窗口内累计次数）。
  final void Function(String fingerprint, int count)? onDuplicate;

  final Map<String, DateTime> _lastSeen = <String, DateTime>{};
  final Map<String, int> _counts = <String, int>{};

  /// 记录一次请求，返回「窗口内第几次」（首次 = 1）。
  int record(String fingerprint) {
    final now = _now();
    _evictIfNeeded(now);
    final last = _lastSeen[fingerprint];
    final repeated = last != null && now.difference(last) < window;
    final count = repeated ? (_counts[fingerprint] ?? 1) + 1 : 1;
    _lastSeen[fingerprint] = now;
    if (repeated) {
      _counts[fingerprint] = count;
      onDuplicate?.call(fingerprint, count);
    } else {
      _counts.remove(fingerprint);
    }
    return count;
  }

  /// 正在跟踪的指纹数（有上限，见 [maxEntries]）。
  int get trackedKeys => _lastSeen.length;

  void _evictIfNeeded(DateTime now) {
    if (_lastSeen.length <= maxEntries) return;
    _lastSeen.removeWhere((_, at) => now.difference(at) >= window);
    _counts.removeWhere((key, _) => !_lastSeen.containsKey(key));
    if (_lastSeen.length > maxEntries) {
      _lastSeen.clear();
      _counts.clear();
    }
  }

  /// 指纹 → 窗口内累计重复次数（只含发生过重复的指纹）。
  Map<String, int> get repeats => Map<String, int>.unmodifiable(_counts);

  /// 清空统计。
  void reset() {
    _lastSeen.clear();
    _counts.clear();
  }
}
