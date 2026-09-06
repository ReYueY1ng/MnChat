import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/crypto/credential_cipher.dart';

void main() {
  group('encryptPassword / decryptPassword', () {
    test('roundtrip 返回原文', () {
      const pwd = 'myPass123';
      final stored = encryptPassword(pwd, 123456);
      expect(stored.startsWith('v1:'), isTrue);
      expect(stored.contains(pwd), isFalse, reason: '密文不应包含明文');
      expect(decryptPassword(stored, 123456), pwd);
    });

    test('不同 uin 产生不同密文', () {
      const pwd = 'samePassword';
      expect(encryptPassword(pwd, 111), isNot(equals(encryptPassword(pwd, 222))));
    });

    test('错误 uin 解不出原文', () {
      final stored = encryptPassword('secret', 123);
      expect(decryptPassword(stored, 456), isNull);
    });

    test('篡改密文被检测', () {
      final stored = encryptPassword('secret', 123);
      final parts = stored.split(':');
      // 改 cipher 的 base64 字符（保持合法 base64），MAC 校验应失败。
      final tail = parts[3];
      final flipped = tail.startsWith('A') ? 'B$tail' : 'A${tail.substring(1)}';
      final tampered = '${parts[0]}:${parts[1]}:${parts[2]}:$flipped';
      expect(decryptPassword(tampered, 123), isNull);
    });

    test('旧版明文密码兼容返回原文', () {
      expect(decryptPassword('plainOldPassword', 123), 'plainOldPassword');
    });

    test('非法格式返回 null', () {
      expect(decryptPassword('v1:broken', 123), isNull);
      expect(decryptPassword('', 123), isEmpty);
    });
  });
}
