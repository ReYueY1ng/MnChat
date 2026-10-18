// 分片直传的请求序列与"网关排队"降级。
//
// 真因（2026-10-17 live）：>128 KiB 的文件必然分成多片，每片一个同接口 POST，
// 网关按账号排队会把 2 秒内的第二次回成 code=9/23 —— 226 B 的图片只有一片所以
// 一直没暴露，179 KB 的录音一上传就卡住。这里锁住两条：片间留白、同片幂等重发。
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/net/photo_upload.dart';

/// 顺序回放式适配器：按次给响应，并记录每次请求的 act。
class _ReplayAdapter implements HttpClientAdapter {
  _ReplayAdapter(this.replies);

  final List<String> replies;
  final List<String> acts = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final m = RegExp(r'act=([a-z_]+)').firstMatch(options.uri.toString());
    acts.add(m?.group(1) ?? '?');
    final index = acts.length - 1;
    final body = index < replies.length ? replies[index] : replies.last;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 造一个能装进 [chunks] 片的字节流（内容不重要，md5 由调用方给）。
Uint8List _bytes(int chunks) =>
    Uint8List(kUploadChunkSize * (chunks - 1) + 10);

void main() {
  test('单片文件：info → upload_end（不会多打同接口的第二次）', () async {
    final adapter = _ReplayAdapter(<String>[
      'ok,size=-1',
      'ok:token=T1&node=34&dir=20261017',
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final token = await uploadPresignedFile(
      dio,
      'http://upload.test/u',
      _bytes(1),
      fileMd5: 'a' * 32,
      ext: 'wav',
      chunkGap: Duration.zero,
    );
    // 回包去掉 `ok:` 前缀后原样返回（token/node/dir 一起，与真实一致）。
    expect(token, 'token=T1&node=34&dir=20261017');
    expect(adapter.acts, <String>['info', 'upload_end']);
  });

  test('两片文件：info → upload_begin → upload_end', () async {
    final adapter =
        _ReplayAdapter(<String>['ok,size=-1', 'ok', 'ok:token=T2&node=34']);
    final dio = Dio()..httpClientAdapter = adapter;
    final token = await uploadPresignedFile(
      dio,
      'http://upload.test/u',
      _bytes(2),
      fileMd5: 'b' * 32,
      ext: 'wav',
      chunkGap: Duration.zero,
    );
    expect(token, 'token=T2&node=34');
    expect(adapter.acts, <String>['info', 'upload_begin', 'upload_end']);
  });

  test('某片被网关挡回（非 ok）→ 重发同一片，最终仍拿到 token', () async {
    final adapter = _ReplayAdapter(<String>[
      'ok,size=-1',
      'code=9', // 第一次 begin 被排队挡掉
      'ok', // 重发成功
      'ok:token=T3&node=34',
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final token = await uploadPresignedFile(
      dio,
      'http://upload.test/u',
      _bytes(2),
      fileMd5: 'c' * 32,
      ext: 'wav',
      chunkGap: Duration.zero,
    );
    expect(token, 'token=T3&node=34');
    expect(
      adapter.acts,
      <String>['info', 'upload_begin', 'upload_begin', 'upload_end'],
    );
  });

  test('一直失败 → 返回 null（不抛），重试次数有上限', () async {
    final adapter = _ReplayAdapter(<String>['ok,size=-1', 'code=9']);
    final dio = Dio()..httpClientAdapter = adapter;
    final token = await uploadPresignedFile(
      dio,
      'http://upload.test/u',
      _bytes(1),
      fileMd5: 'd' * 32,
      ext: 'wav',
      chunkGap: Duration.zero,
    );
    expect(token, isNull);
    // info + 首片 1 次 + 重试 kGatewayRetryAttempts 次
    expect(adapter.acts.length, 1 + 1 + kGatewayRetryAttempts);
  });
}
