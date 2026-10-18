import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/chat/message_adapter.dart' show envelopeOf, isTransientSignal;
import 'package:mnchat/core/models/chat_envelope.dart';
import 'package:mnchat/core/models/messages.dart';

/// `extend_data` 载体（2026-10-17 新增）。
///
/// 背景：`send_chat_msg` 的正文上限约 **128 字节**（实测 128 通过 / 140 回
/// `result=13`），而隐形符号在 UTF-8 里占 3 字节/个 —— 引用原文、语音 URL 这类
/// 载荷在正文里装不下（会被 [attachMnEnvelope] 整条丢弃）。`extend_data` 是
/// 独立字段：没有正文长度约束，官方客户端忽略未知键，MNChat 之间才读。
void main() {
  const longUrl = 'http://map40.mini1.cn/map/40/20261017/'
      'b218a001968ea354cd55ce8733ffe5dc.mp3';

  group('extend_data 载体', () {
    test('编码是 url_encode(base64(JSON))，与分享卡同形', () {
      const env = MnEnvelope(MnEnvelopeKind.voice, <String, Object?>{
        'url': longUrl,
        'seconds': 3,
      });
      final encoded = encodeMnExtendData(env);
      expect(encoded.contains('%'), isTrue, reason: '要 url_encode');
      final raw = utf8.decode(base64Decode(Uri.decodeComponent(encoded)));
      final json = (jsonDecode(raw) as Map).cast<String, Object?>();
      expect(json['mn'], isA<Map>());
      expect((json['mn'] as Map)['k'], 'voice');
    });

    test('大载荷（语音 URL / 引用原文）也能往返 —— 这正是正文载体做不到的', () {
      for (final env in <MnEnvelope>[
        const MnEnvelope(MnEnvelopeKind.voice, <String, Object?>{
          'url': longUrl,
          'seconds': 3,
        }),
        const MnEnvelope(MnEnvelopeKind.quote, <String, Object?>{
          'text': '一条相当长的引用原文，长到放进正文会超过 128 字节上限……',
          'uin': 279630451,
        }),
      ]) {
        final back = envelopeFromExtendData(
          (jsonDecode(utf8.decode(base64Decode(Uri.decodeComponent(encodeMnExtendData(env)))))
                  as Map)
              .cast<String, Object?>(),
        );
        expect(back?.kind, env.kind);
        expect(back?.payload, env.payload);
      }
    });

    test('适配器优先读 extend_data，正文隐写作为兜底', () {
      const env = MnEnvelope(MnEnvelopeKind.voice, <String, Object?>{
        'url': longUrl,
        'seconds': 2,
      });
      final m = ChatMessage(
        uin: 1,
        text: '[语音] 2″',
        time: 1792220000,
        extendData: encodeMnExtendData(env),
      );
      final got = envelopeOf(m);
      expect(got?.kind, MnEnvelopeKind.voice);
      expect(got?.payload['url'], longUrl);

      // 没有 extend_data 时退回正文隐写（早期文本载体仍能解）
      final textOnly = ChatMessage(
        uin: 1,
        text: attachMnEnvelope(
          '',
          const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
        ),
        time: 1792220001,
      );
      expect(envelopeOf(textOnly)?.kind, MnEnvelopeKind.typing);
      expect(isTransientSignal(textOnly), isTrue);
    });

    test('extend_data 里的 typing 同样算临时信号（不进气泡）', () {
      final m = ChatMessage(
        uin: 1,
        text: '',
        time: 1792220002,
        extendData: encodeMnExtendData(
          const MnEnvelope(MnEnvelopeKind.typing, <String, Object?>{}),
        ),
      );
      expect(isTransientSignal(m), isTrue);
    });
  });
}
