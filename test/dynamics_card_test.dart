import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/dynamics.dart';
import 'package:mnchat/core/storage/app_database.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/dynamics_detail_page.dart';
import 'package:mnchat/ui/dynamics_topic_page.dart' show DynamicsTopicPage;
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/widgets/avatar_view.dart';
import 'package:mnchat/ui/widgets/dynamics_card.dart';
import 'package:mnchat/ui/widgets/rich_text_view.dart';

/// 动态卡片回归测试。
///
/// - 昵称 / 时间文字块与头像垂直居中对齐（行仍为 center）；
/// - 「关注」按钮钉在行右上角（顶边与行顶边对齐、右缘贴行右缘）；
/// - 作者已是好友（bit3=8）或已被我关注（bit4=16）时不再显示「关注」按钮；
/// - 内容类型：话题内联渲染 / 投票详情 / 抽奖详情 / 视频标记。

/// 按 `act` 回放固定响应体的假 Dio 适配器（离线，沿用
/// test/dynamics_detail_widget_test.dart 的写法）。
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
  uin: 273640665,
  s2: 's2',
  s2t: 's2t',
  dio: Dio()..httpClientAdapter = _StubAdapter(bodies),
  baseUrl: 'https://example.invalid',
);

void main() {
  const basePost = DynamicsPost(
    pid: '273640665_1787757890',
    uin: 273640665,
    content: '测试动态正文',
    nickname: '测试昵称',
    location: '广东',
  );

  /// pump 动态卡片；[contacts] 注入联系人流（默认空 = 未加载）。
  /// [db] 传入时额外覆写 databaseProvider（点击进详情页需要）。
  /// [client] 注入带假 adapter 的动态客户端（拉投票 / 抽奖详情用）。
  Future<void> pumpCard(
    WidgetTester tester, {
    List<Contact> contacts = const <Contact>[],
    bool isMine = false,
    DynamicsPost? post,
    AppDatabase? db,
    DynamicsClient? client,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactsProvider.overrideWith((_) => Stream.value(contacts)),
          if (db != null) databaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: DynamicsCard(
              post: post ?? basePost,
              isMine: isMine,
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('头部：文字居中于头像槽位，关注按钮钉在行右上角', (tester) async {
    await pumpCard(tester);
    expect(tester.takeException(), isNull);

    // 头像槽位（含框的透明外圈）；可见头像居中于其中。
    final slot = tester.getRect(find.byType(AvatarView));
    final name = tester.getRect(find.byType(RichTextView));
    final meta = tester.getRect(find.text('IP 广东'));
    // 文字块（昵称 + 时间/属地）整体中心 = 头像槽位中心。
    expect(
      (name.top + meta.bottom) / 2,
      closeTo(slot.center.dy, 0.5),
      reason: '昵称/时间文字块需与头像垂直居中对齐',
    );

    // 头部行 = 头像最近的 Row 祖先；关注按钮的 Align 盒需铺满行高。
    final row = tester.getRect(
      find
          .ancestor(of: find.byType(AvatarView), matching: find.byType(Row))
          .first,
    );
    expect(slot.top, closeTo(row.top, 0.5), reason: '头像槽位是行内最高子项');
    final follow = tester.getRect(
      find
          .ancestor(of: find.text('关注'), matching: find.byType(Align))
          .first,
    );
    expect(follow.top, closeTo(row.top, 0.5), reason: '关注按钮需钉在行顶部');
    expect(follow.right, closeTo(row.right, 0.5), reason: '关注按钮需靠行右缘');
  });

  testWidgets('已是好友或已关注：不显示关注按钮', (tester) async {
    // bit3=8 双向好友
    await pumpCard(
      tester,
      contacts: const [Contact(uin: 273640665, nickname: '测试昵称', relation: 8)],
    );
    expect(find.text('关注'), findsNothing);

    // bit4=16 我关注
    await pumpCard(
      tester,
      contacts: const [
        Contact(uin: 273640665, nickname: '测试昵称', relation: 16),
      ],
    );
    expect(find.text('关注'), findsNothing);

    // 8|16=24 好友 + 关注
    await pumpCard(
      tester,
      contacts: const [
        Contact(uin: 273640665, nickname: '测试昵称', relation: 24),
      ],
    );
    expect(find.text('关注'), findsNothing);
  });

  testWidgets('非好友非关注（含不在联系人列表）：显示关注按钮', (tester) async {
    // 联系人未加载 / 作者不在列表：保持原行为显示
    await pumpCard(tester);
    expect(find.text('关注'), findsOneWidget);

    // 在列表但 relation 无 bit3/bit4
    await pumpCard(
      tester,
      contacts: const [Contact(uin: 273640665, nickname: '测试昵称', relation: 0)],
    );
    expect(find.text('关注'), findsOneWidget);

    // 其他 uin 的联系人不影响
    await pumpCard(
      tester,
      contacts: const [Contact(uin: 999, nickname: '别人', relation: 24)],
    );
    expect(find.text('关注'), findsOneWidget);
  });

  testWidgets('我的动态：不显示关注按钮', (tester) async {
    await pumpCard(tester, isMine: true);
    expect(find.text('关注'), findsNothing);
  });

  testWidgets('话题：正文里的 #{名称&id} 内联渲染为 #名称，不单独成 chip', (tester) async {
    // 对齐 dynamicsdatamanager.lua:3176-3260 的 callBack1：话题写在正文里
    // （`#{名称&topicid}`），就地渲染成 `#名称`；topic_list 不再单独成行。
    const withTopics = DynamicsPost(
      pid: '273640665_1787757891',
      uin: 273640665,
      content: '带话题的动态 #{迷你世界&o:21} 和 #{创造&o:22}',
      nickname: '测试昵称',
      location: '广东',
      topics: [
        DynamicsTopic(topicId: 'o:21', title: '迷你世界'),
        DynamicsTopic(topicId: 'o:22', title: '创造'),
      ],
    );
    await pumpCard(tester, post: withTopics);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('#迷你世界'), findsOneWidget);
    expect(find.textContaining('#创造'), findsOneWidget);

    // 正文不带话题标记时不渲染任何话题文本。
    await pumpCard(tester);
    expect(find.textContaining('#迷你世界'), findsNothing);
  });

  testWidgets('话题：只有 topic_list（正文无标记）时不渲染话题 id 串', (tester) async {
    const keyOnly = DynamicsPost(
      pid: '273640665_1787757895',
      uin: 273640665,
      content: '纯话题 key 动态',
      nickname: '测试昵称',
      location: '广东',
      // 真实服务器形态：topic_list 为纯字符串 key 数组，无 title。
      topics: [DynamicsTopic(topicId: 'u:1813749331:1704717010')],
    );
    await pumpCard(tester, post: keyOnly);
    expect(tester.takeException(), isNull);
    // 话题 id 是一串数字，不该作为文本出现在卡片上（游戏在正文无标记时也不显示）。
    expect(find.textContaining('u:1813749331'), findsNothing);
  });

  testWidgets('话题：不再有独立 chip，点卡片仍进动态详情', (tester) async {
    const withTopics = DynamicsPost(
      pid: '273640665_1787757892',
      uin: 273640665,
      content: '带话题的动态 #{迷你世界&o:21}',
      nickname: '测试昵称',
      location: '广东',
      topics: [DynamicsTopic(topicId: 'o:21', title: '迷你世界')],
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await pumpCard(tester, post: withTopics, db: db);

    // 话题就地渲染在正文里，不再有可点的独立 chip。
    expect(find.textContaining('#迷你世界'), findsOneWidget);

    // 卡片整体仍可进详情。
    // 注：无注入 client 的详情页会停在加载转圈（不会 settle），所以用定次 pump
    // 而不是 pumpAndSettle。
    await tester.tap(find.byType(DynamicsCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DynamicsDetailPage), findsOneWidget);
  });

  testWidgets('话题：正文里的 #名称 可点，进该话题下的动态列表', (tester) async {
    const withTopics = DynamicsPost(
      pid: '273640665_1787757898',
      uin: 273640665,
      content: '带话题的动态 #{迷你世界&o:21}',
      nickname: '测试昵称',
      location: '广东',
      topics: [DynamicsTopic(topicId: 'o:21', title: '迷你世界')],
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await pumpCard(tester, post: withTopics, db: db);

    await tester.tap(find.textContaining('#迷你世界'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final page = tester.widget<DynamicsTopicPage>(
      find.byType(DynamicsTopicPage),
    );
    expect(page.topicId, 'o:21', reason: '点话题要用消息里的 id 进话题流');
    expect(page.topicTitle, '迷你世界');
    expect(find.byType(DynamicsDetailPage), findsNothing);
  });

  testWidgets('投票：voteId 非空显示「投票」标记', (tester) async {
    const withVote = DynamicsPost(
      pid: '273640665_1787757893',
      uin: 273640665,
      content: '投票动态',
      nickname: '测试昵称',
      location: '广东',
      voteId: 'v_123',
    );
    await pumpCard(tester, post: withVote);
    expect(find.text('投票'), findsOneWidget);

    await pumpCard(tester);
    expect(find.text('投票'), findsNothing);
  });

  testWidgets('投票：卡片拉取投票详情并展示标题与选项', (tester) async {
    await pumpCard(
      tester,
      post: const DynamicsPost(
        pid: '273640665_1787757896',
        uin: 273640665,
        content: '投票动态',
        nickname: '测试昵称',
        location: '广东',
        voteId: 'vote-9',
      ),
      client: _client(const {
        'get_vote_info':
            '{"ret":0,"data":{"vote_id":"vote-9","title":"今晚吃啥",'
                '"mode":1,"multi_mode":1,"end_time":4102444800,'
                '"option_list":[{"index":1,"text":"火锅","count":3},'
                '{"index":2,"text":"烧烤","count":1}]}}',
      }),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('今晚吃啥'), findsOneWidget);
    expect(find.text('火锅'), findsOneWidget);
    expect(find.text('烧烤'), findsOneWidget);
  });

  testWidgets('抽奖：卡片拉取抽奖详情并展示奖品 / 人数 / 状态', (tester) async {
    await pumpCard(
      tester,
      post: const DynamicsPost(
        pid: '273640665_1787757897',
        uin: 273640665,
        content: '抽奖动态',
        nickname: '测试昵称',
        location: '广东',
        lotteryId: 'lot-1',
      ),
      client: _client(const {
        'posting_lottery_query_lottery':
            '{"ret":0,"data":{"list":[{"lottery_id":"lot-1",'
                '"item_id":43000,"item_num":2,"select_num":1,'
                '"lottery_time":4102444800,"status":2,"join_count":7}]}}',
      }),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('奖品 ×2'), findsOneWidget);
    expect(find.textContaining('参与 7 人'), findsOneWidget);
    expect(find.textContaining('进行中'), findsOneWidget);
  });

  testWidgets('视频：videoResId 非空显示「视频」标记', (tester) async {
    const withVideo = DynamicsPost(
      pid: '273640665_1787757894',
      uin: 273640665,
      content: '视频动态',
      nickname: '测试昵称',
      location: '广东',
      videoResId: 'res_9',
    );
    await pumpCard(tester, post: withVideo);
    expect(find.text('视频'), findsOneWidget);

    await pumpCard(tester);
    expect(find.text('视频'), findsNothing);
  });
}
