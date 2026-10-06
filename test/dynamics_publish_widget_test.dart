import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/dynamics.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/publish_dynamics_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

/// 发布动态页回归测试 —— 断言请求线格式（不联网）：
///   1. 选图 → `add_posting_pic` 的 `seq`/`md5`/`ext` 与实际字节一致，
///      且 `add_posting` 带 `seq=1,2`（1-based、逗号分隔、按上传顺序）；
///   2. 可见范围选择器把 `auth_see` 送进 `add_posting`；
///   3. `@好友` 选择器把 uin 送进 `add_posting` 的 `notice_uins`；
///   4. 投票截止时间默认 now+7 天，随选择器改动。
///
/// 正文断言同时防回归：`content` 只编码一次（双重编码会破坏中文）。
///
/// 对齐 dynamicsdatamanager.lua AddPosting（:1376-1450）/ AddPostPic（:7727-7778）。

/// 记录请求并按 `act` 回放固定响应的 Dio 适配器（离线、无网络）。
class _FakePostingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    final act = options.uri.queryParameters['act'] ?? '';
    String text;
    if (path.endsWith('/miniw/profile')) {
      // upload_pre_photo：`ok:<直传地址>`。
      text = 'ok:https://upload.test/post';
    } else if (options.method == 'POST') {
      // 直传字节：`ok:<sub_token>`。
      text = 'ok:time=1&auth=2&s2t=3';
    } else if (act == 'add_posting_pic') {
      final seq = options.uri.queryParameters['seq'];
      text = '{"ret":0,"data":{"url":"https://img.test/$seq"}}';
    } else if (act == 'create_vote') {
      text = '{"ret":0,"data":{"vote_info":{"vote_id":"vote-1"}}}';
    } else {
      text = '{"ret":0,"data":{}}';
    }
    return ResponseBody.fromString(
      text,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 1×1 PNG（合法图片字节；`Image.memory` 需要能解码，不用随机字节）。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 第二张图：尾部多一字节 → md5 与第一张不同，仍可解码。
final Uint8List _png2 = Uint8List.fromList(<int>[..._png, 0]);

/// 取最后一个匹配 [act]（可选 [seq]）的请求；缺失即失败。
RequestOptions _reqFor(
  List<RequestOptions> requests,
  String act, {
  String? seq,
}) {
  final matches = requests
      .where(
        (r) =>
            r.uri.queryParameters['act'] == act &&
            (seq == null || r.uri.queryParameters['seq'] == seq),
      )
      .toList();
  expect(
    matches,
    isNotEmpty,
    reason: '缺少 act=$act${seq == null ? '' : ' seq=$seq'} 的请求',
  );
  return matches.last;
}

DynamicsClient _client(_FakePostingAdapter adapter) => DynamicsClient(
      uin: 273640665,
      s2: 'S2SECRET',
      s2t: '1790844333',
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://shequ.mini1.cn:8081',
    );

void main() {
  /// 以真实路由推入发布页（发布成功会 pop，直接当 home 会弹空路由栈）。
  Future<void> pumpPublish(
    WidgetTester tester, {
    required DynamicsClient client,
    required DynamicsImagePicker imagePicker,
    List<Contact> contacts = const <Contact>[],
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactsProvider.overrideWith((_) => Stream.value(contacts)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => PublishDynamicsPage(
                        client: client,
                        imagePicker: imagePicker,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('选图 → add_posting_pic 的 seq/md5 与 add_posting 的 seq 一致', (tester) async {
    final adapter = _FakePostingAdapter();
    await pumpPublish(
      tester,
      client: _client(adapter),
      imagePicker: (_) async => [
        (name: 'a.png', bytes: _png),
        (name: 'b.png', bytes: _png2),
      ],
    );

    await tester.tap(find.byKey(publishDynamicsAddImageKey));
    await tester.pumpAndSettle();

    // 两张图都登记成功（缩略图就位，无异常）。
    expect(tester.takeException(), isNull);
    expect(find.byKey(publishDynamicsPicKey(1)), findsOneWidget);
    expect(find.byKey(publishDynamicsPicKey(2)), findsOneWidget);

    final pic1 = _reqFor(adapter.requests, 'add_posting_pic', seq: '1');
    final pic2 = _reqFor(adapter.requests, 'add_posting_pic', seq: '2');
    // 文件 md5 由实际字节算出（与直传的 md5 必须一致）。
    expect(pic1.uri.queryParameters['md5'], crypto.md5.convert(_png).toString());
    expect(
      pic2.uri.queryParameters['md5'],
      crypto.md5.convert(_png2).toString(),
    );
    expect(pic1.uri.queryParameters['ext'], 'png');
    expect(pic1.uri.queryParameters['show_idx'], '1');

    // 可见范围：选「仅粉丝」= 1。
    await tester.tap(find.byKey(publishDynamicsAuthSeeKey(DynamicsAuth.onlyFans)));
    await tester.pump();
    await tester.enterText(find.byKey(publishDynamicsContentKey), '发布图片动态');
    await tester.tap(find.byKey(publishDynamicsSubmitKey));
    await tester.pumpAndSettle();

    final add = _reqFor(adapter.requests, 'add_posting');
    expect(add.uri.queryParameters['seq'], '1,2');
    expect(add.uri.queryParameters['auth_see'], '1');
    // 正文只编码一次（双重编码会得到字面 %E5%8F%91…）。
    expect(add.uri.queryParameters['content'], '发布图片动态');
    // 签名存在（act/uin/… 之外的 md5 参数）。
    expect(add.uri.queryParameters['md5'], isNotEmpty);
  });

  testWidgets('@好友 → notice_uins；可见范围「仅自己」= 3', (tester) async {
    final adapter = _FakePostingAdapter();
    await pumpPublish(
      tester,
      client: _client(adapter),
      imagePicker: (_) async => const [],
      contacts: const [
        Contact(uin: 111, nickname: '阿花', relation: 8),
        Contact(uin: 222, nickname: '[i][color][b]小明', relation: 8),
        Contact(uin: 333, nickname: '非好友', relation: 0),
      ],
    );

    await tester.tap(find.byKey(publishDynamicsNoticeUinsKey));
    await tester.pumpAndSettle();
    // 昵称洗掉富文本标记；非好友（relation 无 bit3）不出现。
    await tester.tap(find.text('阿花'));
    await tester.pump();
    await tester.tap(find.text('小明'));
    await tester.pump();
    expect(find.text('非好友'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(publishDynamicsAuthSeeKey(DynamicsAuth.onlySelf)));
    await tester.pump();
    await tester.enterText(find.byKey(publishDynamicsContentKey), '呼叫好友');
    await tester.tap(find.byKey(publishDynamicsSubmitKey));
    await tester.pumpAndSettle();

    final add = _reqFor(adapter.requests, 'add_posting');
    expect(add.uri.queryParameters['notice_uins'], '111,222');
    expect(add.uri.queryParameters['auth_see'], '3');
    expect(add.uri.queryParameters.containsKey('seq'), isFalse);
  });

  testWidgets('投票：截止时间默认 now+7 天，多选开关进 multi_mode', (tester) async {
    final adapter = _FakePostingAdapter();
    await pumpPublish(
      tester,
      client: _client(adapter),
      imagePicker: (_) async => const [],
    );

    await tester.enterText(find.byKey(publishDynamicsContentKey), '投票动态');
    await tester.tap(find.text('附带投票'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '投票标题'), '去哪里');
    await tester.enterText(find.widgetWithText(TextField, '选项 1'), '左边');
    await tester.enterText(find.widgetWithText(TextField, '选项 2'), '右边');
    await tester.tap(find.text('允许多选'));
    await tester.pump();
    expect(find.byKey(publishDynamicsVoteEndKey), findsOneWidget);
    await tester.tap(find.byKey(publishDynamicsSubmitKey));
    await tester.pumpAndSettle();

    final vote = _reqFor(adapter.requests, 'create_vote');
    final endTime = int.parse(vote.uri.queryParameters['end_time']!);
    final expected = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;
    expect((endTime - expected).abs(), lessThan(300));
    expect(vote.uri.queryParameters['multi_mode'], '1');

    final add = _reqFor(adapter.requests, 'add_posting');
    expect(add.uri.queryParameters['vote_id'], 'vote-1');
  });
}
