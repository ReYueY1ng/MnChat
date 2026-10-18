import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/chat_envelope.dart';
import 'package:mnchat/core/services/voice_clip.dart';

/// 语音消息：时长文案 / WAV 时长估算 / 信封载荷往返。
///
/// 语音的传输复用聊天图片那条预签名分片直传（`uploadChatMedia`），这里覆盖的是
/// 不需要网络的纯函数与信封协议部分；「上传后可回读」的证据在
/// `/tmp/ulw-run-mnchat/evidence/voice_upload_probe.txt`（live 只读 GET）。
List<int> _wav({int seconds = 1, int sampleRate = 8000}) {
  final dataBytes = sampleRate * seconds; // 8bit 单声道 → 每秒 = sampleRate 字节
  final out = BytesBuilder();
  void str(String s) => out.add(s.codeUnits);
  void le32(int v) =>
      out.add(<int>[v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void le16(int v) => out.add(<int>[v & 0xff, (v >> 8) & 0xff]);
  str('RIFF');
  le32(36 + dataBytes);
  str('WAVE');
  str('fmt ');
  le32(16);
  le16(1); // PCM
  le16(1); // 单声道
  le32(sampleRate);
  le32(sampleRate); // byteRate = sampleRate * 1ch * 1byte
  le16(1); // blockAlign
  le16(8); // 位深
  str('data');
  le32(dataBytes);
  out.add(Uint8List(dataBytes)); // 静音采样
  return out.toBytes();
}

void main() {
  group('时长文案', () {
    test('秒 → N″；不足一分钟不带分', () {
      expect(voiceSecondsLabel(0), '0″');
      expect(voiceSecondsLabel(3), '3″');
      expect(voiceSecondsLabel(59), '59″');
    });

    test('超过一分钟 → M′S″；负数按 0', () {
      expect(voiceSecondsLabel(60), '1\u20320″');
      expect(voiceSecondsLabel(75), '1\u203215″');
      expect(voiceSecondsLabel(-5), '0″');
    });
  });

  group('WAV 时长估算', () {
    test('1 秒 / 3 秒的 PCM WAV 都能算对', () {
      expect(voiceDurationSeconds(_wav(seconds: 1)), 1);
      expect(voiceDurationSeconds(_wav(seconds: 3)), 3);
    });

    test('不足半秒 → 0；半秒到 1 秒 → 1（短片段不算 0）', () {
      expect(voiceDurationSeconds(_wav(seconds: 0)), 0);
      final half = _wav(seconds: 0);
      // 手工把 data 块撑到半个 byteRate。
      final wav = _wav(seconds: 1);
      final short = <int>[...wav.take(44), ...List<int>.filled(4000, 0)];
      expect(voiceDurationSeconds(short), 1);
      expect(voiceDurationSeconds(half), 0);
    });

    test('非 WAV / 太短 → 0（绝不抛）', () {
      expect(voiceDurationSeconds(const <int>[1, 2, 3]), 0);
      expect(voiceDurationSeconds(const <int>[]), 0);
      expect(voiceDurationSeconds(List<int>.filled(100, 7)), 0);
      // PNG 头：RIFF/WAVE 判定不通过。
      expect(
        voiceDurationSeconds(const <int>[
          0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13,
          ...<int>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        ]),
        0,
      );
    });
  });

  group('语音信封', () {
    const url = 'http://map40.mini1.cn/map/40/20261017/'
        'b218a001968ea354cd55ce8733ffe5dc.mp3';

    test('语音 URL 超正文预算 → 整条不带信封（需改走 extend_data 载体）', () {
      // 服务端 send_chat_msg 正文上限约 128 字符（实测 128 过 / 140 回 13=msg_too_long）：
      // 一个 CDN URL 的载荷算下来远超预算，[attachMnEnvelope] 于是**不带信封**，
      // 正文保持干净（不让服务端拒收）。语音要真可点，得把元数据改挂 extend_data。
      final payload = attachMnEnvelope(
        '[语音] ${voiceSecondsLabel(3)}',
        const MnEnvelope(MnEnvelopeKind.voice, <String, Object?>{
          'url': url,
          'seconds': 3,
        }),
      );
      final (visible, envelope) = splitMnMessage(payload);
      expect(visible, '[语音] 3″');
      expect(envelope, isNull);
    });

    test('语音载荷装不下 → 整条不带（语音要真可点需改走 extend_data）', () {
      for (final payload in <Map<String, Object?>>[
        <String, Object?>{'url': url, 'seconds': 3},
        <String, Object?>{'seconds': 0},
      ]) {
        final encoded = attachMnEnvelope(
          '[语音]',
          MnEnvelope(MnEnvelopeKind.voice, payload),
        );
        expect(encoded, '[语音]', reason: '超预算宁可不带，也不能让服务端回 13');
        expect(splitMnMessage(encoded).$2, isNull);
      }
    });

    test('官方客户端视角：正文里没有零宽字符（不会看到乱码）', () {
      // 无关宽字符的检查与载荷无关，但保持小载荷以免触发预算守卫。
      final payload = attachMnEnvelope(
        '[语音] 3″',
        const MnEnvelope(MnEnvelopeKind.voice, <String, Object?>{'seconds': 3}),
      );
      final (visible, _) = splitMnMessage(payload);
      for (final r in visible.runes) {
        expect(
          r == 0x200b || r == 0x200c || r == 0x200d,
          isFalse,
          reason: '可见正文不该含零宽字符',
        );
      }
      expect(visible.length, '[语音] 3″'.length);
    });

    test('极小载荷（无 URL）仍能往返；带 URL 则超预算', () {
      final tiny = attachMnEnvelope(
        '[语音]',
        const MnEnvelope(MnEnvelopeKind.voice, <String, Object?>{}),
      );
      final (visible, envelope) = splitMnMessage(tiny);
      expect(visible, '[语音]');
      expect(envelope?.kind, MnEnvelopeKind.voice);
      expect(envelope?.payload, isEmpty);
    });
  });

  group('播放进度：位置 → 0..1', () {
    test('用播放器上报的总长', () {
      expect(
        positionToProgress(const Duration(seconds: 3), const Duration(seconds: 6), 0),
        0.5,
      );
      expect(
        positionToProgress(const Duration(seconds: 6), const Duration(seconds: 6), 0),
        1,
      );
      // 超出/负数都夹到 0..1（进度条不能画出界）。
      expect(
        positionToProgress(const Duration(seconds: 9), const Duration(seconds: 6), 0),
        1,
      );
      expect(
        positionToProgress(const Duration(seconds: -1), const Duration(seconds: 6), 0),
        0,
      );
    });

    test('播放器没给总长时用载荷秒数；都没有则为 0（不画进度）', () {
      expect(
        positionToProgress(const Duration(seconds: 2), Duration.zero, 4),
        0.5,
      );
      expect(positionToProgress(const Duration(seconds: 2), Duration.zero, 0), 0);
    });
  });

  group('拖动定位：0..1 → 播放位置', () {
    test('用播放器总长换算', () {
      expect(
        fractionToPosition(0.5, const Duration(seconds: 8), 0),
        const Duration(seconds: 4),
      );
      expect(
        fractionToPosition(0, const Duration(seconds: 8), 0),
        Duration.zero,
      );
      expect(
        fractionToPosition(1, const Duration(seconds: 8), 0),
        const Duration(seconds: 8),
      );
    });

    test('没有总长就用载荷秒数；越界/NaN 都夹住不抛', () {
      expect(
        fractionToPosition(0.25, Duration.zero, 8),
        const Duration(seconds: 2),
      );
      expect(
        fractionToPosition(1.7, Duration.zero, 8),
        const Duration(seconds: 8),
      );
      expect(fractionToPosition(-0.5, Duration.zero, 8), Duration.zero);
      expect(fractionToPosition(double.nan, Duration.zero, 8), Duration.zero);
      // 两边都给不出总长 → 0（seek 到开头，不会瞎跳）。
      expect(fractionToPosition(0.5, Duration.zero, 0), Duration.zero);
    });
  });
}
