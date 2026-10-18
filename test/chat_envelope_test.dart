// 私有信封（零宽字符隐写）的编解码验证：
// 往返一致、可见正文不脏、未知/损坏数据一律退回纯文本。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/chat_envelope.dart';

void main() {
  group('往返', () {
    test('小载荷（typing）能原样取回，且可见正文一字不差', () {
      // 文本载体的真实容量：服务端正文上限约 128 **字节**，而 4 位/字符的隐形
      // 符号每个 3 字节 → 一条消息只装得下约 20 字节的 JSON。typing 刚好装得下。
      const visible = '晚上一起玩';
      const envelope = MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{});
      final encoded = attachMnEnvelope(visible, envelope);
      expect(encoded.length, greaterThan(visible.length), reason: '应该带上了信封');
      expect(encoded.startsWith(visible), isTrue, reason: '正文前缀必须原样保留');
        final tail = encoded.substring(visible.length);
        // 隐写块 = 起始标记（软连字符）+ 4 位/字符的隐形符号 + 结束标记（ZWNBSP）。
        expect(tail.startsWith('\u00AD'), isTrue);
        expect(tail.endsWith('\uFEFF'), isTrue);
        const symbolRanges = <(int, int)>[
          (0x200B, 0x200F),
          (0x2060, 0x2064),
          (0x17B4, 0x17B5),
        ];
        const symbolSingles = <int>[0x00AD, 0xFEFF, 0x034F, 0x061C, 0x180E];
        expect(
          tail.runes.every(
            (r) =>
                symbolSingles.contains(r) ||
                symbolRanges.any((p) => r >= p.$1 && r <= p.$2),
          ),
          isTrue,
          reason: '隐写块里不能出现可见字符',
        );

        final (decodedVisible, decoded) = splitMnMessage(encoded);
        expect(decodedVisible, visible);
        expect(decoded, isNotNull);
        expect(decoded!.kind, envelope.kind);
        expect(decoded.payload, envelope.payload);
    });

    test('带原文的引用 / 带 URL 的语音装不下 → 整条不带（需改走 extend_data）', () {
      for (final envelope in <MnEnvelope>[
        const MnEnvelope(MnEnvelopeKind.quote, {'t': '在哪', 'u': 1}),
        const MnEnvelope(MnEnvelopeKind.voice, {
          'url': 'http://map40.mini1.cn/map/40/20261017/ab.mp3',
          'seconds': 3,
        }),
      ]) {
        final encoded = attachMnEnvelope('正文', envelope);
        expect(encoded, '正文', reason: '超预算时宁可不带信封，也不能让服务端回 13');
        expect(splitMnMessage(encoded).$2, isNull);
      }
    });

    test('中文/emoji/长文本都不会被破坏（超预算时不带信封）', () {
      const raw = '你好🎉';
      final encoded = attachMnEnvelope(
        raw,
        const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
      );
      final (visible, envelope) = splitMnMessage(encoded);
      expect(visible, raw);
      expect(envelope?.kind, MnEnvelopeKind.typing);

      // 可见正文已经很长 → 加上信封会超字节预算 → 原样返回（服务端会回 13）
      const longText = '一条相当长的消息正文，长到加上信封就超过服务端的字节上限……';
      final dropped = attachMnEnvelope(
        longText,
        const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
      );
      expect(dropped, longText);
      expect(splitMnMessage(dropped).$2, isNull);
    });

    test('重复 attach：装不下的第二段被丢弃，第一段仍能解出', () {
      final once = attachMnEnvelope(
        '正文',
        const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
      );
      final twice = attachMnEnvelope(
        once,
        const MnEnvelope(MnEnvelopeKind.voice, {'s': 2}),
      );
      // voice 载荷超预算 → 第二次不带 → 仍是第一段的 typing ✓（绝不把块叠坏）
      expect(twice, once);
      final (visible, envelope) = splitMnMessage(twice);
      expect(envelope?.kind, MnEnvelopeKind.typing);
      expect(visible, '正文');
    });

    test('信封总长不超服务端字节上限（128），且可见正文过长时自动不带', () {
      final typing = attachMnEnvelope(
        '',
        const MnEnvelope(MnEnvelopeKind.typing, {}),
      );
      expect(typing.length, greaterThan(0));
      expect(utf8.encode(typing).length, lessThanOrEqualTo(kMnMaxMessageBytes));
      expect(splitMnMessage(typing).$2, isNotNull);

      // 可见正文已经很长 → 加上信封会超限 → 原样返回（服务端会回 13=msg_too_long）
      final longText = 'x' * kMnEnvelopeBudgetBytes;
      final dropped = attachMnEnvelope(
        longText,
        const MnEnvelope(MnEnvelopeKind.typing, {}),
      );
      expect(dropped, longText);
    });
  });

  group('降级（未知字段 → 普通文本）', () {
    test('没有隐写块：原样返回', () {
      for (final raw in <String>['', '普通消息', 'a\u200Bb']) {
        final (visible, envelope) = splitMnMessage(raw);
        expect(visible, raw);
        expect(envelope, isNull);
      }
    });

    test('只有结束哨兵 / 位数不够：退回原文（不删字符）', () {
      for (final raw in <String>['\u200D', '正文\u200D', '正文\u200B\u200C\u200D']) {
        final (visible, envelope) = splitMnMessage(raw);
        expect(visible, raw, reason: '不认识的块不能动正文');
        expect(envelope, isNull);
      }
    });

    test('魔数不对 / 版本过高：退回原文', () {
      // 版本号高一位的合法结构：手工构造 8 位魔数 + 3 位版本 + 9 位长度
      String bitsToString(List<int> bits) =>
          bits.map((b) => b == 0 ? '\u200B' : '\u200C').join() + '\uFEFF';
      List<int> put(int value, int width) => [
        for (var i = width - 1; i >= 0; i--) (value >> i) & 1,
      ];

      final wrongMagic = bitsToString([
        ...put(0x7A, 8),
        ...put(kMnEnvelopeVersion, 3),
        ...put(0, 9),
      ]);
      final tooNew = bitsToString([
        ...put(kMnEnvelopeMagic, 8),
        ...put(kMnEnvelopeVersion + 1, 3),
        ...put(0, 9),
      ]);
      for (final raw in <String>['正文$wrongMagic', '正文$tooNew']) {
        final (visible, envelope) = splitMnMessage(raw);
        expect(visible, raw);
        expect(envelope, isNull);
      }
    });

    test('载荷被截断 / JSON 不是对象：退回原文', () {
      final encoded = attachMnEnvelope(
        '正文',
        const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
      );
      final truncated = encoded.substring(0, encoded.length - 12) + '\u200D';
      final (visible, envelope) = splitMnMessage(truncated);
      expect(visible, truncated);
      expect(envelope, isNull);

      // 合法 base64url 但不是 JSON 对象
      final b64 = base64Url.encode(utf8.encode('"字符串"')).replaceAll('=', '');
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      final bits = <int>[];
      void put(int value, int width) {
        for (var i = width - 1; i >= 0; i--) {
          bits.add((value >> i) & 1);
        }
      }

      put(kMnEnvelopeMagic, 8);
      put(kMnEnvelopeVersion, 3);
      put(b64.length, 9);
      for (final u in b64.codeUnits) {
        put(alphabet.indexOf(String.fromCharCode(u)), 6);
      }
      final raw =
          '正文${bits.map((b) => b == 0 ? '\u200B' : '\u200C').join()}\uFEFF';
      final (v2, e2) = splitMnMessage(raw);
      expect(v2, raw);
      expect(e2, isNull);
    });

    test('超长载荷不写进正文（宁可不带元数据）', () {
      final huge = 'x' * 5000;
      final encoded = attachMnEnvelope(
        '正文',
        MnEnvelope(MnEnvelopeKind.quote, {'text': huge, 'uin': 1}),
      );
      expect(encoded, '正文');
      expect(splitMnMessage(encoded).$2, isNull);
    });
  });
}
