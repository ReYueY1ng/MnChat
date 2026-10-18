/// 语音录制：把麦克风（或系统采集源）录成 WAV 字节。
///
/// 用 `record` 插件：Linux 走 `parecord` → `ffmpeg`，Android 走 MediaRecorder，
/// 都输出 16kHz 单声道 WAV —— 与发送侧的 `voiceDurationSeconds` 解析格式一致，
/// 本机播放器也能直接播。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart' show AudioEncoder, AudioRecorder, RecordConfig;

import '../utils/log.dart' show log;

/// WAV 头长度：只读到这么多说明一个字都没录到。
const int kWavHeaderBytes = 44;

/// 录音器。一次只录一条；[stop] 给出音频字节，[cancel] 丢弃本次。
class VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();

  /// 准备写入的路径（[stop] 后失效）。
  String? _path;

  /// 是否正在录。
  Future<bool> isRecording() async {
    try {
      return await _rec.isRecording();
    } catch (_) {
      return false;
    }
  }

  /// 开始录音；返回是否真的开始了（无权限/无设备/出错都是 false）。
  Future<bool> start() async {
    try {
      if (!await _rec.hasPermission()) {
        log.warn('录音：没有采集权限');
        return false;
      }
      final dir = Directory.systemTemp.createTempSync('mnchat_voice_');
      final path = '${dir.path}/clip.wav';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _path = path;
      return true;
    } catch (e) {
      log.warn('录音启动失败: $e');
      return false;
    }
  }

  /// 停止录音并读回字节；没录到内容（只有 WAV 头）或失败返回 null。
  Future<Uint8List?> stop() async {
    final path = _path;
    _path = null;
    try {
      final saved = await _rec.stop();
      final file = File(saved ?? path ?? '');
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      return bytes.length > kWavHeaderBytes ? bytes : null;
    } catch (e) {
      log.warn('录音结束失败: $e');
      return null;
    }
  }

  /// 放弃本次录音。
  Future<void> cancel() async {
    _path = null;
    try {
      await _rec.cancel();
    } catch (_) {
      // 取消失败无所谓：文件在临时目录，不影响发送。
    }
  }

  /// 释放插件资源。
  Future<void> dispose() async {
    try {
      await _rec.dispose();
    } catch (_) {
      // 同上：释放失败不阻断调用方。
    }
  }
}
