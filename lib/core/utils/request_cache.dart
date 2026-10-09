/// 进程内「单飞 + 短 TTL」请求缓存。
///
/// 解决的问题：同一份数据被重复请求。MNChat 里有两类来源 ——
/// provider 因高频事件重跑（每条消息 / 每次标记已读 / 每次重连刷新都会发一份
/// **新的**会话快照，依赖它的聚合 provider 就跟着重跑），以及同一界面上多个
/// widget 同时要同一份数据。
///
/// 对 `miniw/*` 这类接口，重复请求不只是浪费流量：网关是**按账号排队**的，
/// 连发的第二条会回 `code=9/23`（见 `partner.dart` 的
/// `kBestpartnerRetryBackoff` 注释），所以重发还会把本来能拿到的数据换成失败。
///
/// 语义：
/// - 同 key 的并发调用只发一次请求（后来者复用同一个 Future）；
/// - 成功后按 [ttl] 复用；[cacheable] 返回 false 的结果不缓存 —— 这些接口的
///   解析器在业务失败时也返回空值，不能用空值当缓存。
/// - 失败（抛异常）不缓存，且立刻释放在途占位，下一次调用可以真的重试。
library;

/// 单飞 + TTL 的进程内缓存；[clock] 可注入，便于确定性测试。
class RequestCache<T> {
  RequestCache({
    this.ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// 缓存条目上限：键里含 uin 集合（取值空间不封顶），长跑不能无限增长。
  /// 超限时先丢掉已过期条目，仍超则整体清空（丢掉只是多一次请求）。
  static const int maxEntries = 256;

  /// 缓存有效期，从请求成功那一刻算起。
  final Duration ttl;

  final DateTime Function() _now;

  final Map<String, T> _values = <String, T>{};
  final Map<String, DateTime> _storedAt = <String, DateTime>{};
  final Map<String, Future<T>> _inFlight = <String, Future<T>>{};

  /// 当前缓存中的键数量（测试 / 调试用）。
  int get cachedKeys => _values.length;

  /// 当前在途请求的键数量（测试 / 调试用）。
  int get inFlightKeys => _inFlight.length;

  /// 取 [key] 的缓存；只在「无缓存 且 无同 key 在途请求」时才调 [fetch]。
  Future<T> run(
    String key,
    Future<T> Function() fetch, {
    bool Function(T value)? cacheable,
  }) {
    _evictIfNeeded();
    final at = _storedAt[key];
    if (at != null &&
        _values.containsKey(key) &&
        _now().difference(at) < ttl) {
      return Future<T>.value(_values[key] as T);
    }
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    final future = fetch().then((value) {
      if (cacheable == null || cacheable(value)) {
        _values[key] = value;
        _storedAt[key] = _now();
      }
      return value;
    });
    // 清理必须写成**语句块**：写成 `() => _inFlight.remove(key)` 会让
    // whenComplete 去等它返回的那个 Future（自等待死锁，同 emoji_store.dart 的坑）。
    final tracked = future.whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = tracked;
    return tracked;
  }

  /// 丢弃缓存；[key] 为 null 时全清。不影响已经发出的在途请求。
  void invalidate([String? key]) {
    if (key == null) {
      _values.clear();
      _storedAt.clear();
      return;
    }
    _values.remove(key);
    _storedAt.remove(key);
  }

  void _evictIfNeeded() {
    if (_values.length <= maxEntries) return;
    final now = _now();
    final expired = <String>[
      for (final e in _storedAt.entries)
        if (now.difference(e.value) >= ttl) e.key,
    ];
    for (final key in expired) {
      _values.remove(key);
      _storedAt.remove(key);
    }
    if (_values.length > maxEntries) {
      _values.clear();
      _storedAt.clear();
    }
  }
}
