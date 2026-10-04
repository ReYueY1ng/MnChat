/// `get/set_closeapply_flag` 请求参数形状回归。
///
/// 背景（2026-10-04 真实账号实测，两臂各重复 3 次、间隔 2.5s，并先用
/// `query_friend_list` 做阳性对照 result:0）：
/// `get_closeapply_flag` **带上 `src_uin`** 稳定返回 `{"result":2}`，
/// 去掉它才是 `{"result":0,"data":0}`；两臂 auth 指纹不同（确认比较的是两种
/// 形状，而非同一请求重放）。
///
/// 反编译源码 `friendservice.lua` ReqGetFriendApply (7711) / ReqSetFriendApply
/// (7734) 的参数集本来就只有
/// `apiid/cmd/country/lang/[flag]/s2t/time/token/uin/ver` —— **没有 src_uin**。
/// 这个 2 是**好友服务自己的**业务码，不是网关的 UNKNOW_SERVICE（网关码表只对
/// `code`/`ret` 适用），别把它读成「服务未注册」去改地址。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/friend.dart' show FriendClient;
import 'package:mnchat/core/services/gateway.dart' show GatewayClient;

/// 记录请求、回放固定响应的 Dio 适配器（离线，不发真实请求）。
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{["result"]=0,["data"]=0}',
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
  FriendClient clientWith(_RecordingAdapter adapter) => FriendClient(
    uin: 123456,
    s2: 's2',
    s2t: 's2t',
    gateway: GatewayClient(dio: Dio()..httpClientAdapter = adapter),
  );

  test('get_closeapply_flag 不带 src_uin（带了服务端稳定回 result:2）', () async {
    final adapter = _RecordingAdapter();
    await clientWith(adapter).getCloseapplyFlag();

    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'get_closeapply_flag');
    expect(
      q.containsKey('src_uin'),
      isFalse,
      reason: 'src_uin 会让服务端回 {"result":2}（实测），去掉才是 result:0',
    );
    // country/lang 是 notAuth（进 query 不进签名），其余签名参数照旧。
    expect(q['country'], 'CN');
    expect(q['lang'], '0');
    expect(q['uin'], '123456');
    expect(q['s2t'], 's2t');
    expect(q.containsKey('time'), isTrue);
    expect(q.containsKey('token'), isTrue);
  });

  test('set_closeapply_flag 同样不带 src_uin，flag 正确', () async {
    final adapter = _RecordingAdapter();
    await clientWith(adapter).setCloseapplyFlag(on: true);

    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'set_closeapply_flag');
    expect(q['flag'], '1');
    expect(q.containsKey('src_uin'), isFalse);
  });
}
