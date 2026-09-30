import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/gateway.dart'
    show buildFriendRequestUrl, buildGroupUrl, buildMiniwParamMd5Url;
import 'package:mnchat/core/services/miniw_extra.dart'
    show EmojiClient, MiniwParamClient;
import 'package:mnchat/core/services/rich_media.dart' show RichMedia, ShareType;

/// 编码 extend_data：JSON → base64 → url_encode（对齐 friendservice.lua）。
String _encodeExt(Map<String, Object?> m) =>
    Uri.encodeQueryComponent(base64Encode(utf8.encode(jsonEncode(m))));

/// 好友请求 / 群请求 / miniw 参数签名 / 富媒体卡片协议单测。
void main() {
  group('buildFriendRequestUrl（CreateFriendRequest 签名规则）', () {
    test('query 带 cmd 与业务参数，末尾附 auth', () {
      final url = buildFriendRequestUrl(
        server: 'https://x/',
        path: '/server/friend',
        cmd: 'set_note',
        params: {'des_uin': '42', 'note': '备注'},
      );
      expect(url, startsWith('https://x/server/friend?'));
      expect(url, contains('cmd=set_note'));
      expect(url, contains('des_uin=42'));
      expect(url, contains('auth='));
      // 末尾无多余斜杠
      expect(url.contains('https://x//'), isFalse);
    });

    test('参数按 key 升序排列', () {
      final url = buildFriendRequestUrl(
        server: 'https://x',
        path: '/server/friend',
        cmd: 'set_note',
        params: {'z': '1', 'a': '2'},
      );
      final query = Uri.parse(url).query;
      expect(query.indexOf('a=2') < query.indexOf('cmd='), isTrue);
      expect(query.indexOf('cmd=') < query.indexOf('z=1'), isTrue);
    });

    test('notAuthKeys 出现在 query 但不参与签名', () {
      String authOf(String country) => Uri.parse(
        buildFriendRequestUrl(
          server: 'https://x',
          path: '/server/friend',
          cmd: 'get_closeapply_flag',
          params: {'country': country, 'uin': '1'},
          notAuthKeys: {'country'},
        ),
      ).queryParameters['auth']!;

      // notAuth 参数变更不影响 auth；签名参数变更会影响。
      expect(authOf('CN'), authOf('US'));

      String signedAuth(String uin) => Uri.parse(
        buildFriendRequestUrl(
          server: 'https://x',
          path: '/server/friend',
          cmd: 'get_closeapply_flag',
          params: {'country': 'CN', 'uin': uin},
          notAuthKeys: {'country'},
        ),
      ).queryParameters['auth']!;
      expect(signedAuth('1') == signedAuth('2'), isFalse);
    });
  });

  group('buildGroupUrl（CreateGroupChatRequest 签名规则）', () {
    test('act 置于 query 首位并附 auth/s2t/time', () {
      final url = buildGroupUrl(
        server: 'https://x',
        path: '/miniw/group',
        s2: 's2',
        s2t: '&s2t=ST',
        uin: 7,
        act: 'set_group_top',
        extraParams: {'group_id': '9', 'status': '1'},
      );
      expect(url, startsWith('https://x/miniw/group?act=set_group_top'));
      expect(url, contains('group_id=9'));
      expect(url, contains('&md5='));
      expect(url, contains('time='));
    });
  });

  group('ShareType（commonshareinterface.lua 全枚举）', () {
    test('关键取值与反编译一致', () {
      expect(ShareType.text, 0);
      expect(ShareType.map, 1);
      expect(ShareType.skin, 2);
      expect(ShareType.url, 9);
      expect(ShareType.achieve, 10);
      expect(ShareType.pat, 17);
      expect(ShareType.dynamics, 18);
      expect(ShareType.dynamicNotice, 19);
      expect(ShareType.customPanel, 23);
      expect(ShareType.familyInvite, 37);
      expect(ShareType.familyRedPacket, 42);
      expect(ShareType.mscardShare, 52);
    });
  });

  group('RichMedia.decode（新增卡片类型）', () {
    test('拍一拍：识别 isPat 且 subtitle 取 tapText', () {
      final media = RichMedia.decode(
        _encodeExt({'shareType': ShareType.pat, 'tapText': '小明 拍了拍你'}),
      );
      expect(media, isNotNull);
      expect(media!.isPat, isTrue);
      expect(media.title, '拍一拍');
      expect(media.subtitle, '小明 拍了拍你');
    });

    test('自定义面板：标题/内容取 customData', () {
      final media = RichMedia.decode(
        _encodeExt({
          'shareType': ShareType.customPanel,
          'customData': {
            'strTitle': '组队邀请',
            'strContent': '一起来玩',
            'mainTxt': '加入',
          },
        }),
      );
      expect(media!.isCustomPanel, isTrue);
      expect(media.title, '组队邀请');
      expect(media.panelContent, '一起来玩');
      expect(media.subtitle, '一起来玩');
    });

    test('成就分享：识别 isAchieve', () {
      final media = RichMedia.decode(
        _encodeExt({'shareType': ShareType.achieve, 'name': '初次冒险'}),
      );
      expect(media!.isAchieve, isTrue);
      expect(media.title, '成就');
      expect(media.subtitle, '初次冒险');
    });

    test('无法解码时返回 null', () {
      expect(RichMedia.decode('!!!not-base64!!!'), isNull);
    });
  });

  group('MiniwParamClient.buildUrl（http_getParamMD5 + url_addParams）', () {
    test('query 含业务参数 + 全局参数 + time/s2t/encrypt_ver + md5，不含 s2', () {
      final client = MiniwParamClient(
        uin: 123,
        s2: 'SECRET_S2',
        s2t: 'TOK',
        dio: Dio(),
        baseUrl: 'https://x/',
      );
      final url = client.buildUrl('miniw/emoji/act/get_emoji_own_list', {
        'act': 'get_emoji_own_list',
      }, trailing: const ['json=1']);
      expect(url, startsWith('https://x/miniw/emoji/act/get_emoji_own_list?'));
      expect(url, contains('act=get_emoji_own_list'));
      expect(url, contains('encrypt_ver=3'));
      expect(url, contains('&md5='));
      expect(url, endsWith('&json=1'));

      // url_addParams 注入的全局参数 —— 缺了会 400（缺 uin）
      final q = Uri.parse(url).queryParameters;
      expect(q['uin'], '123');
      expect(q['ver'], isNotEmpty);
      expect(q['apiid'], isNotEmpty);
      expect(q['lang'], isNotEmpty);
      expect(q['country'], isNotEmpty);
      expect(q['server_ts'], isNotEmpty);

      // s2 只参与签名，不写进 query
      expect(url.contains('SECRET_S2'), isFalse);
      expect(q.containsKey('s2'), isFalse);
    });

    test('全局参数参与签名：改 uin 会改 md5', () {
      String md5With(int uin) => Uri.parse(
            buildMiniwParamMd5Url(
              baseUrl: 'https://x',
              path: '/miniw/business',
              params: const {'act': 'query_portrait'},
              uin: uin,
              s2: 's2',
              s2t: 't',
              now: 1700000000,
            ),
          ).queryParameters['md5']!;

      expect(md5With(1) == md5With(2), isFalse);
    });

    test('同一入参 → 稳定 URL（now 固定时），且 path 有无前导斜杠等价', () {
      String urlOf(String path) => buildMiniwParamMd5Url(
            baseUrl: 'https://x/',
            path: path,
            params: const {'act': 'a'},
            uin: 9,
            s2: 's2',
            s2t: 't',
            now: 1700000000,
          );

      expect(urlOf('/miniw/title'), urlOf('miniw/title'));
      expect(urlOf('miniw/title'), contains('uin=9'));
    });

    test('trailing（json=1）不参与签名', () {
      String md5Of(List<String> trailing) => Uri.parse(
            buildMiniwParamMd5Url(
              baseUrl: 'https://x',
              path: '/miniw/emoji/act/x',
              params: const {'act': 'x'},
              uin: 1,
              s2: 's2',
              s2t: 't',
              trailing: trailing,
              now: 1700000000,
            ),
          ).queryParameters['md5']!;

      expect(md5Of(const ['json=1']), md5Of(const []));
    });

    test('表情客户端继承同一签名端点', () {
      final emoji = EmojiClient(
        uin: 1,
        s2: 's2',
        s2t: 't',
        dio: Dio(),
        baseUrl: 'https://x',
      );
      expect(emoji, isA<MiniwParamClient>());
    });
  });
}
