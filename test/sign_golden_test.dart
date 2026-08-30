import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/crypto/md5_sign.dart';

/// 签名 golden 测试 —— 用 MNClient (Python 参考实现) 生成的基准值锁定行为。
/// 参考: /home/yuey1ng/mini/MNClient/src/mnclient/crypto/sign.py
void main() {
  const t = 1700000000;
  const s2 = 'abc123';
  const s2t = '789xyz';
  const uin = 2089540493;

  group('md5_sign / md5_token', () {
    test('md5Sign joins parts and hashes', () {
      expect(md5Sign(['msg=', 'data', '&key=', 'key123']), '76eeca38d3d326519a91d2fec94cff56');
    });

    test('md5Token = md5(time+s2+uin)', () {
      expect(md5Token(t, s2, uin), '354c925a701b213ad6b614cf84d77c73');
    });
  });

  group('http_get_s1 family', () {
    test('httpGetS1', () {
      expect(httpGetS1(t, s2, uin, s2t), 'time=1700000000&md5=354c925a701b213ad6b614cf84d77c73&s2t=789xyz');
    });

    test('httpGetS1Map uses auth=', () {
      expect(httpGetS1Map(t, s2, uin, s2t), 'time=1700000000&auth=354c925a701b213ad6b614cf84d77c73&s2t=789xyz');
    });

    test('httpGetS1MapWx', () {
      expect(httpGetS1MapWx(1234567890, t), 'time=1700000000&auth=918ebff3431a057aaa49c6408f6d490b&open_id=1234567890');
    });

    test('httpGetS2', () {
      expect(httpGetS2(s2, s2t, t), '&s2t=789xyz&ts=1700000000&auth=c7f13d9712607facf2852c93b90a15b5');
    });
  });

  group('http_get_param_md5', () {
    test('general param md5', () {
      expect(
        httpGetParamMd5(
          {'act': 'query_friend_list', 'uin': '$uin', 'apiid': '110', 'ver': '1.58.0', 'country': 'CN', 'lang': '0'},
          timeVal: t,
          s2: s2,
          s2t: s2t,
        ),
        '892d2d9961be9e39e25c70ce06d755db',
      );
    });

    test('room server param md5 (whitelist)', () {
      expect(
        httpGetParamMd5RoomServer(
          {'cmd': 'query', 'uin': '$uin', 'country': 'CN', 'lang': '0'},
          timeVal: t,
          s2t: s2t,
        ),
        '5fbcbf07f44009326dc23bbfc21dfcad',
      );
    });
  });

  group('s2_act / guard_map', () {
    test('httpGetS2Act', () {
      expect(httpGetS2Act('query_user_groups', t, s2, uin, s2t),
          'time=1700000000&auth=2ee1ea0709abad66499a77f9a4a065f9&s2t=789xyz');
    });

    test('httpGetS1GuardMap ab_test_all', () {
      expect(httpGetS1GuardMap('ab_test_all', t, s2, uin, s2t),
          'time=1700000000&uin=2089540493&auth=354c925a701b213ad6b614cf84d77c73&s2t=789xyz');
    });

    test('httpGetS1GuardMap ab_test_device_all', () {
      expect(httpGetS1GuardMap('ab_test_device_all', t, s2, uin, s2t, deviceId: 'Dev1'),
          'time=1700000000&device_id=Dev1&auth=20e617b8737cd0b41d8c8e23709b4167');
    });
  });

  group('realname / friend / group sign', () {
    test('httpGetRealNameMobileSum', () {
      expect(
        httpGetRealNameMobileSum('hello', uin: uin, s2t: s2t, mmsumData: 'a' * 32 + 'xy' + '$t', nowVal: t + 100),
        'mmsum=100xy1084fd264b1700000000&cthash=7224038100',
      );
    });

    test('createFriendRequestSign', () {
      expect(createFriendRequestSign('a=1&b=2&cmd=x'), '0cae22129321c3e35a5cd0e6bdbaf2cc');
    });

    test('createGroupChatRequestSign == httpGetS1', () {
      expect(createGroupChatRequestSign(t, s2, uin, s2t),
          'time=1700000000&md5=354c925a701b213ad6b614cf84d77c73&s2t=789xyz');
    });
  });
}