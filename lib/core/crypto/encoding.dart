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

/// 宽松解码游戏侧的 base64 变体 —— 解不出来返回 null（不抛）。
///
/// 真机抓到的 `extend_data` 用的是**把 `=` 填充也换成 `_`** 的 urlsafe 变体，例如
/// `...ImNoYXJlVHlwZSI6MH0__`（尾部 `__` 即 `==`）。如果按常规把 `_` 一律当
/// `/`，尾部就会变成 `//` → 解出乱码 → 整条消息退化（表现：动态表情显示成
/// 「请升级到最新版本查看」）。
///
/// 由于 `_` 既可能是 `/` 也可能是填充，这里**依次尝试几种规范化**，取第一个
/// 既能 base64 解出、又是**合法 UTF-8** 的候选 —— 载荷都是 UTF-8 文本
/// （JSON），用 UTF-8 校验就能把「把填充当数据」的错误候选区分开。
List<int>? lenientBase64Decode(String s) {
  for (final candidate in _base64Candidates(s)) {
    try {
      final bytes = base64Decode(candidate);
      utf8.decode(bytes); // 错误候选会在这里失败（乱码），继续试下一个
      return bytes;
    } catch (_) {
      // 试下一种
    }
  }
  return null;
}

Iterable<String> _base64Candidates(String s) sync* {
  // `:`（本项目发出去的填充写法）、`-`/`+` 的互换先统一掉。
  final unified = s.replaceAll(':', '=').replaceAll('-', '+');

  // 0) 尾部 `_` 当**填充**（真机实测形态），必须先于「`_` 当 `/`」尝试。
  //    原因：尾部 1 个 `_` 若当成 `/` 解，会多出**恰好一个**字节 —— 以
  //    `...In0_`（礼物 extend_data）为例，`_`→`/` 后解成 `...}` 再跟一个
  //    `?`(0x3F)，而 `?` 是**合法 UTF-8**，于是错误候选被选中，随后
  //    `jsonDecode` 因尾部多余内容失败，整条消息退化成兜底文案。
  //    仅当尾部 `_` 个数正好等于该长度的补位需求时才这样解，避免把真正的
  //    `/`（也编码为 `_`）误当填充。
  for (var pads = 2; pads >= 1; pads--) {
    if (unified.length > pads && unified.endsWith('_' * pads)) {
      final bodyLen = unified.length - pads;
      if ((4 - bodyLen % 4) % 4 == pads) {
        final body = unified.substring(0, bodyLen).replaceAll('_', '/');
        yield '$body${'=' * pads}';
      }
    }
  }

  // 1) 标准 urlsafe：`_` == `/`
  yield _leftPad(unified.replaceAll('_', '/'));
  // 2) `_` 全是填充
  yield _leftPad(unified.replaceAll('_', '='));
}

String _leftPad(String s) {
  final rem = s.length % 4;
  return rem == 0 ? s : s.padRight(s.length + (4 - rem), '=');
}
