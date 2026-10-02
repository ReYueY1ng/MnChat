import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/gift_catalog.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/core/services/chat/online_notify.dart';
import 'package:mnchat/core/services/rich_media.dart';
import 'package:mnchat/state/providers.dart' show giftCatalogProvider;
import 'package:mnchat/ui/widgets/gift_picker.dart' show GiftPickerPanel;

/// 礼物卡（`Type = SendFriendGift`）与好友上线通知。
void main() {
  /// 游戏真实发的 extend_data：url_encode(base64(JSON{...}))
  /// （`friendgiftdatamgr.lua:404-423`）。
  String giftExtendData({
    int itemid = 43004,
    int num = 2,
    int addValue = 20,
  }) {
    final json = jsonEncode({
      'Type': 'SendFriendGift',
      'itemid': itemid,
      'num': num,
      'addValue': addValue,
      'des_uin': 1001,
      'src_uin': 2002,
      'src_name': '小明',
      'token': 'abc',
    });
    return Uri.encodeQueryComponent(base64Encode(utf8.encode(json)));
  }

  group('RichMedia：礼物卡', () {
    test('解析出礼物 id / 数量 / 默契度 / 送礼人，并识别成卡片', () {
      final m = RichMedia.decode(giftExtendData())!;
      expect(m.isFriendGift, isTrue);
      // 是卡片 → 消息要走富媒体气泡（否则只会显示那句兜底文案）
      expect(m.isCard, isTrue);
      expect(m.giftItemId, 43004);
      expect(m.giftNum, 2);
      expect(m.giftAddValue, 20);
      expect(m.giftSrcName, '小明');
      expect(m.title, '默契礼物');
      expect(m.subtitle, contains('小明'));
    });

    test('普通文本气泡（shareType=0 + bubble）不算卡片', () {
      final json = jsonEncode({'shareType': 0, 'bubble': 1, 'nickname': 'x'});
      final m = RichMedia.decode(
        Uri.encodeQueryComponent(base64Encode(utf8.encode(json))),
      )!;
      expect(m.isCard, isFalse);
    });

    test('红包 / 房间邀请 / 拍一拍仍然算卡片', () {
      for (final raw in [
        {'Type': 'SendFriendRedPocket', 'amount': 10},
        {'Type': 'InviteJoinRoom', 'RoomName': '房'},
        {'shareType': ShareType.pat, 'tapText': '拍了拍你'},
      ]) {
        final m = RichMedia.decode(
          Uri.encodeQueryComponent(base64Encode(utf8.encode(jsonEncode(raw)))),
        )!;
        expect(m.isCard, isTrue, reason: '$raw');
      }
    });
  });

  group('好友上线通知', () {
    ChatSession friend(int uin, {bool online = false}) => ChatSession(
      id: uin,
      type: ChatSessionType.friend,
      name: '好友$uin',
      relation: 8,
      isOnline: online,
    );

    test('onlineFriendUins 只算在线好友（群聊不算）', () {
      final uins = onlineFriendUins([
        friend(1, online: true),
        friend(2),
        ChatSession(
          id: 99,
          type: ChatSessionType.group,
          name: '群',
          isOnline: true,
        ),
      ]);
      expect(uins, {1});
    });

    test('newlyOnlineFriends 只报离线→在线的跳变', () {
      // 1 一直在线（不提醒）、2 新上线（提醒）、3 下线（不提醒）
      expect(newlyOnlineFriends({1}, {1, 2}), {2});
      expect(newlyOnlineFriends({1, 2}, {1}), isEmpty);
      expect(newlyOnlineFriends(<int>{}, {5}), {5});
    });
  });

  /// 赠送面板的标题是纯文本，收礼人名字必须洗过 —— 线上真机踩到过
  /// 「赠送礼物给 [i][color][b]顾念」。
  group('礼物面板标题的昵称清洗', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      required int uin,
      required String name,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            giftCatalogProvider.overrideWith((ref) => GiftCatalog.empty),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: GiftPickerPanel(
                  hostRef: ref,
                  uin: uin,
                  name: name,
                  onDone: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('富文本标记被清掉', (tester) async {
      await pumpPanel(tester, uin: 4242, name: '[i][color][b]顾念');
      expect(find.text('赠送礼物给 顾念'), findsOneWidget);
      expect(find.textContaining('['), findsNothing);
    });

    testWidgets('昵称只由标记组成时回退迷你号', (tester) async {
      await pumpPanel(tester, uin: 4242, name: '[i][b]');
      expect(find.text('赠送礼物给 4242'), findsOneWidget);
    });

    testWidgets('正常昵称原样显示', (tester) async {
      await pumpPanel(tester, uin: 4242, name: '小明');
      expect(find.text('赠送礼物给 小明'), findsOneWidget);
    });
  });
}
