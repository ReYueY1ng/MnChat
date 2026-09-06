/// Lua `urlEncode` 语义精确复刻 (MNClient `crypto/sign.py:_url_encode` :61-64).
///
/// 保留字母数字及 `.-_` 和空格；空格编码为 `+`.
/// 与 Dart 的 `Uri.encodeQueryComponent` 行为不同（后者空格 → `%20`）。
/// 该函数会被用于登录/签名串构建，差异会导致 MD5 不匹配。
library;

import 'dart:convert';

/// URL-encode matching Lua `urlEncode`（用于**签名串**）:
/// keeps alnum, `.`, `-`, `_`；空格 → `%20`（实测服务器签名要求 %20，非 +）。
///
/// 注意：query 用的 Uri.encodeQueryComponent 把空格转 `+` 也能被服务器接受，
/// 但**签名串必须用 %20**（穷举验证 send_chat_msg result:0）。
String luaUrlEncode(Object value) {
  final s = value.toString();
  final bytes = utf8.encode(s); // UTF-8 字节流
  final sb = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    final isAlnum =
        (b >= 0x30 && b <= 0x39) || // 0-9
        (b >= 0x41 && b <= 0x5A) || // A-Z
        (b >= 0x61 && b <= 0x7A); // a-z
    if (isAlnum || b == 0x2E || b == 0x2D || b == 0x5F) {
      // . - _
      sb.writeCharCode(b);
    } else {
      sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
    i++;
  }
  return sb.toString();
}

/// URL-safe base64 with `=` padding replaced by `:`
/// (MNClient `crypto/encoding.py:urlsafe_b64_urlencode`).
String urlsafeB64Urlencode(List<int> data) {
  final b64 = base64UrlEncode(data).replaceAll('=', '');
  // Python urlsafe_b64encode + replace "=" with ":"; base64Url in Dart already
  // uses -_ and no padding; re-add padding then swap for ":" to match Python.
  final padded = _padForPython(b64);
  return padded.replaceAll('=', ':');
}

String _padForPython(String b64) {
  // Python adds '=' padding: len % 4 -> 0..3
  final rem = b64.length % 4;
  if (rem == 0) return b64;
  return b64 + '=' * (4 - rem);
}

/// Decode URL-safe base64 string that uses `:` instead of `=`.
/// (MNClient `crypto/encoding.py:urlsafe_b64_urldecode`).
List<int> urlsafeB64Urldecode(String s) {
  var normalized = s.replaceAll(':', '=');
  // Restore padding to a multiple of 4.
  final rem = normalized.length % 4;
  if (rem != 0) {
    normalized = normalized.padRight(normalized.length + (4 - rem), '=');
  }
  return base64Url.decode(normalized);
}
