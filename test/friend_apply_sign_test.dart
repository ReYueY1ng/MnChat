/// `apply_friend` / `accept_apply` / `reject_apply` / `handle_black` 的**签名子集**回归。
///
/// 签名（`auth`）是服务端唯一校验的东西：它按「收到的参数 − 自己的 notAuth 表」
/// 重算 md5，多签名一个键就回 `{"result":2}`（好友服务码表 2=sign_error），
/// 少发一个键不挂。所以这两个 cmd 的回归点就是「哪些键进了签名」。
///
/// 2026-10-17 真实账号实测（同一链路先用 `query_friend_list` 拿阳性对照 result:0；
/// des_uin=自己 → 服务端必回 to_self=5，探针不产生真实申请；每臂重复 2 次、
/// 间隔 2.2s；另有一条伪造 auth 的对照臂回 2，证明 2 出自签名校验）：
/// - `apply_friend` 把 country/lang/ver 算进签名 → `{"result":2}` 稳定复现；
///   三者 notAuth 后 → `{"result":5}`（ReqAddFriendSync 的 addparam 第 4 参本来
///   就对这三个传了 true）。
/// - `accept_apply` 相反：country/lang/ver **必须**在签名里，排除它们才回 2
///   （ReqAgreeAddFriend 的 addparam 没有 notAuth 标记）。
/// - `reject_apply`(2477) / `handle_black`(2546) 与 `apply_friend` 同类：
///   apiid/country/lang/ver 都是 notAuth；算进签名时回 2，notAuth 后回业务码。
///
/// 断言方式是「按记录的请求重算 canonical 再比 auth」，请求里的 time/token 都取自
/// 录制结果，所以不依赖时钟、不会偶发。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/crypto/encoding.dart' show luaUrlEncode;
import 'package:mnchat/core/crypto/md5_sign.dart' show md5Sign, roomAuthKey;
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
      '{["result"]=5}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 复刻 `buildFriendRequestUrl` 的 canonical：`k=luaUrlEncode(v)` 排序拼接，
/// 排除 [excludedKeys]（与 `auth` 本身）。
String _canonical(Map<String, String> q, Set<String> excludedKeys) =>
    (q.keys.toList()..sort())
        .where((k) => k != 'auth' && !excludedKeys.contains(k))
        .map((k) => '$k=${luaUrlEncode(q[k]!)}')
        .join('&');

String _authOf(String url) =>
    RegExp(r'auth=([0-9a-f]{32})').firstMatch(url)!.group(1)!;

FriendClient _clientWith(_RecordingAdapter adapter) => FriendClient(
  uin: 123456,
  s2: 's2',
  s2t: 's2t',
  gateway: GatewayClient(dio: Dio()..httpClientAdapter = adapter),
);

void main() {
  test('apply_friend：country/lang/ver 进 query 但不进签名', () async {
    final adapter = _RecordingAdapter();
    await _clientWith(adapter).applyFriend(desUin: 654321, from: '5');

    final url = adapter.requests.single.uri.toString();
    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'apply_friend');
    expect(q['from'], '5');
    // 三个 notAuth 参数照发，只是不参与签名。
    expect(q['country'], 'CN');
    expect(q['lang'], '0');
    expect(q['ver'], isNotNull);

    expect(
      _authOf(url),
      md5Sign([
        _canonical(q, {'country', 'lang', 'ver'}),
        roomAuthKey,
      ]),
      reason: 'apply_friend 的签名必须排除 country/lang/ver（含它们服务端回 result:2）',
    );
    expect(
      _authOf(url),
      isNot(md5Sign([_canonical(q, const {}), roomAuthKey])),
      reason: '把 country/lang/ver 算进签名就是线上那个 result:2 的形状',
    );
  });

  test('accept_apply：country/lang/ver 参与签名（与 apply_friend 相反）', () async {
    final adapter = _RecordingAdapter();
    await _clientWith(adapter).acceptApply(desUin: 654321);

    final url = adapter.requests.single.uri.toString();
    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'accept_apply');
    expect(q['country'], 'CN');
    expect(q['lang'], '0');

    expect(
      _authOf(url),
      md5Sign([_canonical(q, const {}), roomAuthKey]),
      reason: 'accept_apply 的签名包含 country/lang/ver（排除它们服务端回 result:2）',
    );
    expect(
      _authOf(url),
      isNot(
        md5Sign([
          _canonical(q, {'country', 'lang', 'ver'}),
          roomAuthKey,
        ]),
      ),
      reason: '别照 apply_friend 的 notAuth 对称改，那样反而会挂',
    );
  });

  test('reject_apply：apiid/country/lang/ver 进 query 但不进签名', () async {
    final adapter = _RecordingAdapter();
    await _clientWith(adapter).rejectApply(desUin: 654321);

    final url = adapter.requests.single.uri.toString();
    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'reject_apply');
    expect(q['apiid'], '110');
    expect(q['country'], 'CN');
    expect(q['ver'], isNotNull);

    expect(
      _authOf(url),
      md5Sign([
        _canonical(q, {'apiid', 'country', 'lang', 'ver'}),
        roomAuthKey,
      ]),
      reason: 'reject_apply 的签名必须排除 apiid/country/lang/ver（含它们回 result:2）',
    );
    expect(
      _authOf(url),
      isNot(md5Sign([_canonical(q, const {}), roomAuthKey])),
      reason: '把这四个算进签名就是线上那个 result:2 的形状',
    );
  });

  test('handle_black：apiid/country/lang/ver 同样不进签名', () async {
    final adapter = _RecordingAdapter();
    await _clientWith(adapter).removeBlacklist(654321);

    final url = adapter.requests.single.uri.toString();
    final q = adapter.requests.single.uri.queryParameters;
    expect(q['cmd'], 'handle_black');
    expect(q['op_type'], '0');
    expect(q['apiid'], '110');

    expect(
      _authOf(url),
      md5Sign([
        _canonical(q, {'apiid', 'country', 'lang', 'ver'}),
        roomAuthKey,
      ]),
      reason: 'handle_black 的签名必须排除 apiid/country/lang/ver（含它们回 result:2）',
    );
  });
}
