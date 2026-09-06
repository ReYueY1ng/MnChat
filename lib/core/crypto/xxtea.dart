/// Pure-Dart XXTEA encryption/decryption with pack/unpack helpers.
/// 移植自 MNClient `crypto/xxtea.py` (109 行)，逐行对照。
library;

import 'package:archive/archive.dart';
import 'dart:typed_data';

const int kDelta = 0x9E3779B9;
/// Standard XXTEA round constant.

final Uint8List _key = Uint8List.fromList(
  List<int>.generate(16, (i) => [0xb4, 0x8e, 0x6e, 0xf4, 0x4e, 0xd1, 0x3e, 0xee,
    0x60, 0x61, 0x41, 0x75, 0x0e, 0x72, 0x9c, 0xf4][i]),
);
/// Default 16-byte XXTEA key used by Mini World
/// (`b48e6ef44ed13eee606141750e729cf4`).

/// Pack [data] with a 4-byte big-endian length prefix, padded to 4-byte boundary.
Uint8List _pack(List<int> data) {
  final length = data.length;
  final padded = length % 4 == 0 ? length : (length + (4 - length % 4));
  final out = Uint8List(4 + padded);
  // 4-byte big-endian length
  out[0] = (length >> 24) & 0xFF;
  out[1] = (length >> 16) & 0xFF;
  out[2] = (length >> 8) & 0xFF;
  out[3] = length & 0xFF;
  out.setRange(4, 4 + length, data);
  return out;
}

/// Unpack by reading 4-byte big-endian length prefix.
Uint8List _unpack(List<int> data) {
  final length = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
  return Uint8List.fromList(data.sublist(4, length + 4));
}

/// Low-level XXTEA encryption (no pack/unpack).
Uint8List _xxteaEncrypt(Uint8List data, Uint8List key) {
  final n = data.length ~/ 4;
  if (n < 2) return data;
  final v = List<int>.generate(n, (i) =>
      (data[i * 4]) | (data[i * 4 + 1] << 8) | (data[i * 4 + 2] << 16) | (data[i * 4 + 3] << 24));
  final k = List<int>.generate(4, (i) =>
      (key[i * 4] & 0xFF) | (key[i * 4 + 1] << 8) | (key[i * 4 + 2] << 16) | (key[i * 4 + 3] << 24));
  final rounds = 6 + 52 ~/ n;
  var z = v[n - 1];
  var total = 0;
  for (var i = 0; i < rounds; i++) {
    total = (total + kDelta) & 0xFFFFFFFF;
    final e = (total >> 2) & 3;
    for (var p = 0; p < n - 1; p++) {
      final y = v[p + 1];
      final mx = ((z >> 5 ^ y << 2) + (y >> 3 ^ z << 4)) ^
          ((total ^ y) + (k[(p & 3) ^ e] ^ z));
      v[p] = (v[p] + mx) & 0xFFFFFFFF;
      z = v[p];
    }
    final y = v[0];
    final mx = ((z >> 5 ^ y << 2) + (y >> 3 ^ z << 4)) ^
        ((total ^ y) + (k[((n - 1) & 3) ^ e] ^ z));
    v[n - 1] = (v[n - 1] + mx) & 0xFFFFFFFF;
    z = v[n - 1];
  }
  return _wordsToBytes(v);
}

/// Low-level XXTEA decryption (no pack/unpack).
Uint8List _xxteaDecrypt(Uint8List data, Uint8List key) {
  final n = data.length ~/ 4;
  if (n < 2) return data;
  final v = List<int>.generate(n, (i) =>
      (data[i * 4]) | (data[i * 4 + 1] << 8) | (data[i * 4 + 2] << 16) | (data[i * 4 + 3] << 24));
  final k = List<int>.generate(4, (i) =>
      (key[i * 4] & 0xFF) | (key[i * 4 + 1] << 8) | (key[i * 4 + 2] << 16) | (key[i * 4 + 3] << 24));
  final rounds = 6 + 52 ~/ n;
  var y = v[0];
  var total = (rounds * kDelta) & 0xFFFFFFFF;
  while (total != 0) {
    final e = (total >> 2) & 3;
    for (var p = n - 1; p > 0; p--) {
      final z = v[p - 1];
      final mx = ((z >> 5 ^ y << 2) + (y >> 3 ^ z << 4)) ^
          ((total ^ y) + (k[(p & 3) ^ e] ^ z));
      v[p] = (v[p] - mx) & 0xFFFFFFFF;
      y = v[p];
    }
    final z = v[n - 1];
    final mx = ((z >> 5 ^ y << 2) + (y >> 3 ^ z << 4)) ^
        ((total ^ y) + (k[(0 & 3) ^ e] ^ z));
    v[0] = (v[0] - mx) & 0xFFFFFFFF;
    y = v[0];
    total = (total - kDelta) & 0xFFFFFFFF;
  }
  return _wordsToBytes(v);
}

Uint8List _wordsToBytes(List<int> words) {
  final out = Uint8List(words.length * 4);
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    out[i * 4] = w & 0xFF;
    out[i * 4 + 1] = (w >> 8) & 0xFF;
    out[i * 4 + 2] = (w >> 16) & 0xFF;
    out[i * 4 + 3] = (w >> 24) & 0xFF;
  }
  return out;
}

/// Encrypt [data] using XXTEA with the shared key (auto-packs).
Uint8List xxteaEncrypt(List<int> data) => _xxteaEncrypt(_pack(data), _key);

/// Decrypt XXTEA-encrypted [data] and unpack the length prefix.
Uint8List xxteaDecrypt(List<int> data) => _unpack(_xxteaDecrypt(Uint8List.fromList(data), _key));

/// Compress [data] with zlib, then encrypt using XXTEA.
Uint8List xxteaEncryptZip(List<int> data) {
  final zlibCompressed = _zlibCompress(data);
  return _xxteaEncrypt(_pack(zlibCompressed), _key);
}

/// Decrypt XXTEA-encrypted [data], unpack, and decompress with zlib.
Uint8List xxteaDecryptUnzip(List<int> data) {
  final unpacked = _unpack(_xxteaDecrypt(Uint8List.fromList(data), _key));
  return _zlibDecompress(unpacked);
}

// -- zlib via package:archive (native and web).

Uint8List _zlibCompress(List<int> data) =>
    ZLibEncoder().encodeBytes(data);
    

Uint8List _zlibDecompress(List<int> data) =>
    ZLibDecoder().decodeBytes(data);