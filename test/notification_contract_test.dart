// 通知动作契约：Linux 的「标记已读」与「打开」分流；无实现的平台给空流。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/notification_service.dart';

void main() {
  test('action key 映射：mark-read 才标记已读，其余都当打开', () {
    expect(notificationActionFrom('mark-read'), NotificationAction.markRead);
    expect(notificationActionFrom('default'), NotificationAction.open);
    expect(notificationActionFrom('打开'), NotificationAction.open);
    expect(notificationActionFrom(''), NotificationAction.open);
  });

  test('Noop 服务的点击/标记已读流为空且可安全监听', () async {
    final svc = NoopNotificationService();
    expect(await svc.taps.isEmpty, isTrue);
    expect(await svc.readRequests.isEmpty, isTrue);
    await svc.showMessage(
      const MessageNotification(
        sessionKey: 'friend_1',
        title: 't',
        text: 'x',
        group: false,
      ),
    );
    await svc.cancel('friend_1');
    await svc.cancelAll();
    await svc.setBackgroundMode(true);
    expect(await svc.initialTapSessionKey(), isNull);
    svc.dispose();
  });

  test('MessageNotification 携带按会话的提示音/震动/分组标志', () {
    const n = MessageNotification(
      sessionKey: 'group_9',
      title: '群',
      text: 'hi',
      group: true,
      sound: false,
      vibrate: false,
      lines: ['a', 'b'],
    );
    expect(n.group, isTrue);
    expect(n.sound, isFalse);
    expect(n.vibrate, isFalse);
    expect(n.lines, hasLength(2));
  });
}
