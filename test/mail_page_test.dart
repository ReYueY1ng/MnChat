import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/map_info.dart';
import 'package:mnchat/core/services/message_center.dart';
import 'package:mnchat/core/services/msg_box.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/mail_page.dart';
import 'package:mnchat/ui/theme/app_theme.dart';

/// 消息中心真实页面回归测试（pump 真正的 [MailPage]，服务用假客户端接管）。
///
/// 覆盖：
/// - 宽屏双栏：左列 7 分类标题 + 顶部 3 入口渲染；
/// - 选择分类 → 右栏显示该分类消息（标题/正文/详情/底部按钮）；
/// - 默认顶部"动态互动" → 显示互动通知（行动作 + `N小时前 IP 省`）；
/// - 窄屏：单栏列表，点分类 push 详情页。
class _FakeCenter extends MessageCenterClient {
  _FakeCenter() : super(uin: 10001, s2: 's', s2t: 't');

  @override
  Future<(List<MsgFlowEntry>, int)> fetchMsgFlow(
    int channel, {
    int lastTime = 0,
    bool history = false,
  }) async {
    if (channel != MsgChannel.systemMail) return (<MsgFlowEntry>[], 0);
    return (
      const [
        MsgFlowEntry(id: 'm1', type: 1, ts: 1700000000),
        MsgFlowEntry(id: 'm2', type: 1, ts: 1700000100),
      ],
      2,
    );
  }

  @override
  Future<Map<String, MsgItem>> fetchMsgByIDs(
    int channel,
    List<String> ids,
  ) async {
    final out = <String, MsgItem>{};
    for (final id in ids) {
      out[id] = MsgItem(
        id: id,
        channel: channel,
        title: id == 'm1' ? '欢迎使用MNChat' : '系统维护公告',
        content: '正文-$id',
        createTime: id == 'm1' ? 1700000000 : 1700000100,
        readState: 0,
      );
    }
    return out;
  }

  @override
  Future<Map<int, ChannelSummary>> fetchChannelsInfo(
    List<int> channels,
  ) async =>
      {
        for (final c in channels)
          c: ChannelSummary(
            channel: c,
            unread: c == MsgChannel.systemMail ? 2 : 0,
            total: 2,
          ),
      };

  @override
  Future<bool> readMessages(int channel, List<String> ids) async => true;

  @override
  Future<bool> deleteMessages(int channel, List<String> ids) async => true;

  @override
  Future<Set<String>> takeAttachments(int channel, List<String> ids) async =>
      ids.toSet();
}

class _FakeBox extends MsgBoxClient {
  _FakeBox() : super(uin: 10001, s2: 's', s2t: 't');

  @override
  Future<MsgBoxPage> getChannelMsgList(String channel, {int offset = 0}) async {
    if (channel == MsgBoxChannel.rep) {
      return const MsgBoxPage(
        [
          MsgBoxMessage(
            msgId: 'r1',
            channel: MsgBoxChannel.rep,
            msgType: 'commented',
            uin: 20002,
            content: '好棒',
            pidContent: '我的第一条动态',
            pid: '20002_1700000000',
            time: 1700000000,
            location: '广东',
          ),
        ],
        0,
      );
    }
    if (channel == MsgBoxChannel.mapInteract) {
      return const MsgBoxPage(
        [
          MsgBoxMessage(
            msgId: 'w1',
            channel: MsgBoxChannel.mapInteract,
            msgType: 'map_prize',
            uin: 20003,
            content: '这图好玩',
            time: 1700000000,
            data: {'map_id': 42},
          ),
          MsgBoxMessage(
            msgId: 'w2',
            channel: MsgBoxChannel.mapInteract,
            msgType: 'template_like',
            uin: 20004,
            time: 1700000100,
            data: {'name': '大乱斗模板'},
          ),
        ],
        0,
      );
    }
    return MsgBoxPage.empty;
  }

  @override
  Future<Map<String, int>> getChannelMsgListX(List<String> channels) async =>
      {for (final c in channels) c: 0};
}

class _FakeMapInfo extends MapInfoClient {
  _FakeMapInfo() : super(uin: 10001, s2: 's', s2t: 't');

  @override
  Future<Map<String, String>> fetchMapNames(List<String> owids) async =>
      {for (final id in owids) id: '一个幸运方块生存'};
}

void main() {
  Future<void> pumpMailPage(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          messageCenterClientProvider.overrideWithValue(_FakeCenter()),
          msgBoxClientProvider.overrideWithValue(_FakeBox()),
          mapInfoClientProvider.overrideWithValue(_FakeMapInfo()),
          dynamicsClientProvider.overrideWithValue(null),
          profileClientProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const MailPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('宽屏：左列 7 分类 + 顶部 3 入口渲染', (tester) async {
    await pumpMailPage(tester);
    expect(tester.takeException(), isNull);

    for (final title in const [
      '礼物消息',
      '官方邮件',
      '创作者助手',
      '系统消息',
      '好友邮件',
      '动态助手',
      '运营活动',
    ]) {
      expect(find.text(title), findsWidgets, reason: '缺少分类: $title');
    }
    for (final entry in const ['动态互动', '新增粉丝', '作品互动']) {
      expect(find.text(entry), findsWidgets, reason: '缺少入口: $entry');
    }
  });

  testWidgets('宽屏：选择分类显示该分类消息 + 详情 + 底部按钮', (tester) async {
    await pumpMailPage(tester);
    await tester.tap(find.text('官方邮件').first);
    await tester.pumpAndSettle();

    // 左列摘要就是最新一封邮件的**标题**（对齐游戏 tfContent = strTitle），
    // 所以最新那封的标题在左列行和右栏卡片各出现一次。
    expect(find.text('系统维护公告'), findsNWidgets(2),
        reason: '左列摘要 + 右栏卡片');
    expect(find.text('欢迎使用MNChat'), findsOneWidget, reason: '旧的一封只在右栏');
    expect(find.text('详情'), findsWidgets);
    expect(find.text('一键已读'), findsOneWidget);
    expect(find.text('删除已读'), findsOneWidget);
  });

  testWidgets('宽屏：默认动态互动显示互动通知（行动作 + IP 时间）', (tester) async {
    await pumpMailPage(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('评论了你的动态'), findsWidgets);
    expect(find.textContaining('IP 广东'), findsWidgets);
  });

  group('时间与来源格式化（对齐 convertTime2 / GetMailDesc）', () {
    test('邮件卡时间：固定 YYYY-MM-DD HH:MM', () {
      expect(fmtMailTime(0), '');
      expect(
        fmtMailTime(1700000000),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')),
      );
    });

    test('左列时间：半年内 MM-DD HH:MM，更早 YYYY-MM-DD', () {
      expect(fmtMailTimeShort(0), '');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        fmtMailTimeShort(now - 60),
        matches(RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}$')),
      );
      expect(
        fmtMailTimeShort(now - 200 * 86400),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
    });
  });

  testWidgets('宽屏：作品互动卡片显示作品名 / 模板名（行动作 + 参数）', (tester) async {
    await pumpMailPage(tester);
    await tester.tap(find.text('作品互动').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('赞了你的作品："一个幸运方块生存"'),
      findsWidgets,
      reason: '作品名由 map_id 查表补上（chatworksmsg.lua:203）',
    );
    expect(
      find.textContaining('赞了你的模板："大乱斗模板"'),
      findsWidgets,
      reason: '模板名直接来自 data.name（chatworksmsg.lua:150）',
    );
  });

  testWidgets('窄屏：单栏列表，点分类 push 详情页', (tester) async {
    await pumpMailPage(tester, size: const Size(420, 900));
    expect(tester.takeException(), isNull);

    // 单栏：右栏（底部按钮）不出现
    expect(find.text('一键已读'), findsNothing);

    await tester.tap(find.text('官方邮件'));
    await tester.pumpAndSettle();
    // push 的详情页：AppBar 标题 + 消息 + 底部按钮
    expect(find.text('欢迎使用MNChat'), findsOneWidget);
    expect(find.text('一键已读'), findsOneWidget);
    expect(find.text('删除已读'), findsOneWidget);
  });
}
