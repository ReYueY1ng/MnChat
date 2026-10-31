/// 加密备份容器：PBKDF2-HMAC-SHA256 派生密钥 + AES-256-GCM。
///
/// 文件是 JSON 信封（便于识别与版本化），字段全部 base64：
/// `{"format":"mnchat-backup","v":2,"enc":"aes-gcm","kdf":"pbkdf2-hmac-sha256",
///   "iterations":100000,"salt":"...","nonce":"...","ciphertext":"...","tag":"..."}`
///
/// 口令错误 / 文件被篡改时抛 [BackupDecryptException]，绝不返回半截明文。
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// 加密备份的容器版本。
const int kEncryptedBackupVersion = 2;

/// 默认 KDF 迭代次数（测试可调低以加速）。
const int kDefaultBackupIterations = 100000;

/// 解密失败（口令错误、容器损坏、被篡改）。
class BackupDecryptException implements Exception {
  const BackupDecryptException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 是不是加密备份容器（不抛：任何解析失败都返回 false）。
bool isEncryptedBackup(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map && decoded['enc'] == 'aes-gcm';
  } catch (_) {
    return false;
  }
}

/// 加密 JSON 明文，返回信封字节。
Future<List<int>> encryptBackup(
  List<int> plain, {
  required String passphrase,
  int iterations = kDefaultBackupIterations,
  Random? random,
}) async {
  final rng = random ?? Random.secure();
  final salt = List<int>.generate(16, (_) => rng.nextInt(256));
  final nonce = List<int>.generate(12, (_) => rng.nextInt(256));
  final key = await _derive(passphrase, salt, iterations);
  final box = await AesGcm.with256bits().encrypt(
    plain,
    secretKey: key,
    nonce: nonce,
  );
  return utf8.encode(
    jsonEncode({
      'format': 'mnchat-backup',
      'v': kEncryptedBackupVersion,
      'enc': 'aes-gcm',
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    }),
  );
}

/// 解密信封；失败统一抛 [BackupDecryptException]。
Future<List<int>> decryptBackup(
  List<int> bytes, {
  required String passphrase,
}) async {
  final Map<String, dynamic> root;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const BackupDecryptException('备份容器格式不正确');
    }
    root = Map<String, dynamic>.from(decoded);
  } catch (e) {
    if (e is BackupDecryptException) rethrow;
    throw const BackupDecryptException('备份容器格式不正确');
  }
  if (root['enc'] != 'aes-gcm' || root['kdf'] != 'pbkdf2-hmac-sha256') {
    throw const BackupDecryptException('不支持的备份加密格式');
  }
  final iterations = root['iterations'];
  if (iterations is! int || iterations < 1000) {
    throw const BackupDecryptException('备份 KDF 参数不合法');
  }
  final List<int> salt;
  final List<int> nonce;
  final List<int> cipher;
  final List<int> tag;
  try {
    salt = base64Decode('${root['salt']}');
    nonce = base64Decode('${root['nonce']}');
    cipher = base64Decode('${root['ciphertext']}');
    tag = base64Decode('${root['tag']}');
  } catch (_) {
    throw const BackupDecryptException('备份容器字段损坏');
  }
  final key = await _derive(passphrase, salt, iterations);
  try {
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
      secretKey: key,
    );
    return clear;
  } on SecretBoxAuthenticationError {
    throw const BackupDecryptException('口令错误或备份文件已被篡改');
  } catch (_) {
    throw const BackupDecryptException('解密失败');
  }
}

Future<SecretKey> _derive(String passphrase, List<int> salt, int iterations) {
  return Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
}
