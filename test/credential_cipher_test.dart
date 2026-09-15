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
      // 原地替换 cipher 的第一个 base64 字符（长度不变、仍是合法 base64），
      // 让 MAC 校验成为唯一的失败原因。
      //
      // 不要改成「前插字符」的写法：那会把 base64 长度从 24 变成 25
      // （≡1 mod 4），base64Decode 会先抛 FormatException，既掩盖了真正要验证
      // 的 MAC 路径，又只有 1/64 的触发概率——表现出来就是偶发 flaky。
      final tail = parts[3];
      final flipped = '${tail[0] == 'A' ? 'B' : 'A'}${tail.substring(1)}';
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

    test('base64 长度非法时返回 null 而非抛异常', () {
      final stored = encryptPassword('secret', 123);
      final parts = stored.split(':');
      // 前插一位 → 长度 24→25（≡1 mod 4）。旧实现会让 base64Decode 抛出
      // FormatException 逃逸到调用方（启动路径），此处即该路径的回归锁。
      final tampered = '${parts[0]}:${parts[1]}:${parts[2]}:B${parts[3]}';
      expect(decryptPassword(tampered, 123), isNull);
    });

    test('base64 含非法字符时返回 null 而非抛异常', () {
      expect(decryptPassword('v1:AAAA:deadbeef:!!!not-base64!!!', 123), isNull);
    });
  });
}
