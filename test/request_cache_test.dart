// RequestCache（单飞 + TTL）的行为测试。
//
// 这些断言都是确定性事件计数（没有 sleep / 没有时间等待）：并发合并用
// Completer 卡住 fetch，TTL 用注入时钟推进。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/utils/request_cache.dart';

void main() {
  group('RequestCache', () {
    test('同 key 并发调用只 fetch 一次（共享同一个 Future）', () async {
      var calls = 0;
      final gate = Completer<void>();
      final cache = RequestCache<int>(ttl: const Duration(seconds: 5));

      Future<int> fetch() async {
        calls++;
        await gate.future;
        return 7;
      }

      final a = cache.run('k', fetch);
      final b = cache.run('k', fetch);
      expect(calls, 1, reason: '第二次进入时第一个请求还在途，必须复用');
      expect(cache.inFlightKeys, 1);

      gate.complete();
      expect(await a, 7);
      expect(await b, 7);
      expect(calls, 1);
      expect(cache.inFlightKeys, 0);
    });

    test('TTL 内复用缓存、过期后重取', () async {
      var calls = 0;
      var now = DateTime(2026, 1, 1);
      final cache = RequestCache<int>(
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );

      Future<int> fetch() async => ++calls;

      expect(await cache.run('k', fetch), 1);
      expect(await cache.run('k', fetch), 1);
      expect(calls, 1);

      now = now.add(const Duration(seconds: 6));
      expect(await cache.run('k', fetch), 2);
      expect(calls, 2);
    });

    test('不同 key 互不影响', () async {
      var calls = 0;
      final cache = RequestCache<int>(ttl: const Duration(seconds: 5));
      Future<int> fetch() async => ++calls;
      expect(await cache.run('a', fetch), 1);
      expect(await cache.run('b', fetch), 2);
      expect(await cache.run('a', fetch), 1);
      expect(calls, 2);
    });

    test('cacheable 返回 false 的结果不缓存（业务失败也返回空值时用）', () async {
      var calls = 0;
      final cache = RequestCache<int>(ttl: const Duration(seconds: 5));
      Future<int> fetch() async {
        calls++;
        return calls == 1 ? 0 : 9;
      }

      expect(await cache.run('k', fetch, cacheable: (v) => v > 0), 0);
      expect(await cache.run('k', fetch, cacheable: (v) => v > 0), 9);
      expect(calls, 2);
      expect(await cache.run('k', fetch, cacheable: (v) => v > 0), 9);
      expect(calls, 2);
    });

    test('fetch 抛异常：不缓存、释放占位、下次能真的重试', () async {
      var calls = 0;
      final cache = RequestCache<int>(ttl: const Duration(seconds: 5));
      Future<int> fetch() async {
        calls++;
        if (calls == 1) throw StateError('boom');
        return 9;
      }

      await expectLater(cache.run('k', fetch), throwsA(isA<StateError>()));
      expect(cache.inFlightKeys, 0);
      expect(cache.cachedKeys, 0);
      expect(await cache.run('k', fetch), 9);
      expect(calls, 2);
    });

    test('invalidate 丢弃缓存', () async {
      var calls = 0;
      final cache = RequestCache<int>(ttl: const Duration(seconds: 5));
      Future<int> fetch() async => ++calls;
      expect(await cache.run('k', fetch), 1);
      cache.invalidate('k');
      expect(await cache.run('k', fetch), 2);
      cache.invalidate();
      expect(await cache.run('k', fetch), 3);
    });

    test('条目超过上限时清理（长跑不会无限增长），清完仍可继续用', () async {
      var calls = 0;
      final cache = RequestCache<int>(ttl: const Duration(seconds: 5));
      Future<int> fetch() async => ++calls;

      for (var i = 0; i <= RequestCache.maxEntries + 5; i++) {
        await cache.run('k$i', fetch);
      }
      expect(
        cache.cachedKeys,
        lessThanOrEqualTo(RequestCache.maxEntries + 1),
      );

      // 被清掉的键重新拉取即可（丢缓存只是多一次请求）
      final again = await cache.run('k1', fetch);
      expect(again, greaterThan(0));
    });
  });
}
