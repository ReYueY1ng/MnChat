/// `getVoteInfo` 失败处理回归：`code != 0` 时不弹全局错误条，只在
/// 「动态作者是本人」时提示服务端 `msg`（对齐 `dynamicsdatamanager.lua:4646-4656`
/// 的 `bolMine`）。否则别人的投票即使带业务提示也照常静默。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/dynamics.dart';

/// 按 `act` 回放固定响应体的假 Dio 适配器（离线）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._bodies);

  final Map<String, String> _bodies;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final act = options.uri.queryParameters['act'] ?? '';
    return ResponseBody.fromString(
      _bodies[act] ?? '{"ret":0}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DynamicsClient _client(Map<String, String> bodies) => DynamicsClient(
  uin: 7,
  s2: 's2',
  s2t: 's2t',
  dio: Dio()..httpClientAdapter = _StubAdapter(bodies),
  baseUrl: 'https://example.invalid',
);

void main() {
  const failed = '{"code":2,"msg":"该投票正在审核中"}';

  test('code != 0：不抛、返回 null，并把 msg 交给 onMessage', () async {
    String? seen;
    final info = await _client(
      {'get_vote_info': failed},
    ).getVoteInfo('v1', onMessage: (m) => seen = m);
    expect(info, isNull);
    expect(seen, '该投票正在审核中');
  });

  test('code != 0 且不传 onMessage（非本人）：静默', () async {
    final info = await _client({'get_vote_info': failed}).getVoteInfo('v1');
    expect(info, isNull);
  });

  test('code == 0：正常解析标题与选项', () async {
    final info = await _client({
      'get_vote_info':
          '{"code":0,"data":{"vote_id":"v1","title":"今晚吃啥",'
              '"option_list":[{"index":1,"text":"火锅","count":3}]}}',
    }).getVoteInfo('v1');
    expect(info?.title, '今晚吃啥');
    expect(info?.options.single.text, '火锅');
  });
}
