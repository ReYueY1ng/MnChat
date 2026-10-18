/// 语音消息：播放（含进度）+ 时长格式化。
///
/// 语音的**传输**复用的是与聊天图片同一条预签名分片直传
/// （[uploadChatMedia]），载荷走私有信封 `MnEnvelopeKind.voice` → `{url, seconds}`，
/// 所以官方客户端看到的是可读的 `[语音] 3″` 正文，MNChat 之间才渲染成可点的语音条。
///
/// 播放策略（2026-10-18 改）：用 **media_kit** 在应用进程内播放，各平台一致 ——
/// 桌面走系统 libmpv，Android 走 libmpv 的 AAR（`media_kit_libs_android_audio`，
/// 代价是 APK 变大）；URL 直接交给它流式播放，进度来自它的 `position`/`duration`
/// 流（真值）。早先版本是 `Process.start('ffplay')` 再解析它的状态行取进度，
/// Android 另走系统 MediaPlayer 通道：那是权宜之计 —— 依赖外部二进制、各平台
/// 两套实现、还得解析文本。
library;

import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import '../utils/log.dart' show log;

/// 时长文案：`12″`（官方客户端里语音卡也是「数字 + 秒符号」的短形态）。
String voiceSecondsLabel(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  if (s < 60) return '$s″';
  final m = s ~/ 60;
  final r = s % 60;
  return '$m\u2032$r″';
}

/// 从音频字节里尽力估出时长（秒）；解不出 → 0。
///
/// 目前只解 PCM WAV（`RIFF....WAVE`，读 `fmt ` 的 byteRate 与 `data` 块大小）：
/// 这正是本地录音回环最常见的形态。其它容器（mp3/aac/m4a）不算时长也不用额外
/// 依赖去解码 —— 返回 0，UI 就只显示 `[语音]` 不带秒数。
int voiceDurationSeconds(List<int> bytes) {
  if (bytes.length < 44) return 0;
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return 0;
  if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return 0;
  var byteRate = 0;
  var dataSize = 0;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = _le32(bytes, offset + 4);
    if (id == 'fmt ' && offset + 24 <= bytes.length) {
      byteRate = _le32(bytes, offset + 16);
    } else if (id == 'data') {
      dataSize = size > 0 && size <= bytes.length - offset - 8
          ? size
          : bytes.length - offset - 8;
      break;
    }
    if (size < 0) return 0;
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  if (byteRate <= 0 || dataSize <= 0) return 0;
  final seconds = dataSize ~/ byteRate;
  if (seconds > 0) return seconds;
  // 不足一秒也算一秒（录音回环常见的短片段）。
  return (dataSize * 2 >= byteRate) ? 1 : 0;
}

int _le32(List<int> b, int at) =>
    (b[at] & 0xff) |
    ((b[at + 1] & 0xff) << 8) |
    ((b[at + 2] & 0xff) << 16) |
    ((b[at + 3] & 0xff) << 24);

/// 把播放位置换算成 0..1 的进度。
///
/// 播放器上报了总长就用它；没有（容器没写头 / 还没解出）就用载荷里带的秒数；
/// 两者都没有 → 0（UI 就只显示时长、不画进度）。
double positionToProgress(
  Duration position,
  Duration duration,
  int fallbackSeconds,
) {
  final totalMs = duration.inMilliseconds > 0
      ? duration.inMilliseconds
      : fallbackSeconds * 1000;
  if (totalMs <= 0) return 0;
  final v = position.inMilliseconds / totalMs;
  if (v.isNaN) return 0;
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

/// 把 0..1 的进度换算成播放位置（播放器没上报总长时用载荷里的秒数）。
Duration fractionToPosition(
  double fraction,
  Duration duration,
  int fallbackSeconds,
) {
  final f = fraction.isNaN
      ? 0.0
      : (fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction));
  final totalMs = duration.inMilliseconds > 0
      ? duration.inMilliseconds
      : fallbackSeconds * 1000;
  if (totalMs <= 0) return Duration.zero;
  return Duration(milliseconds: (totalMs * f).round());
}

/// 一条语音的播放句柄：真实进度流 + 停止 + 播放结束通知。
///
/// [progress] 是 0..1；[done] 不管自然放完还是被 [stop] 都会完成，UI 据此收回播放态。
class VoicePlayback {
  VoicePlayback._({required this.totalSeconds, this._player});

  /// 载荷里带的时长（秒）；0 表示未知。
  final int totalSeconds;

  final Player? _player;
  final StreamController<double> _progressCtl =
      StreamController<double>.broadcast();
  final Completer<void> _done = Completer<void>();
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  Timer? _fallbackTicker;
  Duration _duration = Duration.zero;
  bool _sawPosition = false;

  /// 播放进度 0..1。
  Stream<double> get progress => _progressCtl.stream;

  /// 播放结束（自然放完或 [stop]）时完成。
  Future<void> get done => _done.future;

  bool get isPlaying => !_done.isCompleted;

  void _emit(double v) {
    if (_progressCtl.isClosed) return;
    _progressCtl.add(v < 0 ? 0 : (v > 1 ? 1 : v));
  }

  /// 订阅 media_kit 的流（位置 / 总长 / 播完 / 出错）。
  void _attach(Player player) {
    _subs.add(
      player.stream.position.listen((p) {
        if (!_sawPosition) {
          _sawPosition = true;
          _stopFallbackTicker();
        }
        _emit(positionToProgress(p, _duration, totalSeconds));
      }),
    );
    _subs.add(
      player.stream.duration.listen((d) {
        if (d.inMilliseconds > 0) _duration = d;
      }),
    );
    _subs.add(
      player.stream.completed.listen((c) {
        if (c) _finish();
      }),
    );
    _subs.add(
      player.stream.error.listen((e) {
        log.warn('语音播放出错: $e', tag: 'Voice');
        _finish(natural: false);
      }),
    );
  }

  /// 播放器不上报位置时（Android 原生通道 / 引擎没起来），按载荷时长本地计时。
  void _startFallbackTicker() {
    if (totalSeconds <= 0 || _fallbackTicker != null) return;
    var elapsedMs = 0;
    _fallbackTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      elapsedMs += 250;
      _emit(elapsedMs / (totalSeconds * 1000));
      if (elapsedMs >= totalSeconds * 1000) _finish();
    });
  }

  void _stopFallbackTicker() {
    _fallbackTicker?.cancel();
    _fallbackTicker = null;
  }

  void _finish({bool natural = true}) {
    if (_done.isCompleted) return;
    _stopFallbackTicker();
    if (natural) _emit(1);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    if (!_progressCtl.isClosed) _progressCtl.close();
    _done.complete();
  }

  /// 跳到 0..1 的位置（拖动进度条松手时调）。
  ///
  /// 先本地发一次进度（滑杆不掉手），再把位置交给播放器。
  Future<void> seekFraction(double fraction) async {
    final player = _player;
    if (player == null || _done.isCompleted) return;
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    _emit(f);
    try {
      await player.seek(fractionToPosition(f, _duration, totalSeconds));
    } catch (e) {
      log.warn('语音定位失败: $e', tag: 'Voice');
    }
  }

  /// 停止播放（幂等，不抛）。
  Future<void> stop() async {
    if (_done.isCompleted) return;
    final player = _player;
    _finish(natural: false);
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } catch (_) {
        // 已经停了：忽略。
      }
    }
  }
}

/// 当前正在播的那一条（同时只放一条：新的开始会先停掉旧的）。
VoicePlayback? _current;

/// 开始播放一条语音，返回**带真实进度**的句柄；失败 / 平台不支持 → null。
///
/// 各平台都用 media_kit 在进程内播放（桌面 libmpv / Android libmpv AAR），
/// URL 直接交给它流式播放（不必先下载到临时文件），进度取自它的位置流。
/// 还没带解码库的平台（如 iOS）返回 null，由 UI 提示不支持。
Future<VoicePlayback?> startVoicePlayback(
  String url, {
  int seconds = 0,
}) async {
  if (url.isEmpty) return null;
  await _current?.stop();

  final supported =
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isAndroid;
  if (!supported) return null;
  try {
    final player = Player();
    final pb = VoicePlayback._(totalSeconds: seconds, player: player);
    _current = pb;
    pb._attach(player);
    // 引擎迟迟不上报位置再兜底（正常路径用不到）。
    Timer(const Duration(milliseconds: 1500), () {
      if (pb.isPlaying && !pb._sawPosition) pb._startFallbackTicker();
    });
    await player.open(Media(url));
    return pb;
  } catch (e) {
    log.warn('语音播放失败: $e', tag: 'Voice');
    return null;
  }
}
