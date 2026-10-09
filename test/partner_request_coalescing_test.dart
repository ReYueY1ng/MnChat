// 拍档系列接口的「单飞 + 短 TTL」缓存测试。
//
// 背景（线上实测）：同一账号连发同一接口，第二条会回 `code=9`（网关排队）。
// 所以等级 / 大会员 / 本人拍档列表都要做到「并发只发一次、短时间内复用」。
// 断言全部基于请求次数（确定性），不依赖任何 sleep。
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/partner.dart';
import 'package:mnchat/core/services/request_errors.dart' show RequestErrorBus;

/// 固定响应体 + 记录请求的适配器（离线）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);
  final String body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _levelsBody =
    '{["code"]=0,["data"]={[1]={["uin"]=1,["level"]=5},'
    '[2]={["uin"]=2,["level"]=3}}}';
const String _vipBody =
    '{["code"]=0,["tvip_info"]={["1"]=1767225600}}';
const String _partnerListBody =
    '{["code"]=0,["data"]={[1]={["bestUin"]=273640665,["tacitnum"]=1}}}';

PartnerClient _client(
  _StubAdapter adapter, {
  Duration listCacheTtl = const Duration(seconds: 5),
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return PartnerClient(
    uin: 279630451,
    s2: 's2',
    s2t: 's2t',
    dio: dio,
    baseUrl: 'https://shequ.mini1.cn:8081',
    retryBackoff: const <Duration>[Duration.zero],
    listCacheTtl: listCacheTtl,
  );
}

void main() {
  setUp(RequestErrorBus.instance.clear);
  tearDown(RequestErrorBus.instance.clear);

  group('getPlatformLevels', () {
    test('并发同一批 uin 只发一次；TTL 内重复调用命中缓存', () async {
      final adapter = _StubAdapter(_levelsBody);
      final client = _client(adapter);

      final results = await Future.wait(<Future<Map<int, int>>>[
        client.getPlatformLevels(const <int>[1, 2]),
        client.getPlatformLevels(const <int>[2, 1]), // 顺序无关，同一 key
      ]);
      expect(results.first, <int, int>{1: 5, 2: 3});
      expect(results.last, results.first);
      expect(adapter.requests, hasLength(1));

      await client.getPlatformLevels(const <int>[1, 2]);
      expect(adapter.requests, hasLength(1), reason: 'TTL 内不应再打网络');
    });

    test('业务失败（code=9）不缓存：下次调用会真的重试', () async {
      final adapter = _StubAdapter('{["code"]=9,["msg"]=""}');
      final client = _client(adapter);

      expect(await client.getPlatformLevels(const <int>[1]), isEmpty);
      expect(await client.getPlatformLevels(const <int>[1]), isEmpty);
      expect(adapter.requests, hasLength(2));
      expect(RequestErrorBus.instance.failures.value.single.label, '平台等级');
    });

    test('空 uin 列表不发请求', () async {
      final adapter = _StubAdapter(_levelsBody);
      expect(await _client(adapter).getPlatformLevels(const <int>[]), isEmpty);
      expect(adapter.requests, isEmpty);
    });
  });

  group('getVipExpiry', () {
    test('并发只发一次；TTL 内重复调用命中缓存', () async {
      final adapter = _StubAdapter(_vipBody);
      final client = _client(adapter);

      final results = await Future.wait(<Future<Map<int, int>>>[
        client.getVipExpiry(const <int>[1]),
        client.getVipExpiry(const <int>[1]),
      ]);
      expect(results.first, <int, int>{1: 1767225600});
      expect(adapter.requests, hasLength(1));

      await client.getVipExpiry(const <int>[1]);
      expect(adapter.requests, hasLength(1));
    });
  });

  group('getPartnerList 与等级/大会员共用同一套缓存语义', () {
    test('本人列表：TTL 内复用；TTL 归零后每次都打', () async {
      final cached = _StubAdapter(_partnerListBody);
      final client = _client(cached);
      await client.getPartnerList();
      await client.getPartnerList();
      expect(cached.requests, hasLength(1));

      final uncached = _StubAdapter(_partnerListBody);
      final client2 = _client(uncached, listCacheTtl: Duration.zero);
      await client2.getPartnerList();
      await client2.getPartnerList();
      expect(uncached.requests, hasLength(2));
    });
  });
}
