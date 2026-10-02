/// 游戏的 `s7` / `s7t` 请求签名（反编译 `commoncomp/http.lua:2198-2234`，V1 方案）。
///
/// 规则：把 URL 的**整段 query** 用自定义字母表做 base64 得到 `s7`，再算
/// `s7t = md5("s7" + s7)[7..11]`，最终请求形如：
///
/// ```text
/// <base>?s7=<base64(query + "&s7e=1")>&s7t=<5 位校验>
/// ```
///
/// 服务端解 `s7` 拿回原始参数。游戏客户端对 `miniw/bestpartner` 就是走这条路
/// （`bestpartnerserver.lua` 的 `ParamEncode` 出的 URL 由 `ns_http` 再套 s7）：
/// 直接带 `act=...&extdata=...` 服务端回 `code=9`/`code=2`，套上 s7 才下发数据。
///
/// V2（`ns_http_s7_sec2`）需要网关下发的 `gate_name` 做字母表洗牌，本客户端
/// 不参与那段握手，所以只实现 V1 —— 游戏自身在 V2 未初始化时也是回退 V1
/// （`encodeS7Url_V2`）。
library;

import 'dart:convert';

import 'md5_sign.dart' show md5Sign;

/// V1 的自定义 base64 字母表（`http.lua:2197` 的 `g_myb64chars`，64 字符）。
const String kS7Alphabet =
    'Vg21WQ5KdRt0yNpc'
    'r9m4O3PoHaZvsLe'
    'CY8FjSwiTkUbuEBIJ'
    'lAG7fqXM6xDnzh-;';

/// 标准 base64 → 自定义字母表（`ToMyBase64`）。
///
/// `A-Za-z0-9+/` 按序映射到 [kS7Alphabet]，填充 `=` 换成 `_`。
String toMyBase64(String s) {
  final standard = base64Encode(utf8.encode(s));
  final out = StringBuffer();
  for (final code in standard.codeUnits) {
    final ch = String.fromCharCode(code);
    switch (ch) {
      case '=':
        out.write('_');
      case '+':
        out.write(kS7Alphabet[62]);
      case '/':
        out.write(kS7Alphabet[63]);
      default:
        final idx = _stdIndex(ch);
        out.write(idx < 0 ? ch : kS7Alphabet[idx]);
    }
  }
  return out.toString();
}

int _stdIndex(String ch) {
  final c = ch.codeUnitAt(0);
  if (c >= 0x41 && c <= 0x5A) return c - 0x41; // A-Z
  if (c >= 0x61 && c <= 0x7A) return 26 + c - 0x61; // a-z
  if (c >= 0x30 && c <= 0x39) return 52 + c - 0x30; // 0-9
  return -1;
}

/// `s7t = md5("s7" + s7)[7..11]` —— Lua 是 1 基下标，Dart 取 `[6, 11)`。
String s7Token(String s7) => md5Sign(['s7', s7]).substring(6, 11);

/// 把带 query 的 URL 换成 `s7` 形式：
/// `<base>?s7=<...>&s7t=<...>`（原 query 全部进 `s7`，末尾补 `&s7e=1`）。
///
/// 不带 query（或太长/太短）时原样返回，与 Lua 的 `pos_ > 10` 判断一致。
String encodeS7Url(String url) {
  final q = url.indexOf('?');
  if (q <= 10) return url;
  final u1 = url.substring(0, q + 1);
  final u2 = '${url.substring(q + 1)}&s7e=1';
  final s7 = toMyBase64(u2);
  return '$u1'
      's7=$s7&s7t=${s7Token(s7)}';
}
