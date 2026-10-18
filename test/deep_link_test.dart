// 深链解析的纯函数验证：合法形态全认、脏数据一律 null（不抛）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/deep_link.dart';
import 'package:mnchat/core/models/messages.dart' show ChatSessionType;

void main() {
  group('会话深链', () {
    test('mnchat://friend/<uin> 与 mnchat://group/<id>', () {
      final f = parseDeepLink('mnchat://friend/273640665');
      expect(f?.isSession, isTrue);
      expect(f?.sessionType, ChatSessionType.friend);
      expect(f?.sessionId, 273640665);
      expect(f?.sessionKey, 'friend_273640665');

      final g = parseDeepLink('mnchat://group/10086');
      expect(g?.sessionType, ChatSessionType.group);
      expect(g?.sessionKey, 'group_10086');
    });

    test('显式 open 形式与大小写不敏感', () {
      final a = parseDeepLink('mnchat://open/group/7');
      expect(a?.sessionType, ChatSessionType.group);
      expect(a?.sessionId, 7);

      final b = parseDeepLink('MNCHAT://FRIEND/9');
      expect(b?.sessionType, ChatSessionType.friend);
      expect(b?.sessionId, 9);
    });

    test('裸会话 key（通知/intent 形态）也认', () {
      expect(parseDeepLink('friend_123')?.sessionKey, 'friend_123');
      expect(parseDeepLink('group_456')?.sessionKey, 'group_456');
    });

    test('尾部斜杠与查询串/片段不影响解析', () {
      expect(parseDeepLink('mnchat://friend/5/')?.sessionId, 5);
      expect(parseDeepLink('mnchat://friend/5?from=push')?.sessionId, 5);
      expect(parseDeepLink('mnchat://search?q=abc#x')?.view, DeepLinkView.search);
    });
  });

  group('页面深链', () {
    test('favorites / search / partners 三个固定页面', () {
      expect(parseDeepLink('mnchat://favorites')?.view, DeepLinkView.favorites);
      expect(parseDeepLink('mnchat://star')?.view, DeepLinkView.favorites);
      expect(parseDeepLink('mnchat://search')?.view, DeepLinkView.search);
      expect(parseDeepLink('mnchat://partners')?.view, DeepLinkView.partners);
      // 无 host 的简写形式
      expect(parseDeepLink('mnchat:favorites')?.view, DeepLinkView.favorites);
    });

    test('video 深链带地址（也认 src，本地路径同样收）', () {
      final v = parseDeepLink('mnchat://video?url=https%3A%2F%2Fa.b%2Fc.mp4');
      expect(v?.isVideo, isTrue);
      expect(v?.videoUrl, 'https://a.b/c.mp4');
      expect(v?.isSession, isFalse);
      expect(v?.view, isNull);
      expect(parseDeepLink('mnchat://play?src=/tmp/a.mp4')?.videoUrl, '/tmp/a.mp4');
      // 本地路径自带的 query 不能被吃掉
      expect(
        parseDeepLink('mnchat://video?url=%2Ftmp%2Fx.mp4%3Ft%3D1')?.videoUrl,
        '/tmp/x.mp4?t=1',
      );
    });
  });

  group('脏数据', () {
    test('无法识别的输入全部返回 null', () {
      for (final bad in <String?>[
        null,
        '',
        '   ',
        'https://example.com/friend/1', // scheme 不符
        'mnchat://', // 没有 host/path
        'mnchat://friend/0', // id 非正
        'mnchat://friend/abc', // id 非数字
        'mnchat://friend', // 缺 id
        'mnchat://unknown/1', // 未知 host
        'mnchat://video', // 缺地址
        'mnchat://video?url=', // 空地址
        'mnchat://video?url=%20', // 只有空白
        'friend_',
        'friend_0',
        'bogus_1',
        'friend_-3',
      ]) {
        expect(parseDeepLink(bad), isNull, reason: '应拒绝: $bad');
      }
    });
  });
}
