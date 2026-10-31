/// 通用的「LRU + TTL」进程内缓存。
///
/// 之前各模块各写一份：`image_disk_cache` 的内存层自己维护 Map + 重新插入做
/// LRU，`config_text_cache` 直接用一个无上限的 Map。这里收敛成一份实现：
/// - 容量按条目数封顶，插入超限时淘汰**最久未使用**的条目；
/// - 每条记录有独立的写入时间，[get] 时超过 [ttl] 即视为未命中并删除；
/// - 时间来源可注入（[now]），测试用假时钟即可确定性验证过期。
///
/// `get` 命中会把条目重新插到队尾（= 最近使用），所以命中本身也影响淘汰顺序。
/// 过期只在 `get` 时结算：没有访问的过期条目会占用容量，直到被 LRU 淘汰 ——
/// 这对一个纯内存缓存是可接受的取舍，避免后台定时器把生命周期变复杂。
library;

/// 带容量上限与 TTL 的 LRU 缓存。
class LruTtlCache<K, V> {
  /// [maxEntries] 为条目数上限（必须 > 0）；[ttl] 从 [put] 写入时起算，
  /// 每次 [put] 同一 key 都会刷新时间戳；[now] 可注入假时钟。
  LruTtlCache({
    required this.maxEntries,
    required this.ttl,
    DateTime Function()? now,
  })  : assert(maxEntries > 0, 'maxEntries 必须为正数'),
        _now = now ?? DateTime.now;

  /// 条目数上限。
  final int maxEntries;

  /// 条目有效期。
  final Duration ttl;

  final DateTime Function() _now;

  /// 插入有序：队首最旧（最该淘汰），队尾最近使用。
  final Map<K, _Entry<V>> _entries = <K, _Entry<V>>{};

  /// 当前保存的条目数（含尚未被 `get` 结算的过期条目）。
  int get length => _entries.length;

  /// 读取 [key]：不存在或已过期返回 null；命中会刷新 LRU 位置。
  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (!_now().isBefore(entry.storedAt.add(ttl))) return null;
    _entries[key] = entry; // 重新插到队尾 = 最近使用
    return entry.value;
  }

  /// 写入 / 覆盖 [key]；超限时从队首淘汰最久未使用的条目。
  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = _Entry<V>(value, _now());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 删除单个条目；返回是否确实存在。
  bool remove(K key) => _entries.remove(key) != null;

  /// 清空全部条目。
  void clear() => _entries.clear();
}

/// 一条缓存记录：值 + 写入时刻。
class _Entry<V> {
  const _Entry(this.value, this.storedAt);

  final V value;
  final DateTime storedAt;
}
