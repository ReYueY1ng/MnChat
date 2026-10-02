import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/crypto/s7_sign.dart';

/// `s7`/`s7t` 签名（游戏 `http.lua:2198-2234` V1）：
/// 字母表映射、md5 取位、以及 s7 能不能还原出原始 query。
void main() {
  String md5Of(String s) => crypto.md5.convert(utf8.encode(s)).toString();

  /// 测试用的反向映射：自定义字母表 → 标准 base64。
  String fromMyBase64(String s) {
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      if (ch == '_') {
        buf.write('=');
      } else {
        final i = kS7Alphabet.indexOf(ch);
        if (i < 0) throw StateError('字母表外的字符: $ch');
        if (i < 26) {
          buf.write(String.fromCharCode(0x41 + i));
        } else if (i < 52) {
          buf.write(String.fromCharCode(0x61 + i - 26));
        } else if (i < 62) {
          buf.write(String.fromCharCode(0x30 + i - 52));
        } else {
          buf.write(i == 62 ? '+' : '/');
        }
      }
    }
    return buf.toString();
  }

  group('toMyBase64', () {
    test('字母表是 64 个字符，末尾是 -;', () {
      expect(kS7Alphabet.length, 64);
      expect(kS7Alphabet.substring(62), '-;');
    });

    test('按标准 base64 的位置映射到自定义字母表（含填充 = → _）', () {
      // 'A' → 标准 base64 "QQ=="：'Q' 是第 16 位 → alphabet[16]，填充两位。
      expect(toMyBase64('A'), '${kS7Alphabet[16]}${kS7Alphabet[16]}__');
      // 标准 base64 的 '+' / '/' 落在字母表最后两位。
      final encoded = toMyBase64('\u00fb\u00ff\u00fe');
      for (final ch in encoded.split('')) {
        expect(kS7Alphabet.contains(ch) || ch == '_', isTrue, reason: ch);
      }
      // 各字母表字符互不相同（映射是双射，才能反解）。
      expect(kS7Alphabet.split('').toSet().length, 64);
    });

    test('输出只含自定义字母表 / 下划线，长度与标准 base64 一致', () {
      const raw = r'act=get_list&uin=279630451&apiid=110&s7e=1';
      final mine = toMyBase64(raw);
      expect(mine.length, base64Encode(utf8.encode(raw)).length);
      for (final ch in mine.split('')) {
        expect(kS7Alphabet.contains(ch) || ch == '_', isTrue, reason: ch);
      }
    });

    test('能还原回原始字符串', () {
      const raw = r'/miniw/bestpartner?act=get_list&uin=1&s7e=1';
      final back = utf8.decode(base64Decode(fromMyBase64(toMyBase64(raw))));
      expect(back, raw);
    });
  });

  group('s7Token', () {
    test('= md5("s7" + s7) 的第 7..11 位', () {
      const s7 = 'Vg21WQ';
      expect(s7Token(s7), md5Of('s7$s7').substring(6, 11));
      expect(s7Token(s7).length, 5);
    });
  });

  group('encodeS7Url', () {
    test('把整段 query 塞进 s7，并补 &s7e=1', () {
      const url = 'https://h/miniw/bestpartner?act=get_list&uin=1';
      final out = encodeS7Url(url);
      expect(out, startsWith('https://h/miniw/bestpartner?s7='));
      final s7 = RegExp(r'\?s7=([^&]+)&s7t=([0-9a-f]{5})$')
          .firstMatch(out)
          ?.group(1);
      expect(s7, isNotNull);
      final decoded = utf8.decode(base64Decode(fromMyBase64(s7!)));
      expect(decoded, 'act=get_list&uin=1&s7e=1');
      expect(out, contains('&s7t=${s7Token(s7)}'));
    });

    test('没有 query，或 "?" 位置太靠前时原样返回', () {
      // 与 Lua 的 `pos_ > 10`（1 基）一致：0 基下就是 index > 10。
      expect(encodeS7Url('https://h/x'), 'https://h/x'); // 没有 '?'
      expect(encodeS7Url('a?b=1'), 'a?b=1'); // '?' 在第 2 位 → 不编码
      expect(encodeS7Url('https://h/x?'), isNot('https://h/x?')); // 达标 → 编码
    });
  });
}
