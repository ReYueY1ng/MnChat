// 邮件导航状态：选中切换、类型筛选、已关注集合的通知语义。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/msg_box.dart' show MsgBoxEntry;
import 'package:mnchat/ui/mail_navigation_controller.dart';
import 'package:mnchat/ui/mail_page.dart' show MailSelection;

void main() {
  test('select 只在变化时通知', () {
    final nav = MailNavigationController(const MailSelection.channel(1));
    var notified = 0;
    nav.addListener(() => notified++);

    nav.select(const MailSelection.channel(1));
    expect(notified, 0);

    nav.select(const MailSelection.channel(2));
    expect(nav.selected.channel, 2);
    expect(notified, 1);
  });

  test('typeFilter 去重赋值；markFollowed 幂等', () {
    final nav = MailNavigationController(const MailSelection.channel(1));
    var notified = 0;
    nav.addListener(() => notified++);

    nav.typeFilter = '全部';
    nav.typeFilter = '全部';
    expect(notified, 1);
    expect(nav.typeFilter, '全部');

    nav.markFollowed(42);
    nav.markFollowed(42);
    expect(notified, 2);
    expect(nav.followed, {42});
  });

  test('入口与频道互斥切换', () {
    final nav = MailNavigationController(const MailSelection.channel(1));
    nav.select(const MailSelection.entry(MsgBoxEntry.dynamics));
    expect(nav.selected.isEntry, isTrue);
    expect(nav.selected.channel, isNull);
  });
}
