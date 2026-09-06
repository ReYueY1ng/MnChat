/// 自动登录凭据的本地加密工具。
///
/// 用 AES-CBC + 随机 IV + HMAC-SHA256 认证标签对密码做可逆加密，
/// 密钥由固定盐与账号 uin 派生（每个账号密文不同）。目标是防止
/// "数据库文件被读取/备份泄露时密码直接可见" 这一级别的威胁——
/// 注意这是客户端逆向项目的固有局限：能拿到代码的攻击者总能
/// 提取密钥，因此这不是防 root/调试器的银行级安全。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// 派生密钥用的固定盐（与 uin 拼接后做 SHA-256）。
const String kCredentialSalt = 'mnchat::credential::v1';

/// 加密结果的前缀（用于识别格式/版本）。
const String kCredentialPrefix = 'v1:';

/// 加密密码，返回 `v1:<ivBase64>:<macHex>:<cipherBase64>`。
String encryptPassword(String password, int uin) {
  final key = _deriveKey(uin);
  final rng = Random.secure();
  final iv = enc.IV(
    Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256))),
  );
  final encrypter = enc.Encrypter(enc.AES(key));
  final cipher = encrypter.encrypt(password, iv: iv);
  final mac = _hmac(key.bytes, [...iv.bytes, ...cipher.bytes]);
  return '$kCredentialPrefix${base64Encode(iv.bytes)}:$mac:${cipher.base64}';
}

/// 解密密码；存储格式非法、版本不匹配或 MAC 校验失败（数据被篡改）时
/// 返回 null。旧版本保存的**明文**密码（非 `v1:` 前缀）原样返回，做平滑迁移。
String? decryptPassword(String stored, int uin) {
  if (!stored.startsWith(kCredentialPrefix)) return stored; // 旧版明文兼容
  final parts = stored.split(':');
  if (parts.length != 4) return null;
  final ivBytes = base64Decode(parts[1]);
  final mac = parts[2];
  final cipherBytes = base64Decode(parts[3]);
  final key = _deriveKey(uin);
  final expected = _hmac(key.bytes, [...ivBytes, ...cipherBytes]);
  if (!_constEq(expected, mac)) return null; // 篡改检测
  final encrypter = enc.Encrypter(enc.AES(key));
  return encrypter.decrypt(enc.Encrypted(cipherBytes), iv: enc.IV(ivBytes));
}

/// 由 (盐, uin) 派生 32 字节 AES 密钥。
enc.Key _deriveKey(int uin) => enc.Key(
  Uint8List.fromList(
    sha256.convert(utf8.encode('$kCredentialSalt:$uin')).bytes,
  ),
);

String _hmac(Uint8List keyBytes, List<int> data) =>
    Hmac(sha256, keyBytes).convert(data).toString();

/// 常数时间比较十六进制字符串，防时序侧信道。
bool _constEq(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
