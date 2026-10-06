import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/dynamics.dart';
import 'package:mnchat/ui/dynamics_detail_page.dart';
import 'package:mnchat/ui/dynamics_notice_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

/// 动态通知页回归测试。
///
/// 覆盖：
/// - 六个频道 tab 按游戏 `DynamicsChannelType` 顺序渲染；
/// - 带 pid 的条目可点，空 pid（粉丝 / 系统 / 地图等）条目不可点，也不会拉动态；
/// - 进入频道即上报已读；
/// - 未登录 / 依赖未就绪时降级为占位态，不抛异常。
class _FakeDynamics extends DynamicsClient {
  _FakeDynamics(this.byChannel) : super(uin: 10001, s2: 's2', s2t: 's2t');

  final Map<String, List<DynamicsNotice>> byChannel;
  final List<String> readCalls = [];
  final List<String> postRequests = [];

  @override
  Future<(List<DynamicsNotice>, int)> fetchChannelNotice(
    String channel, {
    int offset = 0,
  }) async {
    if (offset > 0) return (<DynamicsNotice>[], 0);
    return (byChannel[channel] ?? const <DynamicsNotice>[], 0);
  }

  @override
  Future<bool> readChannelNotice(String channel, List<String> msgIds) async {
    readCalls.add('$channel:${msgIds.join(',')}');
    return true;
  }

  @override
  Future<DynamicsPost?> fetchPost(String pid) async {
    postRequests.add(pid);
    return null;
  }
}

/// 带 pid：可以点开动态详情。
const _withPid = DynamicsNotice(
  msgId: 'm1',
  channel: DynamicsNoticeChannel.rep,
  msgType: 'post_rep',
  uin: 20002,
  nickname: '评论者',
  content: '收到一条评论',
  pid: '20002_1700000000',
  time: 1700000000,
);

/// 空 pid：粉丝类通知，没有可跳转的动态。
const _noPid = DynamicsNotice(
  msgId: 'm2',
  channel: DynamicsNoticeChannel.rep,
  msgType: 'fans_change',
  uin: 20003,
  nickname: '小美',
  content: '小美关注了你',
  time: 1700000100,
);

const _allLabels = ['评论', '点赞', '@我', '粉丝', '系统', '地图'];

void main() {
  Future<void> pumpPage(WidgetTester tester, {DynamicsClient? client}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: DynamicsNoticePage(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('六个通知频道 tab 按游戏顺序渲染', (tester) async {
    await pumpPage(
      tester,
      client: _FakeDynamics(const {
        DynamicsNoticeChannel.rep: [_withPid, _noPid],
      }),
    );
    expect(tester.takeException(), isNull);

    final bar = tester.widget<TabBar>(find.byType(TabBar));
    final labels = [for (final t in bar.tabs) (t as Tab).text ?? ''];
    expect(labels, _allLabels);

    // 六个标签在 TabBar 内实际渲染，且从左到右顺序一致。
    final xs = [
      for (final l in labels)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(TabBar),
                matching: find.text(l),
              ),
            )
            .dx,
    ];
    expect(xs, orderedEquals(List<double>.of(xs)..sort()));
  });

  testWidgets('带 pid 的条目可点；空 pid 的条目不可点', (tester) async {
    final fake = _FakeDynamics(const {
      DynamicsNoticeChannel.rep: [_withPid, _noPid],
    });
    await pumpPage(tester, client: fake);
    expect(tester.takeException(), isNull);

    ListTile tileOf(String text) => tester.widget<ListTile>(
      find
          .ancestor(of: find.text(text), matching: find.byType(ListTile))
          .first,
    );

    expect(tileOf('收到一条评论').onTap, isNotNull, reason: '带 pid 的条目可点开动态详情');
    expect(tileOf('小美关注了你').onTap, isNull, reason: '空 pid 的条目不可点');

    await tester.tap(find.text('小美关注了你'));
    await tester.pumpAndSettle();
    expect(fake.postRequests, isEmpty, reason: '空 pid 条目不应触发 fetchPost');
    expect(find.byType(DynamicsDetailPage), findsNothing);

    expect(fake.readCalls, hasLength(1), reason: '进入频道应上报一次已读');
    expect(fake.readCalls.single, '${DynamicsNoticeChannel.rep}:m1,m2');
  });

  testWidgets('未登录 / 依赖未就绪时降级为占位态，不抛异常', (tester) async {
    // 裸 ProviderScope：databaseProvider 未 override，取 auth 会抛；
    // 页面应降级为「未登录」而不是把异常抛到 widget 树。
    await pumpPage(tester, client: null);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('未登录'), findsWidgets);

    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.tabs.length, 6, reason: '未登录也要渲染六个频道 tab');
  });
}
