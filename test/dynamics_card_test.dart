import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/dynamics.dart';
import 'package:mnchat/state/providers.dart';
import 'package:mnchat/ui/theme/app_theme.dart';
import 'package:mnchat/ui/widgets/avatar_view.dart';
import 'package:mnchat/ui/widgets/dynamics_card.dart';
import 'package:mnchat/ui/widgets/rich_text_view.dart';

/// 动态卡片头部回归测试。
///
/// - 昵称 / 时间文字块与头像垂直居中对齐（行仍为 center）；
/// - 「关注」按钮钉在行右上角（顶边与行顶边对齐、右缘贴行右缘）；
/// - 作者已是好友（bit3=8）或已被我关注（bit4=16）时不再显示「关注」按钮。
void main() {
  const post = DynamicsPost(
    pid: '273640665_1787757890',
    uin: 273640665,
    content: '测试动态正文',
    nickname: '测试昵称',
    location: '广东',
  );

  /// pump 动态卡片；[contacts] 注入联系人流（默认空 = 未加载）。
  Future<void> pumpCard(
    WidgetTester tester, {
    List<Contact> contacts = const <Contact>[],
    bool isMine = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactsProvider.overrideWith((_) => Stream.value(contacts)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(body: DynamicsCard(post: post, isMine: isMine)),
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
}
