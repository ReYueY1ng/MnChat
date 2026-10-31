// LruTtlCache 的行为测试：淘汰顺序、命中刷新、注入时钟下的 TTL 结算。
//
// 不用真实时间：时钟是一个可推进的变量，因此没有任何 sleep / 等待。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/utils/lru_cache.dart';

void main() {
  group('LruTtlCache', () {
    test('超过容量时淘汰最久未使用的条目', () {
      final cache = LruTtlCache<String, int>(
        maxEntries: 2,
        ttl: const Duration(minutes: 5),
      );

      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.length, 2);

      cache.put('c', 3);

      expect(cache.get('a'), isNull, reason: 'a 最久未使用，应被淘汰');
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
      expect(cache.length, 2);
    });

    test('get 命中会刷新 LRU 位置', () {
      final cache = LruTtlCache<String, int>(
        maxEntries: 2,
        ttl: const Duration(minutes: 5),
      );

      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.get('a'), 1, reason: '访问 a，a 变成最近使用');

      cache.put('c', 3);

      expect(cache.get('a'), 1);
      expect(cache.get('b'), isNull, reason: 'b 变为最久未使用');
    });

    test('put 同一 key 覆盖值并刷新位置', () {
      final cache = LruTtlCache<String, int>(
        maxEntries: 2,
        ttl: const Duration(minutes: 5),
      );

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('a', 10);
      cache.put('c', 3);

      expect(cache.get('a'), 10);
      expect(cache.get('b'), isNull);
      expect(cache.length, 2);
    });

    test('TTL 到期后 get 返回 null 并移除条目', () {
      var now = DateTime(2026, 1, 1, 12);
      final cache = LruTtlCache<String, int>(
        maxEntries: 8,
        ttl: const Duration(seconds: 30),
        now: () => now,
      );

      cache.put('k', 1);
      now = now.add(const Duration(seconds: 29));
      expect(cache.get('k'), 1, reason: '未到期应命中');

      now = now.add(const Duration(seconds: 1));
      expect(cache.get('k'), isNull, reason: '正好到 ttl 视为过期');
      expect(cache.length, 0, reason: '过期条目在 get 时被删除');
    });

    test('put 同一 key 会重置 TTL', () {
      var now = DateTime(2026, 1, 1, 12);
      final cache = LruTtlCache<String, int>(
        maxEntries: 8,
        ttl: const Duration(seconds: 30),
        now: () => now,
      );

      cache.put('k', 1);
      now = now.add(const Duration(seconds: 20));
      cache.put('k', 2);
      now = now.add(const Duration(seconds: 20));

      expect(cache.get('k'), 2, reason: '从第二次写入起算，尚未过期');
    });

    test('remove / clear 与 length', () {
      final cache = LruTtlCache<String, int>(
        maxEntries: 8,
        ttl: const Duration(minutes: 5),
      );

      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.length, 2);

      expect(cache.remove('a'), isTrue);
      expect(cache.remove('a'), isFalse);
      expect(cache.length, 1);
      expect(cache.get('a'), isNull);

      cache.clear();
      expect(cache.length, 0);
      expect(cache.get('b'), isNull);
    });
  });
}
