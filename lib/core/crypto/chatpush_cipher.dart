/// ChatPush rotate-XOR cipher (MNClient `crypto/chatpush.py`).
///
/// 加密：每字节先左旋 3 位，再与循环 4 字节 key XOR。
/// 解密：先 XOR，再右旋 3 位。
/// 注意：不是普通 XOR——位旋转对正确性至关重要。
library;

import 'protocol_keys.dart';

/// Encrypt [data] with rotate-left-3 + cyclic XOR.
/// `((b << 3) + (b >> 5)) & 0xFF` then `^ key[i % 4]`.
List<int> chatpushEncrypt(List<int> data) {
  final out = List<int>.filled(data.length, 0);
  for (var i = 0; i < data.length; i++) {
    final b = data[i];
    final rotated = ((b << 3) + (b >> 5)) & 0xFF;
    out[i] = (rotated ^ chatpushXorKey[i % 4]) & 0xFF;
  }
  return out;
}

/// Decrypt [data] produced by [chatpushEncrypt].
/// `^ key[i%4]` first, then rotate-right-3: `((b << 5) + (b >> 3)) & 0xFF`.
List<int> chatpushDecrypt(List<int> data) {
  final out = List<int>.filled(data.length, 0);
  for (var i = 0; i < data.length; i++) {
    final b = data[i];
    final xored = (b ^ chatpushXorKey[i % 4]) & 0xFF;
    out[i] = ((xored << 5) + (xored >> 3)) & 0xFF;
  }
  return out;
}
