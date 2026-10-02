/// gateway.dart 的解码 / 取值路径测试。
///
/// URL 构造（`buildFriendRequestUrl` / `buildGroupUrl` / `buildMiniwParamMd5Url`）
/// 已由 `test/miniw_protocol_test.dart` 覆盖，这里只补它没碰的两件事：
///
/// 1. **响应体解码失败不再静默**：既不是 JSON 也不是 LuaTable 的 body 以前被
///    `decodeGatewayResponse` 吞成 `{}`，调用方只看到「空数据」。现在要上报。
/// 2. **dio 已经解好 JSON 时不炸**：`resp.data as String?` 会在服务端返回
///    `application/json` 时抛未捕获的 CastError。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/gateway.dart'
    show GatewayClient, decodeGatewayResponse;
import 'package:mnchat/core/services/request_errors.dart'
    show RequestErrorBus, RequestFailure;

/// 固定响应体 + 指定 content-type 的 Dio 适配器（离线，不发真实请求）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.contentType = 'text/plain'});

  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _url =
    'https://shequ.mini1.cn:8081/server/friend?cmd=query_friend_list';

/// 当前总线上的失败记录。
List<RequestFailure> reported() => RequestErrorBus.instance.failures.value;

void main() {
  setUp(RequestErrorBus.instance.clear);
  tearDown(RequestErrorBus.instance.clear);

  group('decodeGatewayResponse', () {
    test('合法 JSON → Map，不上报', () {
      final decoded = decodeGatewayResponse('{"code":0,"data":{"a":1}}');
      expect(decoded, isA<Map>());
      expect(reported(), isEmpty);
    });

    test('LuaTable 字面量 → Map，不上报', () {
      final decoded = decodeGatewayResponse('{["code"]=0,["msg"]=""}');
      expect(decoded, isA<Map>());
      expect(reported(), isEmpty);
    });

    test('空响应体按 {} 处理且不算失败（变更类接口成功时 200 无 body）', () {
      expect(decodeGatewayResponse(''), isEmpty);
      expect(decodeGatewayResponse('   \n\t '), isEmpty);
      expect(reported(), isEmpty);
    });

    test('既非 JSON 也非 LuaTable → 上报解析失败，仍返回 {} 不抛', () {
      final decoded = decodeGatewayResponse(
        '<!DOCTYPE html><html>502 Bad Gateway</html>',
        url: _url,
      );

      expect(decoded, isEmpty);
      final f = reported().single;
      expect(f.label, 'friend.query_friend_list');
      expect(f.code, isNull);
      expect(f.message, contains('既非 JSON 也非 LuaTable'));
      expect(f.endpoint, _url);
    });

    test('不带 url 时用「响应解析」占位，且不拼出可能泄漏的地址', () {
      decodeGatewayResponse('garbage');
      final f = reported().single;
      expect(f.label, '响应解析');
      expect(f.endpoint, isEmpty);
      expect(f.summary, contains('网络异常'));
    });
  });

  group('GatewayClient 解码路径', () {
    GatewayClient client(_StubAdapter adapter) =>
        GatewayClient(dio: Dio()..httpClientAdapter = adapter);

    test('GET：响应体解析失败 → 空表 + 上报，不再静默降级', () async {
      final data = await client(_StubAdapter('<html>502</html>')).get(_url);

      expect(data, isEmpty);
      expect(reported().single.label, 'friend.query_friend_list');
    });

    test('POST：解析失败同样上报', () async {
      final data =
          await client(_StubAdapter('not a json nor lua table')).post(_url);

      expect(data, isEmpty);
      expect(reported(), hasLength(1));
    });

    test('dio 已解成 Map（application/json）时不抛 CastError', () async {
      final gw = client(_StubAdapter(
        '{"code":0,"data":{"n":7}}',
        contentType: 'application/json',
      ));

      final data = await gw.get(_url);

      expect(data['code'], 0);
      expect((data['data']! as Map<Object?, Object?>)['n'], 7);
      expect(reported(), isEmpty);
    });

    test('业务码非 0 → 带上服务端码上报', () async {
      await client(_StubAdapter('{"code":9}')).get(_url);

      final f = reported().single;
      expect(f.code, 9);
      expect(f.summary, contains('NO_ROUTE'));
    });

    test('解析失败与业务码失败是两条独立记录', () async {
      await client(_StubAdapter('garbage')).get(_url);
      await client(_StubAdapter('{"code":9}')).get(_url);

      expect(reported(), hasLength(2));
      expect(reported().map((f) => f.code), containsAll(<Object?>[null, 9]));
    });

    test('正常响应不产生任何记录', () async {
      await client(_StubAdapter('{"code":0}')).get(_url);
      await client(_StubAdapter('{["code"]=0}')).post(_url);
      expect(reported(), isEmpty);
    });
  });
}
