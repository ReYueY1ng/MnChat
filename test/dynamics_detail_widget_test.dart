/// 动态详情页互动回归测试。
///
/// 覆盖：
/// - (a) 每条评论的长按 / overflow 菜单按作者显示，并发出正确的 `act`；
/// - (b) 二级回复的点赞 / 删除（act=prize_comment_rep /
///   delete_player_comment_rep / delete_comment_rep）；
/// - (c) 本人动态的 AppBar 管理菜单只在 `post.uin == myUin` 时出现，
///   删除动态发出 `act=delete_posting`；
/// - (d) 投票卡渲染 `get_vote_info` 的标题与选项，提交发出 `act=vote`。
///
/// 断言「发了哪个请求」用一个记录请求、回放固定响应的假 Dio adapter（离线），
/// 沿用 test/friend_label_pool_test.dart 的 `HttpClientAdapter` 写法。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mnchat/core/services/dynamics.dart';
import 'package:mnchat/core/services/request_errors.dart' show RequestErrorBus;
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/dynamics_detail_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

/// 记录请求、按 `act` 回放固定响应体的 Dio 适配器（离线，不发真实请求）。
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({Map<String, String>? bodies})
      : _bodies = bodies ?? const <String, String>{};

  final Map<String, String> _bodies;
  final List<RequestOptions> requests = <RequestOptions>[];

  /// 所有匹配 [act] 的已记录请求。
  List<RequestOptions> withAct(String act) => requests
      .where((r) => r.uri.queryParameters['act'] == act)
      .toList(growable: false);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final act = options.uri.queryParameters['act'] ?? '';
    final body = _bodies[act] ?? '{"ret":0}';
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

const int kMeUin = 273640665;
const int kOtherUin = 111222333;

/// 一条一级评论的响应条目（作者 [uin]）。
String _commentBody({
  int uin = kOtherUin,
  int opUin = 0,
  int replyCount = 0,
}) =>
    '{"ret":0,"data":{"list":[{"uin":$uin,"op_uin":$opUin,'
    '"content":"%E4%BD%A0%E5%A5%BD","last_time":1700000000,'
    '"pid_uin":$kMeUin,"pid_ct":1787757890,"com_cnt":$replyCount}]}}';

/// 一条二级回复的响应条目（回复者 [repUin]）。
String _replyBody({int repUin = kMeUin}) =>
    '{"ret":0,"data":{"list":[{"rep_id":"rep-1","rep_uin":$repUin,'
    '"op_uin":$kOtherUin,"content":"yo","rep_time":1700000001,"prize":0}]}}';

const String _voteBody = '{"ret":0,"data":{"vote_id":"vote-9",'
    '"title":"今晚吃啥","mode":1,"multi_mode":1,"end_time":4102444800,'
    '"option_list":[{"index":1,"text":"火锅","count":3},'
    '{"index":2,"text":"烧烤","count":1}]}}';

DynamicsPost _post({int uin = kMeUin, String? voteId}) => DynamicsPost(
  pid: '${kMeUin}_1787757890',
  uin: uin,
  content: '测试动态正文',
  nickname: '测试昵称',
  location: '广东',
  voteId: voteId,
);

DynamicsClient _client(_RecordingAdapter adapter) => DynamicsClient(
  uin: kMeUin,
  s2: 's2',
  s2t: 's2t',
  dio: Dio()..httpClientAdapter = adapter,
  baseUrl: 'https://example.invalid',
);

Future<void> _pump(
  WidgetTester tester,
  DynamicsPost post,
  DynamicsClient client, {
  int myUin = kMeUin,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [myUinProvider.overrideWithValue(myUin)],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: DynamicsDetailPage(post: post, client: client),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(RequestErrorBus.instance.clear);
  tearDown(RequestErrorBus.instance.clear);

  testWidgets('(c) 本人动态：AppBar 管理菜单出现，删除动态发出 delete_posting', (
    tester,
  ) async {
    final adapter = _RecordingAdapter();
    await _pump(tester, _post(), _client(adapter));

    expect(find.byKey(dynamicsPostMenuKey), findsOneWidget);

    await tester.tap(find.byKey(dynamicsPostMenuKey));
    await tester.pumpAndSettle();
    expect(find.text('删除动态'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('改可见范围'), findsOneWidget);

    await tester.tap(find.text('删除动态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('delete_posting');
    expect(sent, hasLength(1), reason: '删除动态应发出 act=delete_posting');
    expect(sent.single.uri.queryParameters['pid'], '${kMeUin}_1787757890');
  });

  testWidgets('(c) 他人动态：AppBar 管理菜单不出现', (tester) async {
    final adapter = _RecordingAdapter();
    await _pump(tester, _post(uin: kOtherUin), _client(adapter));

    expect(find.byKey(dynamicsPostMenuKey), findsNothing);
  });

  testWidgets('(c) 改可见范围发出 setPostingAuth（ptype=see）', (tester) async {
    final adapter = _RecordingAdapter();
    await _pump(tester, _post(), _client(adapter));

    await tester.tap(find.byKey(dynamicsPostMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('改可见范围'));
    await tester.pumpAndSettle();
    // 5 档可见范围来自 DynamicsAuth.labels
    expect(find.text('仅粉丝'), findsOneWidget);
    await tester.tap(find.text('仅粉丝'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('setPostingAuth');
    expect(sent, hasLength(1));
    expect(sent.single.uri.queryParameters['ptype'], DynamicsAuth.ptypeSee);
    expect(
      sent.single.uri.queryParameters['pauth'],
      '${DynamicsAuth.onlyFans}',
    );
  });

  testWidgets('(a) 本人动态：评论菜单含置顶 / 删除评论 / 回复 / 点赞', (
    tester,
  ) async {
    final adapter = _RecordingAdapter(
      bodies: {'get_recommend_comment': _commentBody()},
    );
    await _pump(tester, _post(), _client(adapter));

    await tester.tap(find.byTooltip(dynamicsCommentMenuTooltip));
    await tester.pumpAndSettle();

    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('取消点赞'), findsNothing);
    expect(find.text('点赞'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('删除评论'), findsOneWidget);
  });

  testWidgets('(a) 他人动态 + 他人评论：无置顶、无删除评论，仅点赞/回复', (
    tester,
  ) async {
    final adapter = _RecordingAdapter(
      bodies: {'get_recommend_comment': _commentBody()},
    );
    await _pump(
      tester,
      _post(uin: kOtherUin),
      _client(adapter),
      myUin: kMeUin,
    );

    await tester.tap(find.byTooltip(dynamicsCommentMenuTooltip));
    await tester.pumpAndSettle();

    expect(find.text('置顶'), findsNothing);
    expect(find.text('取消置顶'), findsNothing);
    expect(find.text('删除评论'), findsNothing);
    expect(find.text('点赞'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
  });

  testWidgets('(a) 他人动态 + 我的评论：出现删除评论（评论作者可删）', (tester) async {
    final adapter = _RecordingAdapter(
      bodies: {'get_recommend_comment': _commentBody(uin: kMeUin)},
    );
    await _pump(
      tester,
      _post(uin: kOtherUin),
      _client(adapter),
      myUin: kMeUin,
    );

    await tester.tap(find.byTooltip(dynamicsCommentMenuTooltip));
    await tester.pumpAndSettle();

    expect(find.text('删除评论'), findsOneWidget);
    expect(find.text('置顶'), findsNothing);
  });

  testWidgets('(a) 评论点赞发出 prize_comment（op_type=prize，op_uin 原样）', (
    tester,
  ) async {
    // op_uin=7：定位参数必须原样带上（实时探针：一级评论 op_uin 可为 0，不能拿作者兜底）
    final adapter = _RecordingAdapter(
      bodies: {'get_recommend_comment': _commentBody(opUin: 7)},
    );
    await _pump(tester, _post(), _client(adapter));

    await tester.tap(find.byTooltip(dynamicsCommentMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('点赞'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('prize_comment');
    expect(sent, hasLength(1));
    final q = sent.single.uri.queryParameters;
    expect(q['op_type'], 'prize');
    expect(q['com_op_uin'], '7');
    expect(q['com_uin'], '$kOtherUin');
  });

  testWidgets('(a) 删除评论发出 delete_single_comment', (tester) async {
    final adapter = _RecordingAdapter(
      bodies: {'get_recommend_comment': _commentBody(uin: kMeUin)},
    );
    await _pump(
      tester,
      _post(uin: kOtherUin),
      _client(adapter),
      myUin: kMeUin,
    );

    await tester.tap(find.byTooltip(dynamicsCommentMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除评论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('delete_single_comment');
    expect(sent, hasLength(1));
    expect(
      sent.single.uri.queryParameters['pid'],
      '${kMeUin}_1787757890_${kMeUin}_1700000000',
      reason: 'pid 由 <动态pid>_<评论作者uin>_<last_time> 拼成',
    );
  });

  testWidgets('(b) 回复写作发出 add_comment_rep（op_uin 取被回复者）', (tester) async {
    final adapter = _RecordingAdapter(
      bodies: {'get_recommend_comment': _commentBody()},
    );
    await _pump(tester, _post(), _client(adapter));

    await tester.tap(find.byTooltip(dynamicsCommentMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '顶一个');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('add_comment_rep');
    expect(sent, hasLength(1));
    final q = sent.single.uri.queryParameters;
    // 一级评论 op_uin=0 时，被回复者回落为评论作者 uin。
    expect(q['op_uin'], '$kOtherUin');
    expect(q['content'], '顶一个');
    expect(q['com_pid_ct'], '1787757890');
  });

  testWidgets('(b) 我的回复：删除发出 delete_player_comment_rep', (tester) async {
    final adapter = _RecordingAdapter(
      bodies: {
        'get_recommend_comment': _commentBody(replyCount: 1),
        'get_comment_rep': _replyBody(repUin: kMeUin),
      },
    );
    await _pump(tester, _post(), _client(adapter));

    await tester.tap(find.text('共1条回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(dynamicsReplyMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('delete_player_comment_rep');
    expect(sent, hasLength(1));
    expect(sent.single.uri.queryParameters['rep_id'], 'rep-1');
    expect(adapter.withAct('delete_comment_rep'), isEmpty);
  });

  testWidgets('(b) 他人回复（我是动态作者）：删除发出 delete_comment_rep', (
    tester,
  ) async {
    final adapter = _RecordingAdapter(
      bodies: {
        'get_recommend_comment': _commentBody(replyCount: 1),
        'get_comment_rep': _replyBody(repUin: kOtherUin),
      },
    );
    await _pump(tester, _post(), _client(adapter));

    await tester.tap(find.text('共1条回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(dynamicsReplyMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('delete_comment_rep');
    expect(sent, hasLength(1));
    expect(sent.single.uri.queryParameters['rep_id'], 'rep-1');
  });

  testWidgets('(b) 回复点赞发出 prize_comment_rep', (tester) async {
    final adapter = _RecordingAdapter(
      bodies: {
        'get_recommend_comment': _commentBody(replyCount: 1),
        'get_comment_rep': _replyBody(repUin: kOtherUin),
      },
    );
    await _pump(tester, _post(), _client(adapter));

    await tester.tap(find.text('共1条回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(dynamicsReplyMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('点赞'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('prize_comment_rep');
    expect(sent, hasLength(1));
    expect(sent.single.uri.queryParameters['rep_id'], 'rep-1');
    expect(sent.single.uri.queryParameters['op_type'], 'prize');
  });

  testWidgets('(d) 投票卡渲染标题/选项并提交 vote（opts=1,2）', (tester) async {
    final adapter = _RecordingAdapter(
      bodies: {'get_vote_info': _voteBody},
    );
    await _pump(tester, _post(voteId: 'vote-9'), _client(adapter));

    final info = adapter.withAct('get_vote_info');
    expect(info, hasLength(1), reason: 'voteId 非空时应拉取投票信息');
    expect(info.single.uri.queryParameters['vote_id'], 'vote-9');

    expect(find.text('今晚吃啥'), findsOneWidget);
    expect(find.text('火锅'), findsOneWidget);
    expect(find.text('烧烤'), findsOneWidget);

    // 多选（mode=1 && multi_mode=1）：两个都选。
    await tester.tap(find.text('火锅'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('烧烤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('投票'));
    await tester.pumpAndSettle();

    final sent = adapter.withAct('vote');
    expect(sent, hasLength(1));
    expect(sent.single.uri.queryParameters['vote_id'], 'vote-9');
    expect(sent.single.uri.queryParameters['opts'], '1,2');
  });

  testWidgets('(d) 无 voteId 时不渲染投票卡', (tester) async {
    final adapter = _RecordingAdapter();
    await _pump(tester, _post(), _client(adapter));

    expect(adapter.withAct('get_vote_info'), isEmpty);
    expect(find.text('投票'), findsNothing);
  });
}
