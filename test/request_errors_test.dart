import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/net/http_factory.dart' show createDio;
import 'package:mnchat/core/services/family.dart' show FamilyClient;
import 'package:mnchat/core/services/gateway.dart' show GatewayClient;
import 'package:mnchat/core/services/partner.dart';
import 'package:mnchat/core/services/profile.dart' show ProfileClient;
import 'package:mnchat/core/services/request_errors.dart';

/// 直接清空总线（不走 setUp，便于在用例中间重置）。
void clearBus() => RequestErrorBus.instance.clear();

/// 固定响应体 / 抛异常的 Dio 适配器（离线）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body) : throwMessage = null;

  _StubAdapter.throwing(this.throwMessage) : body = null;

  final String? body;
  final String? throwMessage;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final msg = throwMessage;
    if (msg != null) {
      // 用调用方自己的 options 构造异常：拦截器上报的就是这个地址。
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: msg,
      );
    }
    return ResponseBody.fromString(
      body!,
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
  setUp(RequestErrorBus.instance.clear);
  tearDown(RequestErrorBus.instance.clear);

  group('RequestErrorBus', () {
    test('上报后按最新在前保存，并给出可读摘要', () {
      final bus = RequestErrorBus.instance;
      bus.report(
        label: '拍档列表（我）',
        endpoint: 'https://shequ.mini1.cn:8081//miniw/bestpartner?s7=***&s7t=***',
        code: 9,
        message: '',
      );

      final f = bus.failures.value.single;
      expect(f.label, '拍档列表（我）');
      expect(f.code, 9);
      expect(f.count, 1);
      expect(f.summary, contains('code=9'));
      expect(f.summary, contains('NO_ROUTE'));
      expect(describeRequestCode(2), contains('UNKNOW_SERVICE'));
      expect(describeRequestCode(7012), '认证失败');
      expect(describeRequestCode(12345), '#12345');
    });

    test('同一失败重复上报只保留一条并计数（不刷屏）', () {
      final bus = RequestErrorBus.instance;
      for (var i = 0; i < 3; i++) {
        bus.report(label: '拍档列表（我）', endpoint: 'e', code: 9);
      }
      expect(bus.failures.value.length, 1);
      expect(bus.failures.value.single.count, 3);
    });

    test('不同 code / 端点分开记录，最多保留 maxEntries 条', () {
      final bus = RequestErrorBus.instance;
      bus.report(label: 'a', endpoint: 'e', code: 9);
      bus.report(label: 'a', endpoint: 'e', code: 23);
      expect(bus.failures.value.length, 2);

      for (var i = 0; i < RequestErrorBus.maxEntries + 5; i++) {
        bus.report(label: 'x$i', endpoint: 'e', code: 1);
      }
      expect(bus.failures.value.length, RequestErrorBus.maxEntries);
    });

    test('clear 清空列表', () {
      final bus = RequestErrorBus.instance;
      bus.report(label: 'a', endpoint: 'e', code: 9);
      bus.clear();
      expect(bus.failures.value, isEmpty);
    });

    test('新失败发事件、重复失败不发（吐司去重）', () async {
      final bus = RequestErrorBus.instance;
      final events = <RequestFailure>[];
      final sub = bus.stream.listen(events.add);

      bus.report(label: 'a', endpoint: 'e', code: 9);
      bus.report(label: 'a', endpoint: 'e', code: 9);
      bus.report(label: 'b', endpoint: 'e', code: 9);
      await Future<void>.delayed(Duration.zero);

      expect(events.map((f) => f.label), ['a', 'b']);
      await sub.cancel();
    });
  });

  group('createDio 拦截器', () {
    test('传输失败（超时/断网）上报为「网络请求」，地址已脱敏', () async {
      final dio = createDio();
      final adapter = _StubAdapter.throwing('timeout');
      dio.httpClientAdapter = adapter;

      await expectLater(
        dio.get('https://shequ.mini1.cn:8081//miniw/bestpartner?s7=SECRET&s7t=SIG'),
        throwsA(isA<DioException>()),
      );

      final f = RequestErrorBus.instance.failures.value.single;
      expect(f.label, '网络请求');
      expect(f.message, 'timeout');
      expect(f.endpoint, contains('s7=***'));
      expect(f.endpoint, isNot(contains('SECRET')));
    });

    test('业务码失败（HTTP 200）不经过拦截器，由 client 自己上报', () async {
      final dio = createDio();
      dio.httpClientAdapter = _StubAdapter('{["code"]=9,["msg"]=""}');
      await dio.get('https://shequ.mini1.cn:8081//miniw/bestpartner');
      expect(RequestErrorBus.instance.failures.value, isEmpty);
    });
  });

  group('labelFromUrl / reportIfFailed', () {
    test('从 URL 推标签：path 末段 + act', () {
      expect(
        labelFromUrl('https://h/miniw/family?act=get_family_list&uin=1'),
        'family.get_family_list',
      );
      expect(
        labelFromUrl('https://h/server/friend?cmd=query_friend_list'),
        'friend.query_friend_list',
      );
      expect(labelFromUrl('https://h/miniw/upgrade'), 'upgrade');
    });

    test('code / ret / result 非 0 都算失败；对象状态值不算', () {
      clearBus();
      expect(reportIfFailed('https://h/miniw/family?act=get_family_list',
          const {'code': 1, 'msg': '参数错误'}), isTrue);
      expect(
          reportIfFailed('https://h/miniw/x', const {'ret': '-1'}), isTrue);
      expect(reportIfFailed('https://h/server/friend', const {'result': 2}),
          isTrue);
      // 非失败：0 / 字符串 '0' / result 是业务对象 / 非 Map
      expect(reportIfFailed('https://h/miniw/x', const {'code': 0}), isFalse);
      expect(reportIfFailed('https://h/miniw/x', const {'ret': '0'}), isFalse);
      expect(
          reportIfFailed(
              'https://h/miniw/x', const {'result': {'list': <Object>[]}}),
          isFalse);
      expect(reportIfFailed('https://h/miniw/x', const <Object>[]), isFalse);

      expect(RequestErrorBus.instance.failures.value.length, 3);
      final f = RequestErrorBus.instance.failures.value
          .firstWhere((e) => e.label == 'x');
      expect(f.label, 'x');
      expect(f.message, '');
    });
  });

  group('业务客户端上报', () {
    test('FamilyClient（自带 helper）失败 → 上报 family.<act>', () async {
      clearBus();
      final dio = Dio()..httpClientAdapter = _StubAdapter('{["code"]=1,["msg"]="参数错误"}');
      final client = FamilyClient(
        uin: 1,
        s2: 's2',
        s2t: 's2t',
        dio: dio,
        baseUrl: 'https://shequ.mini1.cn:8081',
      );
      await client.getFamilyList();

      final f = RequestErrorBus.instance.failures.value.single;
      expect(f.label, 'family.get_family_list');
      expect(f.code, 1);
      expect(f.message, '参数错误');
    });

    test('GatewayClient（friend / group 共用）失败 → 上报', () async {
      clearBus();
      final dio = Dio()..httpClientAdapter = _StubAdapter('{"result":2}');
      final gw = GatewayClient(dio: dio);
      await gw.get('https://shequ.mini1.cn:8081/server/friend?cmd=query_friend_list');

      final f = RequestErrorBus.instance.failures.value.single;
      expect(f.label, 'friend.query_friend_list');
      expect(f.code, 2);
    });

    test('ProfileClient（多 inline 解码点）失败 → 上报 profile.<act>', () async {
      clearBus();
      final dio = Dio()..httpClientAdapter = _StubAdapter('{["code"]=1,["msg"]="参数错误"}');
      final client = ProfileClient(
        uin: 1,
        s2: 's2',
        s2t: 's2t',
        dio: dio,
        baseUrl: 'https://shequ.mini1.cn:8081',
      );
      await client.getProfileBatch3(const <int>[1]);

      final f = RequestErrorBus.instance.failures.value.single;
      expect(f.label, 'profile.getProfileBatch3');
      expect(f.code, 1);
    });

    test('成功响应不产生记录', () async {
      clearBus();
      final dio = Dio()..httpClientAdapter = _StubAdapter('{"result":0}');
      await GatewayClient(dio: dio)
          .get('https://shequ.mini1.cn:8081/server/friend?cmd=query_friend_list');
      expect(RequestErrorBus.instance.failures.value, isEmpty);
    });
  });

  group('PartnerClient 上报', () {
    PartnerClient client(_StubAdapter adapter) {
      final dio = Dio()..httpClientAdapter = adapter;
      return PartnerClient(
        uin: 279630451,
        s2: 's2',
        s2t: 's2t',
        dio: dio,
        baseUrl: 'https://shequ.mini1.cn:8081',
        retryBackoff: const <Duration>[Duration.zero],
      );
    }

    test('重试耗尽（code=9 排队）→ 上报带标签与业务码，地址脱敏', () async {
      final adapter = _StubAdapter('{["code"]=9,["msg"]=""}');
      final list = await client(adapter).getPartnerList();

      expect(list, isEmpty);
      final f = RequestErrorBus.instance.failures.value.single;
      expect(f.label, '拍档列表（我）');
      expect(f.code, 9);
      expect(f.endpoint, contains('miniw/bestpartner'));
      expect(f.endpoint, contains('s7=***'));
      expect(f.endpoint, isNot(contains('auth=')));
    });

    test('不可重试的业务码（code=2）只打一次并上报', () async {
      final adapter = _StubAdapter('{["code"]=2,["msg"]=""}');
      await client(adapter).getPartnerList();
      expect(adapter.calls, 1);
      expect(RequestErrorBus.instance.failures.value.single.code, 2);
    });

    test('成功时不产生任何失败记录', () async {
      final adapter = _StubAdapter('{["code"]=0,["data"]={}}');
      await client(adapter).getPartnerList();
      expect(RequestErrorBus.instance.failures.value, isEmpty);
    });

    test('槽位 / 红点失败也有各自标签', () async {
      final adapter = _StubAdapter('{["code"]=9,["msg"]=""}');
      final c = client(adapter);
      await c.getPartnerSlot(1);
      await c.getRedDotCount();
      final labels =
          RequestErrorBus.instance.failures.value.map((f) => f.label).toSet();
      expect(labels, containsAll(<String>['拍档槽位', '拍档红点']));
    });
  });
}
