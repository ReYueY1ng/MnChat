/// `/server/friend` 请求参数形状回归。
///
/// 背景（2026-10-02 真实账号实测，每个形状重复 3 次、间隔 2.5s，并先用
/// `query_friend_list` 做阳性对照 3/3 成功）：
/// `query_friend_label_pool` **带上 `src_uin`** 稳定返回 `{"result":2}`，
/// 去掉它才是 `{"result":0,"label_list":{…}}`；补 country/lang/encrypt_ver/
/// op_type/tag_id 或改走 POST 都无效。
///
/// 这个 2 是**好友服务自己的**业务码，不是网关的 UNKNOW_SERVICE（网关码表只
/// 对 `code`/`ret` 适用），所以不要把它读成「服务未注册」去改地址。
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
      '{["result"]=0,["label_list"]={}}',
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

  test('query_friend_label_pool 不带 src_uin（带了服务端稳定回 result:2）', () async {
    final adapter = _RecordingAdapter();
    await clientWith(adapter).queryFriendLabelPool();

    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'query_friend_label_pool');
    expect(
      q.containsKey('src_uin'),
      isFalse,
      reason: 'src_uin 会让服务端回 {"result":2}（实测），去掉才是 result:0',
    );
    // 其余签名参数照旧，别把签名一起削了。
    expect(q['uin'], '123456');
    expect(q['s2t'], 's2t');
    expect(q.containsKey('time'), isTrue);
    expect(q.containsKey('token'), isTrue);
  });

  test('setFriendLabelPool 建标签：label 不带 base64 补位，也不带 src_uin', () async {
    final adapter = _RecordingAdapter();
    await clientWith(adapter).setFriendLabelPool(opType: 1, label: 'probe');

    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'set_friend_label_pool');
    expect(q['op_type'], '1');
    // 带 `=` 补位服务端直接回 {"result":2}（实测）；这条曾经因为这里自己
    // inline 一次 base64Encode 而漏掉。
    expect(q['label'], 'cHJvYmU');
    expect(q['label']!.contains('='), isFalse);
    expect(q.containsKey('src_uin'), isFalse);
  });

  test('其它 cmd 仍然带 src_uin（label_pool / closeapply 例外）', () async {
    final adapter = _RecordingAdapter();
    await clientWith(adapter).setOnlineNotifyFlag(654321, on: true);

    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'set_online_notify_flag');
    expect(q['src_uin'], '123456');
    expect(q['des_uin'], '654321');
  });
}
