// 重复请求计数（观测）的测试。
//
// 指纹用真实 URL 形状（miniw 的签名参数每次都变，必须被排除掉），计数窗口用
// 注入时钟推进 —— 没有任何等待真实时间。
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/net/duplicate_request_monitor.dart';
import 'package:mnchat/core/net/http_factory.dart' show createDio;

/// 固定响应体、记录请求的适配器（离线）。
class _StubAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"code":0}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('requestFingerprint', () {
    test('排除每次都变的参数（time/s2t/md5/server_ts），并与顺序无关', () {
      final a = requestFingerprint(
        'get',
        Uri.parse(
          'https://h/miniw/upgrade?act=get_level_info_batch&op_uin_list=1,2'
          '&uin=9&time=111&s2t=x&md5=aaa&server_ts=111',
        ),
      );
      final b = requestFingerprint(
        'GET',
        Uri.parse(
          'https://h/miniw/upgrade?server_ts=222&md5=bbb&s2t=y&time=999'
          '&uin=9&op_uin_list=1,2&act=get_level_info_batch',
        ),
      );
      expect(a, b);
      expect(a, 'GET /miniw/upgrade?act=get_level_info_batch&op_uin_list=1,2&uin=9');
    });

    test('s7 包裹的接口参数不可见 → 退化为 path 级别（仍能抓「同接口连发」）', () {
      final a = requestFingerprint(
        'GET',
        Uri.parse('https://h//miniw/bestpartner?s7=AAA&s7t=12345'),
      );
      final b = requestFingerprint(
        'GET',
        Uri.parse('https://h//miniw/bestpartner?s7=BBB&s7t=67890'),
      );
      expect(a, b);
      expect(a, 'GET //miniw/bestpartner');
    });
  });

  group('DuplicateRequestMonitor', () {
    test('窗口内累计计数；超窗重新从 1 开始；重复时回调', () {
      var now = DateTime(2026, 1, 1);
      final seen = <String>[];
      final monitor = DuplicateRequestMonitor(
        window: const Duration(seconds: 2),
        clock: () => now,
        onDuplicate: (fp, n) => seen.add('$fp#$n'),
      );

      expect(monitor.record('A'), 1);
      now = now.add(const Duration(milliseconds: 500));
      expect(monitor.record('A'), 2);
      expect(monitor.record('A'), 3);
      expect(monitor.repeats['A'], 3);

      now = now.add(const Duration(seconds: 3)); // 超出窗口
      expect(monitor.record('A'), 1);
      expect(monitor.repeats.containsKey('A'), isFalse);

      expect(seen, <String>['A#2', 'A#3']);
    });

    test('不同指纹分开计数；reset 清空', () {
      final monitor = DuplicateRequestMonitor();
      monitor.record('A');
      monitor.record('B');
      monitor.record('B');
      expect(monitor.repeats.keys, <String>['B']);
      monitor.reset();
      expect(monitor.repeats, isEmpty);
    });

    test('指纹表有上限：长跑不会无限增长，清掉后仍可继续计数', () {
      final monitor = DuplicateRequestMonitor();
      for (var i = 0; i <= DuplicateRequestMonitor.maxEntries + 5; i++) {
        expect(monitor.record('FP$i'), 1);
      }
      expect(
        monitor.trackedKeys,
        lessThanOrEqualTo(DuplicateRequestMonitor.maxEntries + 1),
      );
      expect(monitor.record('again'), 1);
      expect(monitor.record('again'), 2);
    });
  });

  group('createDio 拦截器', () {
    test('同一接口连发两次 → 计入重复统计', () async {
      final monitor = DuplicateRequestMonitor();
      final previous = DuplicateRequestMonitor.instance;
      DuplicateRequestMonitor.instance = monitor;
      addTearDown(() => DuplicateRequestMonitor.instance = previous);

      final adapter = _StubAdapter();
      final dio = createDio()..httpClientAdapter = adapter;

      await dio.get(
        'https://h/miniw/upgrade?act=get_level_info_batch&op_uin_list=1&uin=9&time=1&s2t=a&md5=x',
      );
      await dio.get(
        'https://h/miniw/upgrade?act=get_level_info_batch&op_uin_list=1&uin=9&time=2&s2t=b&md5=y',
      );

      expect(adapter.requests, hasLength(2));
      expect(
        monitor.repeats['GET /miniw/upgrade?act=get_level_info_batch&op_uin_list=1&uin=9'],
        2,
      );
    });

    test('不同接口不互相计数', () async {
      final monitor = DuplicateRequestMonitor();
      final previous = DuplicateRequestMonitor.instance;
      DuplicateRequestMonitor.instance = monitor;
      addTearDown(() => DuplicateRequestMonitor.instance = previous);

      final dio = createDio()..httpClientAdapter = _StubAdapter();
      await dio.get('https://h/miniw/upgrade?act=a&uin=9&time=1');
      await dio.get('https://h/miniw/business?act=b&uin=9&time=2');
      expect(monitor.repeats, isEmpty);
    });
  });
}
